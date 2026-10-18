import Foundation
import Testing

@testable import KitbagCore

private let calendar: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "America/Chicago")!
  return calendar
}()

private func day(_ month: Int, _ day: Int, year: Int = 2026) -> LocalDate {
  LocalDate(year: year, month: month, day: day)
}

private func moment(_ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
  calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
}

private func monday(at hour: Int) -> Course {
  Course(
    code: "A 1",
    meetings: [
      Meeting(
        kind: "LEC", section: "001", days: [.monday], start: TimeOfDay(hour: hour, minute: 0),
        end: TimeOfDay(hour: hour + 1, minute: 0))
    ])
}

@Suite("Term")
struct TermTests {
  @Test func countsEveryDayWhenThereAreNoDates() {
    let term = Timetable(courses: [])
    #expect(term.contains(day(1, 1)))
    #expect(!term.hasDates)
  }

  @Test func containsDaysWithinItsDates() {
    let term = Timetable(startDate: day(9, 2), endDate: day(12, 9))
    #expect(term.contains(day(9, 2)))
    #expect(term.contains(day(12, 9)))
    #expect(!term.contains(day(9, 1)))
    #expect(!term.contains(day(12, 10)))
    let openEnded = Timetable(startDate: day(9, 2))
    #expect(openEnded.contains(day(12, 31)))
    #expect(!openEnded.contains(day(8, 31)))
  }

  @Test func numbersTheWeeksFromTheFirstDay() {
    let term = Timetable(startDate: day(9, 2), endDate: day(12, 9))
    #expect(term.weekNumber(on: day(9, 2), calendar: calendar) == 1)
    #expect(term.weekNumber(on: day(9, 8), calendar: calendar) == 1)
    #expect(term.weekNumber(on: day(9, 9), calendar: calendar) == 2)
    #expect(term.weekNumber(on: day(9, 1), calendar: calendar) == nil)
    #expect(term.totalWeeks(calendar: calendar) == 15)
    #expect(Timetable().weekNumber(on: day(9, 2), calendar: calendar) == nil)
    #expect(Timetable(startDate: day(9, 2)).totalWeeks(calendar: calendar) == nil)
  }

  @Test func holdsNoClassesOutsideItsDates() {
    let term = Timetable(startDate: day(10, 26), endDate: day(12, 9), courses: [monday(at: 9)])
    #expect(term.slots(on: day(10, 19), calendar: calendar).isEmpty)  // a Monday before the term
    #expect(term.slots(on: day(10, 26), calendar: calendar).count == 1)
    #expect(term.slots(on: day(12, 14), calendar: calendar).isEmpty)  // a Monday after it
  }

  @Test func looksForTheNextClassOnlyInsideTheTerm() throws {
    let notStarted = Timetable(startDate: day(10, 26), endDate: day(12, 9), courses: [monday(at: 9)])
    let first = try #require(notStarted.upcoming(after: moment(10, 19), calendar: calendar))
    #expect(first.start == calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 9)))

    let over = Timetable(startDate: day(9, 2), endDate: day(10, 21), courses: [monday(at: 9)])
    #expect(over.upcoming(after: moment(10, 22), calendar: calendar) == nil)
  }

  @Test func sumsCredits() {
    let term = Timetable(courses: [Course(code: "A", credits: 3), Course(code: "B", credits: 1.5), Course(code: "C")])
    #expect(term.totalCredits == 4.5)
  }

  @Test func readsAnOldFileWithoutTermFields() throws {
    let json = #"{"version": 1, "title": "Old", "courses": [{"code": "X 1"}]}"#
    let term = try Timetable(fileData: Data(json.utf8))
    #expect(term.title == "Old")
    #expect(term.year == nil)
    #expect(term.startDate == nil)
    #expect(term.courses[0].credits == nil)
  }

  @Test func roundTripsTermFieldsAndGrades() throws {
    let term = Timetable(
      title: "T", year: 2026, season: .fall, startDate: day(9, 2), endDate: day(12, 9),
      courses: [Course(code: "A", credits: 3, grade: "AB")])
    let loaded = try Timetable(fileData: try term.fileData())
    #expect(loaded == term)
    #expect(loaded.courses[0].grade == "AB")
  }

