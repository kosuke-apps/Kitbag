import KitbagCore
import SwiftUI

extension GradeScale {
  var title: LocalizedStringResource {
    switch id {
    case "uw-madison": LocalizedStringResource("UW–Madison (A, AB, B…)", table: "GPA")
    case "us-plus-minus": LocalizedStringResource("US with plus and minus", table: "GPA")
    case "japan": LocalizedStringResource("Japan (S, A, B, C, D)", table: "GPA")
    default: LocalizedStringResource("Grade scale", table: "GPA")
    }
  }

  /// The best grade points the scale gives.
  var top: Double { counted.compactMap(\.points).max() ?? 4 }
}

/// The GPA tool: the cumulative GPA, each term's, grades that can be entered, and two what-if calculators: what a term
/// would come to with imagined grades, and what the next grades must average to reach a target.
struct GPAView: View {
  @Environment(TimetableStore.self) private var store
  @Environment(\.titleDesign) private var design
  @Environment(\.palette) private var palette
  @AppStorage("kitbag.gradeScale") private var scaleID = GradeScale.uwMadison.id

  @State private var imagined: [UUID: String] = [:]
  @State private var target = 3.5
  @State private var plannedText = ""

  private var scale: GradeScale { .scale(id: scaleID) }
  private var terms: [Timetable] { store.terms }
  private var currentTerm: Timetable { store.timetable }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 18) {
          overallCard
          if terms.isEmpty {
            Text("Add a term and its courses in the timetable first.", tableName: "GPA")
              .font(.subheadline).foregroundStyle(.secondary)
          }
          ForEach(terms) { term in termCard(term) }
          if !currentTerm.courses.isEmpty {
            imaginedCard
            targetCard
          }
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
              ForEach(GradeScale.all) { scale in
                Text(scale.title).tag(scale.id)
              }
            } label: {
              Text("Grade scale", tableName: "GPA")
            }
          } label: {
            Image(systemName: "ellipsis.circle")
          }
          .accessibilityLabel(Text("Grade scale", tableName: "GPA"))
        }
      }
    }
  }

  // MARK: Numbers

  private func entries(_ term: Timetable, imagined: [UUID: String] = [:]) -> [GPA.Entry] {
    term.courses.compactMap { course in
      course.credits.map { GPA.Entry(credits: $0, grade: course.grade ?? imagined[course.id]) }
    }
  }

  private func result(_ term: Timetable) -> GPA.Result? { GPA.result(of: entries(term), scale: scale) }

  private func sum(_ results: [GPA.Result]) -> GPA.Result? {
    guard var total = results.first else { return nil }
    for next in results.dropFirst() { total = total + next }
    return total
  }

  private var overall: GPA.Result? { sum(terms.compactMap(result)) }

  private func format(_ value: Double) -> String { String(format: "%.2f", value) }

  // MARK: Cards

  private var overallCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      SectionHeading(Text("Cumulative GPA", tableName: "GPA"))
      if let overall {
        Text(format(overall.gpa)).font(.system(size: 56, weight: .semibold, design: design))
        gauge(overall.gpa)
        Text("Credits counted: \(format(overall.credits))", tableName: "GPA")
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
        Text(term.termName).font(.system(size: 19, weight: .semibold, design: design))
        Spacer()
        if let result = result(term) {
          Text(format(result.gpa)).font(.system(size: 19, weight: .semibold, design: design))
        } else {
          Text("–").foregroundStyle(.secondary)
        }
      }
      ForEach(term.courses) { course in
        HStack {
          Circle().fill(course.color.strongColor).frame(width: 10, height: 10)
          Text(course.code).font(.subheadline.weight(.medium))
          if let credits = course.credits { Text(creditsText(credits)).font(.caption).foregroundStyle(.secondary) }
          Spacer()
          gradeMenu(for: course, in: term)
        }
      }
      if term.courses.isEmpty {
        Text("No courses in this term.", tableName: "GPA").font(.footnote).foregroundStyle(.secondary)
      }
    }
    .themedCard()
  }

  private func gradeMenu(for course: Course, in term: Timetable) -> some View {
    Menu {
      Button {
        store.setGrade(nil, courseID: course.id, in: term.id)
      } label: {
        Text("Not graded yet", tableName: "GPA")
      }
      ForEach(scale.grades, id: \.label) { grade in
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
    .disabled(course.credits == nil)
    .accessibilityLabel(Text("Grade of \(course.code)", tableName: "GPA"))
  }

  /// What the current term and the overall GPA come to, with grades imagined for the courses that have none yet.
  private var imaginedCard: some View {
    let open = currentTerm.courses.filter { $0.grade == nil && $0.credits != nil }
    let projectedTerm = GPA.result(of: entries(currentTerm, imagined: imagined), scale: scale)
    let others = sum(terms.filter { $0.id != currentTerm.id }.compactMap(result))
    let projectedOverall = sum([others, projectedTerm].compactMap { $0 })
    return VStack(alignment: .leading, spacing: 10) {
      SectionHeading(Text("What if", tableName: "GPA"))
      Text("Imagine grades for \(currentTerm.termName).", tableName: "GPA").font(.footnote).foregroundStyle(.secondary)
      ForEach(open) { course in
        HStack {
          Circle().fill(course.color.strongColor).frame(width: 10, height: 10)
          Text(course.code).font(.subheadline.weight(.medium))
          Spacer()
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
      }
      if open.isEmpty {
        Text("Every course of this term has a grade.", tableName: "GPA").font(.footnote).foregroundStyle(.secondary)
      }
      Divider()
      HStack {
        VStack(alignment: .leading) {
          Text("This term", tableName: "GPA").font(.caption).foregroundStyle(.secondary)
          Text(projectedTerm.map { format($0.gpa) } ?? "–").font(.title3.weight(.semibold))
        }
        Spacer()
        VStack(alignment: .trailing) {
          Text("Overall", tableName: "GPA").font(.caption).foregroundStyle(.secondary)
          Text(projectedOverall.map { format($0.gpa) } ?? "–").font(.title3.weight(.semibold))
        }
      }
    }
    .themedCard()
  }

  /// What the next credits must average to reach a target GPA, and the lowest grade that does it.
  private var targetCard: some View {
    let openCredits = currentTerm.courses.filter { $0.grade == nil }.compactMap(\.credits).reduce(0, +)
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
