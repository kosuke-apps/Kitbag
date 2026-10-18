import KitbagCore
import SwiftUI
import UniformTypeIdentifiers

extension GradeScale {
  var title: LocalizedStringResource {
    switch id {
    case "uw-madison": LocalizedStringResource("UW–Madison (A, AB, B…)", table: "GPA")
    case "us-plus-minus": LocalizedStringResource("US with plus and minus", table: "GPA")
    case "japan": LocalizedStringResource("Japan (S, A, B, C, D)", table: "GPA")
    case "tohoku": LocalizedStringResource("Tohoku University (AA, A, B, C, D)", table: "GPA")
    default: LocalizedStringResource("Grade scale", table: "GPA")
    }
  }

  /// The best grade points the scale gives.
  var top: Double { counted.compactMap(\.points).max() ?? 4 }
}

/// The GPA tool: the cumulative GPA, each term's, grades that can be entered (for any term, with or without a timetable),
/// how each course and each term counts, the person's own grading systems, and two what-if calculators.
struct GPAView: View {
  @Environment(TimetableStore.self) private var store
  @Environment(GradeScaleStore.self) private var gradeScales
  @Environment(\.titleDesign) private var design
  @Environment(\.palette) private var palette
  @AppStorage("kitbag.gradeScale") private var scaleID = GradeScale.uwMadison.id

  // What if
  @State private var imagined: [UUID: String] = [:]
  @State private var leftOut: Set<UUID> = []
  @State private var hypothetical: [Hypothetical] = []
  @State private var newCreditsText = ""
  @State private var newGrade: String?
  // Target
  @State private var target = 3.5
  @State private var plannedText = ""
  @State private var sheet: Sheet?
  @State private var importingReport = false
  @State private var reportCourses: [ReportedCourse]?
  @State private var reportFailed = false

  private enum Sheet: Identifiable {
    case course(termID: UUID, course: Course, isNew: Bool)
    case term(Timetable)
    case scales

    var id: String {
      switch self {
      case .course(_, let course, _): "course-\(course.id)"
      case .term(let term): "term-\(term.id)"
      case .scales: "scales"
      }
    }
  }

  /// A course that is only imagined: credits and a grade, in no term.
  private struct Hypothetical: Identifiable {
    let id = UUID()
    var credits: Double
    var grade: String
  }