  @Test func listsInstructorsOnce() {
    let course = Course(
      code: "A",
      meetings: [
        Meeting(
          kind: "LEC", section: "1", days: [.monday], start: TimeOfDay(hour: 9, minute: 0),
          end: TimeOfDay(hour: 10, minute: 0), instructor: "Ann"),
        Meeting(
          kind: "LAB", section: "2", days: [.tuesday], start: TimeOfDay(hour: 9, minute: 0),
          end: TimeOfDay(hour: 10, minute: 0), instructor: "Ann"),
        Meeting(
          kind: "DIS", section: "3", days: [.friday], start: TimeOfDay(hour: 9, minute: 0),
          end: TimeOfDay(hour: 10, minute: 0), instructor: "Bo"),
      ])
    #expect(course.instructors == ["Ann", "Bo"])
  }
}

@Suite("TimetableLibrary")
struct TimetableLibraryTests {
  private let spring = Timetable(
    title: "Spring", year: 2026, season: .spring, startDate: day(1, 20), endDate: day(5, 8))
  private let fall = Timetable(title: "Fall", year: 2026, season: .fall, startDate: day(9, 2), endDate: day(12, 9))
  private let next = Timetable(
    title: "Next", year: 2027, season: .spring, startDate: day(1, 19, year: 2027), endDate: day(5, 7, year: 2027))

  @Test func picksTheTermThatContainsToday() {
    let library = TimetableLibrary(timetables: [spring, fall, next])
    #expect(library.active(on: moment(3, 1), calendar: calendar)?.title == "Spring")
    #expect(library.active(on: moment(10, 18), calendar: calendar)?.title == "Fall")
  }

  @Test func fallsBackToTheLatestTermThatBegan() {
    let library = TimetableLibrary(timetables: [spring, fall, next])
    #expect(library.active(on: moment(7, 1), calendar: calendar)?.title == "Spring")
    #expect(library.active(on: moment(12, 20), calendar: calendar)?.title == "Fall")
  }

  @Test func usesThePreferredTermWhenNothingHasBegun() {
    let library = TimetableLibrary(timetables: [fall, next], preferredID: next.id)
    #expect(library.active(on: moment(3, 1), calendar: calendar)?.title == "Next")
    #expect(TimetableLibrary(timetables: [fall]).active(on: moment(3, 1), calendar: calendar)?.title == "Fall")
    #expect(TimetableLibrary().active(on: moment(3, 1), calendar: calendar) == nil)
  }

  @Test func usesATermWithoutDatesWhenItIsTheOnlyOne() {
    let undated = Timetable(title: "Undated")
    #expect(TimetableLibrary(timetables: [undated]).active(on: moment(3, 1), calendar: calendar)?.title == "Undated")
  }

  @Test func listsTheLatestTermFirst() {
    let library = TimetableLibrary(timetables: [spring, next, fall, Timetable(title: "Undated")])
    #expect(library.ordered.map(\.title) == ["Next", "Fall", "Spring", "Undated"])
  }

  @Test func addsReplacesAndRemoves() {
    var library = TimetableLibrary(timetables: [fall], preferredID: fall.id)
    var changed = fall
    changed.title = "Renamed"
    library.upsert(changed)
    library.upsert(spring)
    #expect(library.timetables.count == 2)
    #expect(library.timetable(id: fall.id)?.title == "Renamed")
    library.remove(id: fall.id)
    #expect(library.timetables.count == 1)
    #expect(library.preferredID == nil)
  }

  @Test func startsANewTermFromAnOldOne() {
    let course = Course(
      code: "A",
      meetings: [
        Meeting(
          kind: "LEC", section: "1", days: [.monday], start: TimeOfDay(hour: 9, minute: 0),
          end: TimeOfDay(hour: 10, minute: 0))
      ], credits: 3, grade: "B")
    let old = Timetable(courses: [course])
    let copies = TimetableLibrary().continuing(from: old)
    #expect(copies.count == 1)
    #expect(copies[0].id != course.id)
    #expect(copies[0].meetings[0].id != course.meetings[0].id)
    #expect(copies[0].grade == nil)
    #expect(copies[0].credits == 3)
    #expect(copies[0].code == "A")
  }

