import Foundation
import Testing

@testable import KitbagCore

// The fixtures are invented courses; a real timetable is personal data and never goes into the repository.

private let calendar: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "America/Chicago")!
  return calendar
}()

/// A date in the fixture calendar. 2026-10-19 is a Monday.
private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
  calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

private func time(_ hour: Int, _ minute: Int = 0) -> TimeOfDay { TimeOfDay(hour: hour, minute: minute) }

private let alpha = Course(
  code: "A 100", title: "Alpha", color: .lavender,
  meetings: [
    Meeting(
      kind: "LEC", section: "001", days: [.monday, .wednesday, .friday], start: time(9), end: time(9, 50),
      location: "Hall 1", instructor: "Prof A")
  ])
private let beta = Course(
  code: "B 200", title: "Beta", color: .mint,
  meetings: [
    Meeting(kind: "LEC", section: "001", days: [.tuesday, .thursday], start: time(13), end: time(14, 15)),
    Meeting(kind: "LAB", section: "301", days: [.wednesday], start: time(15, 30), end: time(17, 30)),
  ])
private let gamma = Course(
  code: "C 300", title: "Gamma", color: .rose,
  meetings: [Meeting(kind: "LEC", section: "002", days: [.monday], start: time(13, 20), end: time(14, 10))])

private let timetable = Timetable(title: "Test term", courses: [beta, gamma, alpha])

@Suite("TimeOfDay")
struct TimeOfDayTests {
  @Test func readsTwentyFourHourText() {
    #expect(TimeOfDay("8:50")?.minutes == 530)
    #expect(TimeOfDay("13:20")?.minutes == 800)
    #expect(TimeOfDay("24:00")?.minutes == 1440)
    #expect(TimeOfDay("08:05")?.minutes == 485)
  }

  @Test func rejectsWhatIsNotATime() {
    for text in ["", "8", "8:5", "8:60", "25:00", "24:01", "a:bc", "8:50:00", "-1:00"] {
      #expect(TimeOfDay(text) == nil, "\(text)")
    }
  }

  @Test func writesBothClockStyles() {
    #expect(time(13, 20).text == "13:20")
    #expect(time(13, 20).twelveHourText == "1:20")
    #expect(time(0, 5).twelveHourText == "12:05")
    #expect(time(12).twelveHourText == "12:00")
    #expect(time(8, 50).twelveHourText == "8:50")
  }

  @Test func isWrittenAsText() throws {
    let data = try JSONEncoder().encode(["at": time(13, 20)])
    #expect(String(decoding: data, as: UTF8.self) == #"{"at":"13:20"}"#)
    #expect(try JSONDecoder().decode([String: TimeOfDay].self, from: data)["at"] == time(13, 20))
  }

  @Test func clampsToTheDay() {
    #expect(TimeOfDay(minutes: -5).minutes == 0)
    #expect(TimeOfDay(minutes: 5000).minutes == 1440)
  }
}

@Suite("Weekday")
struct WeekdayTests {
  @Test func followsTheCalendar() {
    #expect(Weekday(date: date(19, 12), calendar: calendar) == .monday)
    #expect(Weekday(date: date(23, 12), calendar: calendar) == .friday)
    #expect(Weekday(date: date(24, 12), calendar: calendar) == .saturday)
    #expect(Weekday(date: date(25, 12), calendar: calendar) == .sunday)
  }

  @Test func indexesCalendarSymbols() {
    #expect(Weekday.monday.calendarSymbolIndex == 1)
    #expect(Weekday.saturday.calendarSymbolIndex == 6)
    #expect(Weekday.sunday.calendarSymbolIndex == 0)
  }
}

@Suite("Timetable")
struct TimetableTests {
  @Test func listsADaysClassesEarliestFirst() {
    let monday = timetable.slots(on: .monday)
    #expect(monday.map(\.course.code) == ["A 100", "C 300"])
    #expect(timetable.slots(on: .wednesday).map(\.meeting.label) == ["LEC 001", "LAB 301"])
    #expect(timetable.slots(on: .saturday).isEmpty)
  }

  @Test func findsTheClassInProgress() throws {
    let found = try #require(timetable.upcoming(after: date(19, 9, 30), calendar: calendar))
    #expect(found.slot.course.code == "A 100")
    #expect(found.isInProgress(at: date(19, 9, 30)))
    #expect(found.start == date(19, 9))
    #expect(found.end == date(19, 9, 50))
  }

  @Test func findsTheNextClassLaterTheSameDay() throws {
    let before = try #require(timetable.upcoming(after: date(19, 8), calendar: calendar))
    #expect(before.slot.course.code == "A 100")
    #expect(!before.isInProgress(at: date(19, 8)))

    let between = try #require(timetable.upcoming(after: date(19, 10), calendar: calendar))
    #expect(between.slot.course.code == "C 300")
    #expect(between.start == date(19, 13, 20))
  }

  @Test func movesOnToTheNextDayWithAClass() throws {
    let tuesday = try #require(timetable.upcoming(after: date(19, 15), calendar: calendar))
    #expect(tuesday.slot.course.code == "B 200")
    #expect(tuesday.start == date(20, 13))
  }

