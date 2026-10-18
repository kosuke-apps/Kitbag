import Foundation
import Testing

@testable import KitbagCore

@Suite("GPA options")
struct GPAOptionsTests {
  private let scale = GradeScale.uwMadison

  @Test func leavesOutExcludedAndPassFailCourses() {
    let entries = [
      GPA.Entry(credits: 3, grade: "A"), GPA.Entry(credits: 3, grade: "C"),
      GPA.Entry(credits: 3, grade: "A", mode: .excluded), GPA.Entry(credits: 4, grade: "S", mode: .passFail),
    ]
    let result = GPA.result(of: entries, scale: scale)
    #expect(result?.credits == 6)
    #expect(result?.gpa == 3.0)
    #expect(GPA.result(of: [GPA.Entry(credits: 3, grade: "A", mode: .excluded)], scale: scale) == nil)
  }

  @Test func countsEarnedCreditsApartFromTheGPA() {
    let entries = [
      GPA.Entry(credits: 3, grade: "B"), GPA.Entry(credits: 3, grade: "F"),
      GPA.Entry(credits: 2, grade: "S", mode: .passFail),
      GPA.Entry(credits: 2, grade: "U", mode: .passFail), GPA.Entry(credits: 4, grade: "A", mode: .excluded),
      GPA.Entry(credits: 3, grade: nil),
    ]
    #expect(GPA.earnedCredits(of: entries, scale: scale) == 9)
  }

  @Test func addsUpTermsOnTheirOwnScalesAndSkipsLeftOutTerms() {
    let home = GPA.TermInput(
      entries: [GPA.Entry(credits: 3, grade: "A"), GPA.Entry(credits: 3, grade: "B")], scale: .uwMadison)
    let abroad = GPA.TermInput(entries: [GPA.Entry(credits: 4, grade: "S")], scale: .japan)
    let leftOut = GPA.TermInput(entries: [GPA.Entry(credits: 4, grade: "A")], scale: .uwMadison, included: false)
    let cumulative = GPA.cumulative([home, abroad, leftOut])
    // 3 × 4.0 + 3 × 3.0 on UW's scale, plus 4 × 4.0 for S on the Japanese one.
    #expect(cumulative?.credits == 10)
    #expect(cumulative?.points == 37.0)
    #expect(GPA.cumulative([leftOut]) == nil)
    #expect(GPA.cumulative([]) == nil)
  }

  @Test func readsAScaleThePersonWrote() throws {
    let mine = GradeScale(
      id: "custom-1", name: "Abroad",
      grades: [
        .init(label: "1", points: 4.0), .init(label: "2", points: 3.0), .init(label: "3", points: 2.0),
        .init(label: "4", points: 0.0), .init(label: "Pass", points: nil, earnsCredit: true),
      ])
    let data = try JSONEncoder().encode(mine)
    let back = try JSONDecoder().decode(GradeScale.self, from: data)
    #expect(back == mine)
    #expect(GradeScale.scale(id: "custom-1", custom: [mine]).name == "Abroad")
    #expect(GradeScale.scale(id: "unknown", custom: [mine]).id == "uw-madison")
    #expect(mine.earnsCredit("Pass"))
    #expect(!mine.earnsCredit("4"))
    #expect(mine.earnsCredit("2"))
    #expect(
      GPA.result(of: [GPA.Entry(credits: 2, grade: "2"), GPA.Entry(credits: 2, grade: "Pass")], scale: mine)?.gpa == 3.0
    )
  }

  @Test func savesTheOptionsOnlyWhenTheyAreNotTheDefaults() throws {
    let plain = Course(code: "A 1", credits: 3, grade: "A")
    let plainJSON = String(decoding: try JSONEncoder().encode(plain), as: UTF8.self)
    #expect(!plainJSON.contains("gpaMode"))
    var changed = plain
    changed.gpaMode = .excluded
    #expect(try JSONDecoder().decode(Course.self, from: try JSONEncoder().encode(changed)).gpaMode == .excluded)

    let term = Timetable(title: "Old", courses: [plain])
    let termJSON = String(decoding: try term.fileData(), as: UTF8.self)
    #expect(!termJSON.contains("gradeScaleID"))
    #expect(!termJSON.contains("countsInCumulativeGPA"))
    #expect(!termJSON.contains("gradesOnly"))
    let special = Timetable(
      title: "Abroad", courses: [plain], gradeScaleID: "japan", countsInCumulativeGPA: false, gradesOnly: true)
    let back = try Timetable(fileData: try special.fileData())
    #expect(back.gradeScaleID == "japan")
    #expect(!back.countsInCumulativeGPA)
    #expect(back.gradesOnly)
  }

  @Test func aGradesOnlyTermIsNeverTheTermInForce() {
    let current = Timetable(
      title: "Now", startDate: LocalDate(year: 2026, month: 9, day: 1),
      endDate: LocalDate(year: 2026, month: 12, day: 15),
      courses: [
        Course(
          code: "X 1",
          meetings: [
            Meeting(
              kind: "LEC", section: "1", days: [.monday], start: TimeOfDay(hour: 9, minute: 0),
              end: TimeOfDay(hour: 10, minute: 0))
          ])
      ])
    let old = Timetable(
      title: "Old", startDate: LocalDate(year: 2026, month: 9, day: 1),
      endDate: LocalDate(year: 2026, month: 12, day: 15),
      courses: [Course(code: "Y 2", credits: 3, grade: "A")], gradesOnly: true)
    let library = TimetableLibrary(timetables: [old, current])
    let calendar = Calendar(identifier: .gregorian)
    let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18)) ?? Date()
    #expect(library.active(on: day, calendar: calendar)?.title == "Now")
    // Alone, it is all there is.
    #expect(TimetableLibrary(timetables: [old]).active(on: day, calendar: calendar)?.title == "Old")
    // Once it has a class it is a timetable again.
    var withClass = old
    withClass.courses[0].meetings = current.courses[0].meetings
    #expect(!withClass.isGradesOnly)
  }
}