  private var scale: GradeScale { gradeScales.scale(id: scaleID) }
  private var terms: [Timetable] { store.terms }
  private func scale(for term: Timetable) -> GradeScale { gradeScales.scale(id: term.gradeScaleID ?? scaleID) }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 18) {
          overallCard
          if terms.isEmpty {
            Text("Add a term you took, or a course, with the plus button.", tableName: "GPA")
              .font(.subheadline).foregroundStyle(.secondary)
          }
          ForEach(terms) { term in termCard(term) }
          if !openCourses.isEmpty || !terms.isEmpty {
            whatIfCard
          }
          if !terms.isEmpty { targetCard }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
      }
      .themedScreen()
      .navigationTitle(Text("GPA", tableName: "GPA"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Menu {
            Picker(selection: $scaleID) {
              ForEach(gradeScales.all) { scale in
                Text(scale.displayName).tag(scale.id)
              }
            } label: {
              Text("Grade scale", tableName: "GPA")
            }
            Button {
              sheet = .scales
            } label: {
              Label {
                Text("Edit grade scales…", tableName: "GPA")
              } icon: {
                Image(systemName: "slider.horizontal.3")
              }
            }
          } label: {
            Image(systemName: "ellipsis.circle")
          }
          .accessibilityLabel(Text("Grade scale", tableName: "GPA"))
        }
        ToolbarItem(placement: .topBarLeading) {
          Menu {
            Button {
              sheet = .term(
                Timetable(
                  year: Calendar.current.component(.year, from: Date()), season: .fall, gradesOnly: true))
            } label: {
              Label {
                Text("Add a term…", tableName: "GPA")
              } icon: {
                Image(systemName: "calendar.badge.plus")
              }
            }
            Button {
              importingReport = true
            } label: {
              Label {
                Text("Import grades from a PDF…", tableName: "GPA")
              } icon: {
                Image(systemName: "doc.text.magnifyingglass")
              }
            }
            if let current = terms.first {
              Button {
                sheet = .course(termID: current.id, course: Course(code: ""), isNew: true)
              } label: {
                Label {
                  Text("Add a course to \(current.termName)…", tableName: "GPA")
                } icon: {
                  Image(systemName: "plus")
                }
              }
            }
          } label: {
            Image(systemName: "plus")
          }
          .accessibilityLabel(Text("Add", tableName: "GPA"))
        }
      }
      .fileImporter(isPresented: $importingReport, allowedContentTypes: [.pdf]) { result in
        guard case .success(let url) = result, let courses = GradeReportImport.read(url) else {
          reportFailed = true
          return
        }
        reportCourses = courses
      }
      .sheet(
        isPresented: Binding(get: { reportCourses != nil }, set: { if !$0 { reportCourses = nil } })
      ) {
        if let reportCourses { GradeReportPreview(courses: reportCourses) }
      }
      .alert(Text("That PDF is not a grade list Kitbag can read.", tableName: "GPA"), isPresented: $reportFailed) {
        Button {
        } label: {
          Text("OK", tableName: "Notes")
        }
      } message: {
        Text("It reads the English grade list of Tohoku University.", tableName: "GPA")
      }
      .sheet(item: $sheet) { sheet in
        switch sheet {
        case .course(let termID, let course, let isNew):
          let term = store.term(id: termID)
          GPACourseEditor(course: course, termID: termID, scale: term.map(scale(for:)) ?? scale, isNew: isNew)
        case .term(let term):
          TermEditor(term: term, isNew: true) { _ in }
        case .scales:
          NavigationStack { GradeScalesView() }
        }
      }
    }
  }

  // MARK: Numbers

  /// The courses of a term as entries for the calculation: those with credits, with grades imagined for the open ones and
  /// some courses left out, for the what-if calculator.
  private func entries(_ term: Timetable, imagined: [UUID: String] = [:], leftOut: Set<UUID> = []) -> [GPA.Entry] {
    term.courses.compactMap { course in
      guard let credits = course.credits, !leftOut.contains(course.id) else { return nil }
      return GPA.Entry(credits: credits, grade: course.grade ?? imagined[course.id], mode: course.gpaMode)
    }
  }

  private func input(_ term: Timetable, imagined: [UUID: String] = [:], leftOut: Set<UUID> = []) -> GPA.TermInput {
    GPA.TermInput(
      entries: entries(term, imagined: imagined, leftOut: leftOut), scale: scale(for: term),
      included: term.countsInCumulativeGPA)
  }

  private func result(_ term: Timetable) -> GPA.Result? {
    GPA.result(of: entries(term), scale: scale(for: term))
  }

  private var overall: GPA.Result? { GPA.cumulative(terms.map { input($0) }) }

  private var earnedCredits: Double {
    terms.filter(\.countsInCumulativeGPA).reduce(0) { $0 + GPA.earnedCredits(of: entries($1), scale: scale(for: $1)) }
  }

  /// Courses with credits and no grade yet, in the terms that count, that a grade can be imagined for.
  private var openCourses: [(term: Timetable, course: Course)] {
    terms.filter(\.countsInCumulativeGPA).flatMap { term in
      term.courses.filter { $0.grade == nil && $0.credits != nil && $0.gpaMode == .counted }.map { (term, $0) }
    }
  }

  private func format(_ value: Double) -> String { String(format: "%.2f", value) }

  private func creditsText(_ credits: Double) -> String {
    credits.formatted(.number.precision(.fractionLength(0...2)))
  }

  // MARK: Cards

  private var overallCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      SectionHeading(Text("Cumulative GPA", tableName: "GPA"))
      if let overall {
        Text(format(overall.gpa)).font(.system(size: 56, weight: .semibold, design: design))
        gauge(overall.gpa)
        HStack {
          Text("Credits counted: \(format(overall.credits))", tableName: "GPA")
          Spacer()
          Text("Credits earned: \(format(earnedCredits))", tableName: "GPA")
        }
        .font(.footnote).foregroundStyle(.secondary)
      } else {
        Text("–").font(.system(size: 56, weight: .semibold, design: design)).foregroundStyle(.secondary)
        Text("Enter grades and credits to see your GPA.", tableName: "GPA").font(.footnote).foregroundStyle(.secondary)
      }
    }
    .themedCard(padding: 18, radius: 22)
  }

  private func gauge(_ value: Double) -> some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule().fill(Color.primary.opacity(0.1))
        Capsule().fill(palette.accent).frame(width: proxy.size.width * min(max(value / scale.top, 0), 1))
      }
    }
    .frame(height: 6)
    .accessibilityHidden(true)
  }

  private func termCard(_ term: Timetable) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 2) {
          Text(term.termName).font(.system(size: 19, weight: .semibold, design: design))
          if let note = termNote(term) { Text(note).font(.caption).foregroundStyle(.secondary) }
        }
        Spacer()
        if let result = result(term) {
          Text(format(result.gpa)).font(.system(size: 19, weight: .semibold, design: design))
        } else {
          Text("–").foregroundStyle(.secondary)
        }
        termMenu(term)
      }
      ForEach(term.courses) { course in
        courseRow(course, in: term)
      }
      if term.courses.isEmpty {
        Text("No courses in this term.", tableName: "GPA").font(.footnote).foregroundStyle(.secondary)
      }
    }
    .themedCard()
    .opacity(term.countsInCumulativeGPA ? 1 : 0.75)
  }

  private func termNote(_ term: Timetable) -> String? {
    var notes: [String] = []
    if let id = term.gradeScaleID {
      notes.append(L10n.string("Graded on \(gradeScales.scale(id: id).displayName)", table: "GPA"))
    }
    if !term.countsInCumulativeGPA { notes.append(L10n.string("Not in the cumulative GPA", table: "GPA")) }
    return notes.isEmpty ? nil : notes.joined(separator: " · ")
  }

  private func termMenu(_ term: Timetable) -> some View {
    Menu {
      Button {
        sheet = .course(termID: term.id, course: Course(code: ""), isNew: true)
      } label: {
        Label {
          Text("Add a course", tableName: "GPA")
        } icon: {
          Image(systemName: "plus")
        }
      }
      Picker(
        selection: Binding(
          get: { term.gradeScaleID },
          set: { id in
            var changed = term
            changed.gradeScaleID = id
            store.upsertTerm(changed)
          })
      ) {
        Text("Same as everywhere", tableName: "GPA").tag(String?.none)
        ForEach(gradeScales.all) { scale in
          Text(scale.displayName).tag(String?.some(scale.id))
        }
      } label: {
        Text("Grade scale for this term", tableName: "GPA")
      }
      Toggle(
        isOn: Binding(
          get: { term.countsInCumulativeGPA },
          set: { on in
            var changed = term
            changed.countsInCumulativeGPA = on
            store.upsertTerm(changed)
          })
      ) {
        Text("Count in the cumulative GPA", tableName: "GPA")
      }
      Button {
        sheet = .term(term)
      } label: {
        Label {
          Text("Edit the term…", tableName: "GPA")
        } icon: {
          Image(systemName: "pencil")
        }
      }
    } label: {
      Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
    }
    .accessibilityLabel(Text("Term options", tableName: "GPA"))
  }

  private func courseRow(_ course: Course, in term: Timetable) -> some View {
    HStack {
      Button {
        sheet = .course(termID: term.id, course: course, isNew: false)
      } label: {
        HStack(spacing: 8) {
          Circle().fill(course.color.strongColor).frame(width: 10, height: 10)
          Text(course.code).font(.subheadline.weight(.medium)).lineLimit(2).multilineTextAlignment(.leading)
          if let credits = course.credits {
            Text(creditsText(credits)).font(.caption).foregroundStyle(.secondary)
          } else {
            Text("add credits", tableName: "GPA").font(.caption).foregroundStyle(.orange)
          }
          if let symbol = course.gpaMode.symbol {
            Image(systemName: symbol).font(.caption).foregroundStyle(.secondary)
          }
          Spacer(minLength: 4)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      gradeMenu(for: course, in: term)
    }
  }

  private func gradeMenu(for course: Course, in term: Timetable) -> some View {
    Menu {
      Button {
        store.setGrade(nil, courseID: course.id, in: term.id)
      } label: {
        Text("Not graded yet", tableName: "GPA")
      }
      ForEach(scale(for: term).grades, id: \.label) { grade in
        Button(grade.label) { store.setGrade(grade.label, courseID: course.id, in: term.id) }
      }
    } label: {
      HStack(spacing: 4) {
        Text(course.grade ?? "–").font(.subheadline.weight(.semibold)).frame(minWidth: 28)
        Image(systemName: "chevron.up.chevron.down").font(.caption2)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(Color.primary.opacity(0.08), in: Capsule())
      .foregroundStyle(.primary)
    }
    .accessibilityLabel(Text("Grade of \(course.code)", tableName: "GPA"))
  }

  /// What the GPA would come to with grades imagined for open courses, courses imagined, and courses left out.
  private var whatIfCard: some View {
    let hypotheticalTerm = GPA.TermInput(
      entries: hypothetical.map { GPA.Entry(credits: $0.credits, grade: $0.grade) }, scale: scale)
    let projected = GPA.cumulative(terms.map { input($0, imagined: imagined, leftOut: leftOut) } + [hypotheticalTerm])
    let graded = terms.flatMap { term in term.courses.filter { $0.grade != nil && $0.credits != nil }.map { (term, $0) }
    }
    return VStack(alignment: .leading, spacing: 12) {
      SectionHeading(Text("What if", tableName: "GPA"))
      if !openCourses.isEmpty {
        Text("Imagine grades for courses that have none yet.", tableName: "GPA").font(.footnote).foregroundStyle(
          .secondary)
        ForEach(openCourses, id: \.course.id) { item in
          HStack {
            Circle().fill(item.course.color.strongColor).frame(width: 10, height: 10)
            Text(item.course.code).font(.subheadline.weight(.medium))
            Text(item.term.termName).font(.caption).foregroundStyle(.secondary)
            Spacer()
            imaginedMenu(for: item.course, scale: scale(for: item.term))
          }
        }
      }

      Divider()
      Text("Imagine a course that is not in any term.", tableName: "GPA").font(.footnote).foregroundStyle(.secondary)
      ForEach(hypothetical) { course in
        HStack {
          Text("\(creditsText(course.credits)) credits", tableName: "GPA").font(.subheadline)
          Spacer()
          Text(course.grade).font(.subheadline.weight(.semibold))
          Button {
            hypothetical.removeAll { $0.id == course.id }
          } label: {
            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text("Remove", tableName: "GPA"))
        }
      }
      HStack {
        TextField(text: $newCreditsText, prompt: Text("Credits", tableName: "GPA")) {
          Text("Credits", tableName: "GPA")
        }
        .keyboardType(.decimalPad)
        .frame(width: 80)
        Menu {
          ForEach(scale.counted, id: \.label) { grade in
            Button(grade.label) { newGrade = grade.label }
          }
        } label: {
          HStack(spacing: 4) {
            Text(newGrade ?? "–").font(.subheadline.weight(.semibold)).frame(minWidth: 28)
            Image(systemName: "chevron.up.chevron.down").font(.caption2)
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .background(palette.accent.opacity(0.15), in: Capsule())
          .foregroundStyle(.primary)
        }
        Spacer()
        Button {
          addHypothetical()
        } label: {
          Label {
            Text("Add", tableName: "GPA")
          } icon: {
            Image(systemName: "plus.circle.fill")
          }
        }
        .disabled(Double(newCreditsText.replacingOccurrences(of: ",", with: ".")) == nil || newGrade == nil)
      }

      if !graded.isEmpty {
        DisclosureGroup {
          ForEach(graded, id: \.1.id) { item in
            Toggle(
              isOn: Binding(
                get: { !leftOut.contains(item.1.id) },
                set: { on in
                  if on { leftOut.remove(item.1.id) } else { leftOut.insert(item.1.id) }
                })
            ) {
              HStack {
                Text(item.1.code).font(.subheadline)
                Text(item.0.termName).font(.caption).foregroundStyle(.secondary)
              }
            }
          }
        } label: {
          Text("Leave courses out", tableName: "GPA").font(.subheadline)
        }
      }

      Divider()
      HStack {
        VStack(alignment: .leading) {
          Text("Now", tableName: "GPA").font(.caption).foregroundStyle(.secondary)
          Text(overall.map { format($0.gpa) } ?? "–").font(.title3.weight(.semibold))
        }
        Spacer()
        if let projected, let overall {
          Image(systemName: projected.gpa >= overall.gpa ? "arrow.up.right" : "arrow.down.right")
            .foregroundStyle(projected.gpa >= overall.gpa ? Color.green : Color.red)
        }
        Spacer()
        VStack(alignment: .trailing) {
          Text("What if", tableName: "GPA").font(.caption).foregroundStyle(.secondary)
          Text(projected.map { format($0.gpa) } ?? "–").font(.title3.weight(.semibold))
        }
      }
      if !imagined.isEmpty || !hypothetical.isEmpty || !leftOut.isEmpty {
        Button(role: .destructive) {
          imagined = [:]
          hypothetical = []
          leftOut = []
        } label: {
          Text("Start over", tableName: "GPA").font(.footnote)
        }
      }
    }
    .themedCard()
  }

  private func imaginedMenu(for course: Course, scale: GradeScale) -> some View {
    Menu {
      Button {
        imagined[course.id] = nil
      } label: {
        Text("No grade", tableName: "GPA")
      }
      ForEach(scale.counted, id: \.label) { grade in
        Button(grade.label) { imagined[course.id] = grade.label }
      }
    } label: {
      HStack(spacing: 4) {
        Text(imagined[course.id] ?? "–").font(.subheadline.weight(.semibold)).frame(minWidth: 28)
        Image(systemName: "chevron.up.chevron.down").font(.caption2)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(palette.accent.opacity(0.15), in: Capsule())
      .foregroundStyle(.primary)
    }
  }

  private func addHypothetical() {
    guard let credits = Double(newCreditsText.replacingOccurrences(of: ",", with: ".")), let grade = newGrade else {
      return
    }
    hypothetical.append(Hypothetical(credits: credits, grade: grade))
    newCreditsText = ""
  }

  /// What the next credits must average to reach a target GPA, and the lowest grade that does it.
  private var targetCard: some View {
    let openCredits = openCourses.compactMap(\.course.credits).reduce(0, +)
    let planned = Double(plannedText.replacingOccurrences(of: ",", with: ".")) ?? openCredits
    let needed = GPA.requiredAverage(current: overall, plannedCredits: planned, target: target)
    return VStack(alignment: .leading, spacing: 10) {
      SectionHeading(Text("Target", tableName: "GPA"))
      Stepper(value: $target, in: 0...scale.top, step: 0.05) {
        LabeledContent {
          Text(format(target)).font(.title3.weight(.semibold))
        } label: {
          Text("Target GPA", tableName: "GPA")
        }
      }
      LabeledContent {
        TextField(text: $plannedText, prompt: Text(format(openCredits))) {
          Text("Credits still to earn", tableName: "GPA")
        }
        .multilineTextAlignment(.trailing)
        .keyboardType(.decimalPad)
        .frame(width: 90)
      } label: {
        Text("Credits still to earn", tableName: "GPA")
      }
      if let needed {
        if needed > scale.top + 1e-9 {
          Text("Out of reach: it would need more than the top grade.", tableName: "GPA").foregroundStyle(.red)
        } else if needed <= 0 {
          Text("Already safe: any grade keeps you at or above the target.", tableName: "GPA").foregroundStyle(.green)
        } else {
          Text("Needs an average of \(format(needed)) on those credits.", tableName: "GPA").font(
            .subheadline.weight(.medium))
          if let grade = GPA.lowestGrade(reaching: needed, scale: scale) {
            Text("That is \(grade) or better on average.", tableName: "GPA").font(.footnote).foregroundStyle(.secondary)
          }
        }
      } else {
        Text("Enter the credits you still have to earn.", tableName: "GPA").font(.footnote).foregroundStyle(.secondary)
      }
    }
    .themedCard()
  }
}
