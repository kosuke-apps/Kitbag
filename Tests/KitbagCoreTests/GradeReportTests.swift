import Foundation
import Testing

@testable import KitbagCore

/// An invented report in the layout of the real one: wrapped columns, a wrapped subject name, instructor names that run into
/// the semester column, a course still being taken, and summary pages after the list.
private let sample = """
  Grade list
  X0AA0000 EXAMPLE PERSON
  Year 3
  Faculty of Examples
  Subject Credit
  s
  Subject f
  Assessmen
  t or calcul
  ating GPA
  Year
  Semester
  Faculty name
  General Education Subjects
  Foundations
  Navigating Academia
  Introduction to Examples
  2.0 AA ○ 2024 Second semAAA BBB
  ester C
  Humanities
  History
  2.0 A ○ 2024 Second semCCC DDD EEE
  ester F
  Languages
  English
  English I-A
  1.0 B ○ 2024 Second sem
  ester
  Career Education
  Special Lecture of Career Education (Digital Entr
  epreneurship Seminar) 2.0 AA ○ 2025 Second semGGG
  ester
  Pass Fail Course
  1.0 P 2025 First semeHHH
  ster
  (Note)The subject that ※ is output in the beginning of its name is being registered now.
  1/ 6 2026/10/14(Wed) 10:56
  Grade list
  X0AA0000 EXAMPLE PERSON
  Specialized Education Subjects
  Mathematics I
  2.0 C ○ 2025 First semeIII JJJ
  ster
  Seminar I
  2.0 A ○ 2025 Second semKKK
  ester
  * 1.0 Seminar II
  2026 Second semLLL
  ester
  Summary of acquired credits
  X0AA0000 EXAMPLE PERSON
  Total
  111.0
  1.0
  112.0
  """.split(separator: "\n").map(String.init)

@Suite("GradeReport")
struct GradeReportTests {
  @Test func readsTheCoursesOfAReport() throws {
    let courses = try #require(GradeReportParser.parse(lines: sample))
    #expect(
      courses.map(\.name) == [
        "Introduction to Examples", "History", "English I-A",
        "Special Lecture of Career Education (Digital Entrepreneurship Seminar)",
        "Pass Fail Course", "Mathematics I", "Seminar I", "Seminar II",
      ])
    #expect(courses.map(\.credits) == [2, 2, 1, 2, 1, 2, 2, 1])
    #expect(courses.map(\.grade) == ["AA", "A", "B", "AA", "P", "C", "A", nil])
    #expect(courses.map(\.countsInGPA) == [true, true, true, true, false, true, true, true])
  }

  @Test func readsYearAndSemester() throws {
    let courses = try #require(GradeReportParser.parse(lines: sample))
    #expect(courses[0].year == 2024)
    #expect(courses[0].semester == .second)
    #expect(courses[4].semester == .first)
    #expect(courses[7].year == 2026)
    #expect(courses[7].semester == .second)
  }

  @Test func leavesOutTheSummaryAndThePerson() throws {
    let courses = try #require(GradeReportParser.parse(lines: sample))
    #expect(courses.allSatisfy { !$0.name.contains("EXAMPLE") && !$0.name.contains("Total") })
    #expect(courses.count == 8)
  }

  @Test func refusesTextThatIsNotAReport() {
    #expect(GradeReportParser.parse(lines: ["Hello", "2.0 AA ○ 2024 Second semester"]) == nil)
    #expect(GradeReportParser.parse(lines: ["Grade list", "nothing else"]) == nil)
    #expect(GradeReportParser.parse(lines: []) == nil)
  }

  @Test func groupsCoursesIntoTermsOldestFirst() throws {
    let courses = try #require(GradeReportParser.parse(lines: sample))
    let terms = ReportedTerm.group(courses)
    #expect(
      terms.map { "\($0.year)-\($0.semester.rawValue)" } == ["2024-second", "2025-first", "2025-second", "2026-second"])
    #expect(terms[0].courses.count == 3)
    #expect(terms[0].title(prefix: "Tohoku") == "Tohoku 2024 Second semester")
    #expect(terms[1].season == .spring)
    #expect(terms[0].season == .fall)
  }

  @Test func theTohokuScaleCountsAAThroughD() {
    let scale = GradeScale.tohoku
    #expect(scale.points(for: "AA") == 4)
    #expect(scale.points(for: "A") == 3)
    #expect(scale.points(for: "D") == 0)
    #expect(scale.earnsCredit("C"))
    #expect(!scale.earnsCredit("D"))
    #expect(GradeScale.scale(id: "tohoku").id == "tohoku")
  }
}