  @Test func skipsTheWeekend() throws {
    let afterFriday = try #require(timetable.upcoming(after: date(23, 10), calendar: calendar))
    #expect(afterFriday.slot.course.code == "A 100")
    #expect(afterFriday.start == date(26, 9))

    let sunday = try #require(timetable.upcoming(after: date(25, 12), calendar: calendar))
    #expect(sunday.start == date(26, 9))
  }

  @Test func countsAClassUntilItEnds() throws {
    let justBefore = try #require(timetable.upcoming(after: date(19, 9, 49), calendar: calendar))
    #expect(justBefore.slot.course.code == "A 100")
    let atEnd = try #require(timetable.upcoming(after: date(19, 9, 50), calendar: calendar))
    #expect(atEnd.slot.course.code == "C 300")
  }

  @Test func hasNothingToFindInAnEmptyTimetable() {
    #expect(Timetable().upcoming(after: date(19, 9), calendar: calendar) == nil)
  }

  @Test func drawsEightToFiveByDefaultAndWidensForOddClasses() {
    #expect(Timetable().hourRange == 8...17)
    #expect(timetable.hourRange == 8...17)

    func makeTimetable(with meeting: Meeting) -> Timetable {
      Timetable(courses: [Course(code: "X 1", meetings: [meeting])])
    }
    let early = Meeting(kind: "LEC", section: "1", days: [.monday], start: time(7, 30), end: time(8, 20))
    let evening = Meeting(kind: "LEC", section: "1", days: [.monday], start: time(18), end: time(20, 30))
    let endsOnTheHour = Meeting(kind: "LEC", section: "1", days: [.monday], start: time(16), end: time(18))
    #expect(makeTimetable(with: early).hourRange == 7...17)
    #expect(makeTimetable(with: evening).hourRange == 8...20)
    #expect(makeTimetable(with: endsOnTheHour).hourRange == 8...17)
  }

  @Test func showsTheWeekendOnlyWhenUsed() {
    #expect(timetable.visibleDays == Weekday.schoolWeek)
    let saturday = Timetable(
      courses: [
        Course(
          code: "S 1", meetings: [Meeting(kind: "LEC", section: "1", days: [.saturday], start: time(9), end: time(10))])
      ])
    #expect(saturday.visibleDays.last == .saturday)
    #expect(saturday.visibleDays.count == 6)
    let sunday = Timetable(
      courses: [
        Course(
          code: "S 1", meetings: [Meeting(kind: "LEC", section: "1", days: [.sunday], start: time(9), end: time(10))])
      ])
    #expect(sunday.visibleDays.count == 7)
  }

  @Test func summarisesSectionsOnceEach() {
    #expect(beta.sectionsSummary == "LEC 001 + LAB 301")
    let repeated = Course(
      code: "R 1",
      meetings: [
        Meeting(kind: "LEC", section: "001", days: [.monday], start: time(9), end: time(10)),
        Meeting(kind: "LEC", section: "001", days: [.friday], start: time(9), end: time(10)),
      ])
    #expect(repeated.sectionsSummary == "LEC 001")
  }

  @Test func sortsAndDeduplicatesDays() {
    let meeting = Meeting(kind: "LEC", section: "1", days: [.friday, .monday, .friday], start: time(9), end: time(10))
    #expect(meeting.days == [.monday, .friday])
  }
}

@Suite("Timetable files")
struct TimetableFileTests {
  @Test func roundTrips() throws {
    let data = try timetable.fileData()
    #expect(try Timetable(fileData: data) == timetable)
  }

  @Test func writesTheSameBytesEachTime() throws {
    #expect(try timetable.fileData() == timetable.fileData())
  }

  @Test func recordsTheFileVersion() throws {
    let text = String(decoding: try timetable.fileData(), as: UTF8.self)
    #expect(text.contains(#""version" : 1"#))
  }

  @Test func readsAHandWrittenFile() throws {
    let json = """
      {
        "title": "My term",
        "courses": [
          {
            "code": "X 101",
            "title": "Intro",
            "color": "sky",
            "meetings": [
              { "kind": "LEC", "section": "001", "days": ["monday", "wednesday"], "start": "9:00", "end": "9:50" }
            ]
          },
          { "code": "Y 202" }
        ]
      }
      """
    let table = try Timetable(fileData: Data(json.utf8))
    #expect(table.title == "My term")
    #expect(table.courses.count == 2)
    #expect(table.courses[0].meetings[0].days == [.monday, .wednesday])
    #expect(table.courses[0].meetings[0].location == "")
    #expect(table.courses[1].meetings.isEmpty)
    #expect(table.courses[0].id != table.courses[1].id)
  }

  @Test func rejectsABadTime() {
    let json = #"{"courses":[{"code":"X","meetings":[{"days":["monday"],"start":"9am","end":"10:00"}]}]}"#
    #expect(throws: DecodingError.self) { try Timetable(fileData: Data(json.utf8)) }
  }
}
