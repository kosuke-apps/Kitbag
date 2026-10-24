import KitbagCore
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// Reads a grade list PDF and turns it into terms that hold only grades. The terms are matched by their title (`2024 First
/// semester`), so reading a newer report adds what is new and updates what changed, and never duplicates a term.
enum GradeReportImport {
  /// The grade scale the terms are graded on.
  static let scaleID = GradeScale.japanAA.id

  /// The courses in the PDF, or nil when it is not a grade list this reader knows.
  static func read(_ url: URL) -> [ReportedCourse]? {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard let document = PDFDocument(url: url) else { return nil }
    var lines: [String] = []
    for index in 0..<document.pageCount {
      lines += (document.page(at: index)?.string ?? "").split(whereSeparator: \.isNewline).map(String.init)
    }
    return GradeReportParser.parse(lines: lines)
  }

  /// Adds the reported terms to the library: a term with the same title is updated course by course (a course is the same when
  /// its name is), and the rest are added. Returns how many terms and courses were added or changed.
  @MainActor
  @discardableResult
  static func apply(
    _ terms: [ReportedTerm], to store: TimetableStore, scaleID: String = Self.scaleID
  ) -> (
    terms: Int, courses: Int
  ) {
    var courseCount = 0
    for reported in terms {
      let title = reported.title
      // The first versions put a school's name in front of the title (`<School> 2024 First semester`); such a term is the
      // same term, and takes the plain title.
      var term =
        store.terms.first { $0.gradesOnly && ($0.title == title || $0.title.hasSuffix(" " + title)) }
        ?? Timetable(
          title: title, year: reported.year, season: reported.season, gradeScaleID: scaleID, gradesOnly: true)
      for item in reported.courses {
        var course =
          term.courses.first { $0.code == item.name } ?? Course(code: item.name, color: color(for: term.courses.count))
        course.credits = item.credits
        course.grade = item.grade
        course.gpaMode = item.countsInGPA ? .counted : .excluded
        if let index = term.courses.firstIndex(where: { $0.id == course.id }) {
          term.courses[index] = course
        } else {
          term.courses.append(course)
        }
        courseCount += 1
      }
      term.title = title
      store.upsertTerm(term)
    }
    return (terms.count, courseCount)
  }

  private static func color(for index: Int) -> CourseColor {
    CourseColor.allCases[index % CourseColor.allCases.count]
  }
}

/// Shows what a grade list contains before anything is added: the terms, the number of courses and credits in each.
struct GradeReportPreview: View {
  @Environment(TimetableStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @Environment(\.palette) private var palette

  let courses: [ReportedCourse]
  @State private var done = false

  private var terms: [ReportedTerm] { ReportedTerm.group(courses) }

  var body: some View {
    NavigationStack {
      List {
        Section {
          Text(
            "\(courses.count) courses in \(terms.count) terms. Nothing is added until you press Import.",
            tableName: "GPA"
          )
          .font(.subheadline)
        } footer: {
          Text(
            "The terms are named by year and semester and graded on the Japan (AA, A, B, C, D) scale. The student's name and number in the report are not kept.",
            tableName: "GPA")
        }
        .listRowBackground(palette.card)
        ForEach(terms, id: \.self) { term in
          Section {
            ForEach(term.courses, id: \.self) { course in
              HStack {
                Text(course.name).font(.subheadline).lineLimit(2)
                Spacer(minLength: 8)
                Text(course.credits.formatted(.number.precision(.fractionLength(0...1))))
                  .font(.caption).foregroundStyle(.secondary)
                Text(course.grade ?? "–").font(.subheadline.weight(.semibold)).frame(minWidth: 28)
              }
            }
          } header: {
            Text(term.title)
          }
          .listRowBackground(palette.card)
        }
      }
      .scrollContentBackground(.hidden)
      .themedScreen()
      .navigationTitle(Text("Import grades", tableName: "GPA"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            dismiss()
          } label: {
            Text("Cancel", tableName: "GPA")
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            GradeReportImport.apply(terms, to: store)
            dismiss()
          } label: {
            Text("Import", tableName: "GPA")
          }
        }
      }
    }
  }
}