  @Test func roundTripsThroughAFile() throws {
    let library = TimetableLibrary(timetables: [spring, fall], preferredID: fall.id)
    #expect(try TimetableLibrary(fileData: library.fileData()) == library)
  }
}

@Suite("Grades")
struct GradeTests {
  private let uw = GradeScale.uwMadison

  @Test func knowsTheUWScale() {
    #expect(uw.points(for: "A") == 4.0)
    #expect(uw.points(for: "AB") == 3.5)
    #expect(uw.points(for: "BC") == 2.5)
    #expect(uw.points(for: "F") == 0.0)
    #expect(uw.points(for: "S") == nil)
    #expect(uw.contains("S"))
    #expect(!uw.contains("A+"))
  }

  @Test func averagesByCredits() throws {
    let result = try #require(
      GPA.result(of: [GPA.Entry(credits: 4, grade: "A"), GPA.Entry(credits: 2, grade: "BC")], scale: uw))
    #expect(result.credits == 6)
    #expect(result.points == 4 * 4.0 + 2 * 2.5)
    #expect(abs(result.gpa - 3.5) < 1e-9)
  }

  @Test func leavesOutWhatDoesNotCount() throws {
    let result = try #require(
      GPA.result(
        of: [
          GPA.Entry(credits: 3, grade: "B"), GPA.Entry(credits: 3, grade: "S"), GPA.Entry(credits: 3, grade: nil),
          GPA.Entry(credits: 0, grade: "A"), GPA.Entry(credits: 3, grade: "nonsense"),
        ], scale: uw))
    #expect(result.credits == 3)
    #expect(result.gpa == 3.0)
  }

  @Test func hasNoResultWithoutGrades() {
    #expect(GPA.result(of: [GPA.Entry(credits: 3, grade: nil)], scale: uw) == nil)
    #expect(GPA.result(of: [], scale: uw) == nil)
  }

  @Test func addsResultsAcrossTerms() throws {
    let a = try #require(GPA.result(of: [GPA.Entry(credits: 3, grade: "A")], scale: uw))
    let b = try #require(GPA.result(of: [GPA.Entry(credits: 3, grade: "C")], scale: uw))
    #expect((a + b).gpa == 3.0)
  }

  @Test func findsTheAverageNeededForATarget() throws {
    let current = GPA.Result(credits: 30, points: 105)  // a 3.5 so far
    let needed = try #require(GPA.requiredAverage(current: current, plannedCredits: 15, target: 3.6))
    #expect(abs(needed - 3.8) < 1e-9)
    #expect(GPA.requiredAverage(current: nil, plannedCredits: 12, target: 3.0) == 3.0)
    #expect(GPA.requiredAverage(current: current, plannedCredits: 0, target: 3.6) == nil)
  }

  @Test func findsTheLowestGradeThatReachesAnAverage() {
    #expect(GPA.lowestGrade(reaching: 3.8, scale: uw) == "A")
    #expect(GPA.lowestGrade(reaching: 3.5, scale: uw) == "AB")
    #expect(GPA.lowestGrade(reaching: 2.6, scale: uw) == "B")
    #expect(GPA.lowestGrade(reaching: -1, scale: uw) == "F")
    #expect(GPA.lowestGrade(reaching: 4.2, scale: uw) == nil)
  }

  @Test func listsTheScalesAndFallsBack() {
    #expect(GradeScale.all.map(\.id) == ["uw-madison", "us-plus-minus", "japan"])
    #expect(GradeScale.scale(id: "japan").points(for: "S") == 4.0)
    #expect(GradeScale.scale(id: "unknown").id == "uw-madison")
    #expect(GradeScale.usPlusMinus.points(for: "A-") == 3.7)
  }
}
