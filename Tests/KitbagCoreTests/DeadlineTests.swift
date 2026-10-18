import Foundation
import Testing

@testable import KitbagCore

// The fixtures are invented; real deadlines are personal data and never go into the repository.

private let calendar: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "America/Chicago")!
  calendar.firstWeekday = 2
  return calendar
}()

private func day(_ day: Int, month: Int = 10) -> LocalDate { LocalDate(year: 2026, month: month, day: day) }

private func moment(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
  calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

@Suite("LocalDate")
struct LocalDateTests {
  @Test func readsAndWritesISOText() {
    #expect(LocalDate("2026-10-22") == day(22))
    #expect(day(5).text == "2026-10-05")
  }

  @Test func rejectsWhatIsNotADay() {
    for text in ["", "2026-10", "2026-13-01", "2026-02-30", "26-10-22", "2026-1-5", "2026/10/22", "x"] {
      #expect(LocalDate(text) == nil, "\(text)")
    }
    #expect(LocalDate("2028-02-29") != nil)
    #expect(LocalDate("2026-02-29") == nil)
  }

  @Test func followsTheCalendarsTimeZone() {
    // 03:00 UTC on the 19th is still the evening of the 18th in Chicago.
    let late = Date(timeIntervalSince1970: 1_792_378_800)  // 2026-10-19T03:00:00Z
    #expect(LocalDate(late, calendar: calendar) == day(18))
  }

  @Test func doesDayArithmetic() {
    #expect(day(30).adding(days: 3, calendar: calendar) == day(2, month: 11))
    #expect(day(1).adding(days: -1, calendar: calendar) == LocalDate(year: 2026, month: 9, day: 30))
    #expect(day(22).days(since: day(19), calendar: calendar) == 3)
    #expect(day(19).days(since: day(22), calendar: calendar) == -3)
    #expect(day(19).weekday(calendar: calendar) == .monday)
  }

  @Test func orders() {
    #expect(day(5) < day(6))
    #expect(day(31) < day(1, month: 11))
  }

  @Test func staysTheSameInAnotherCalendarSystem() {
    var japanese = Calendar(identifier: .japanese)
    japanese.timeZone = calendar.timeZone
    #expect(LocalDate(moment(22, 12), calendar: japanese) == day(22))
    #expect(day(22).date(calendar: japanese) == day(22).date(calendar: calendar))
  }
}

@Suite("MonthGrid")
struct MonthGridTests {
  @Test func fillsWholeWeeksStartingOnTheFirstWeekday() {
    // October 2026 starts on a Thursday and has 31 days.
    let monday = MonthGrid(containing: day(18), calendar: calendar)
    #expect(monday.weeks.count == 5)
    #expect(monday.weeks[0].first == LocalDate(year: 2026, month: 9, day: 28))
    #expect(monday.weeks[0][3] == day(1))
    #expect(monday.weeks.last?.last == day(1, month: 11))
    #expect(monday.weeks.allSatisfy { $0.count == 7 })

    var sundayFirst = calendar
    sundayFirst.firstWeekday = 1
    let sunday = MonthGrid(containing: day(18), calendar: sundayFirst)
    #expect(sunday.weeks[0].first == LocalDate(year: 2026, month: 9, day: 27))
    #expect(sunday.weeks[0][4] == day(1))
  }

  @Test func knowsWhichDaysBelongToTheMonth() {
    let grid = MonthGrid(containing: day(18), calendar: calendar)
    #expect(grid.contains(day(1)))
    #expect(grid.contains(day(31)))
    #expect(!grid.contains(LocalDate(year: 2026, month: 9, day: 30)))
    #expect(grid.month == day(1))
  }

  @Test func needsSixRowsWhenTheMonthSpansSix() {
    // August 2026 starts on a Saturday and has 31 days: with Sunday first it needs six rows.
    var sundayFirst = calendar
    sundayFirst.firstWeekday = 1
    #expect(MonthGrid(containing: day(10, month: 8), calendar: sundayFirst).weeks.count == 6)
  }

  @Test func movesBetweenMonths() {
    let grid = MonthGrid(containing: day(18), calendar: calendar)
    #expect(grid.shifted(by: 1, calendar: calendar).month == day(1, month: 11))
    #expect(grid.shifted(by: -10, calendar: calendar).month == LocalDate(year: 2025, month: 12, day: 1))
    #expect(grid.shifted(by: 3, calendar: calendar).month == LocalDate(year: 2027, month: 1, day: 1))
    #expect(grid.shifted(by: 0, calendar: calendar) == grid)
  }

  @Test func ordersTheColumns() {
    #expect(MonthGrid.columnOrder(calendar: calendar).first == .monday)
    #expect(MonthGrid.columnOrder(calendar: calendar).last == .sunday)
    var sundayFirst = calendar
    sundayFirst.firstWeekday = 1
    #expect(
      MonthGrid.columnOrder(calendar: sundayFirst) == [
        .sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday,
      ])
  }
}

@Suite("Deadline")
struct DeadlineTests {
  @Test func isDueAtItsTimeOrTheEndOfItsDay() {
    let timed = Deadline(title: "Lab report", date: day(22), time: TimeOfDay(hour: 14, minute: 30))
    #expect(timed.dueInstant(calendar: calendar) == moment(22, 14, 30))
    let allDay = Deadline(title: "Essay", date: day(22))
    #expect(allDay.dueInstant(calendar: calendar) == moment(22, 23, 59))
  }

  @Test func isOverdueOnlyWhenNotDone() {
    var item = Deadline(title: "Essay", date: day(22))
    #expect(!item.isOverdue(at: moment(22, 23, 0), calendar: calendar))
    #expect(item.isOverdue(at: moment(23, 0, 1), calendar: calendar))
    item.isDone = true
    #expect(!item.isOverdue(at: moment(23, 0, 1), calendar: calendar))
  }

  @Test func remindsBeforeATimedDeadline() {
    let time = TimeOfDay(hour: 14, minute: 30)
    func reminder(_ lead: ReminderLead) -> Date? {
      Deadline(title: "x", date: day(22), time: time, reminder: lead).reminderDate(calendar: calendar)
    }
    #expect(reminder(.none) == nil)
    #expect(reminder(.atDue) == moment(22, 14, 30))
    #expect(reminder(.hourBefore) == moment(22, 13, 30))
    #expect(reminder(.dayBefore) == moment(21, 14, 30))
    #expect(reminder(.twoDaysBefore) == moment(20, 14, 30))
  }

  @Test func remindsAtNineForADeadlineWithoutATime() {
    func reminder(_ lead: ReminderLead) -> Date? {
      Deadline(title: "x", date: day(22), reminder: lead).reminderDate(calendar: calendar)
    }
    #expect(reminder(.none) == nil)
    #expect(reminder(.atDue) == moment(22, 9))
    #expect(reminder(.hourBefore) == moment(22, 9))
    #expect(reminder(.dayBefore) == moment(21, 9))
    #expect(reminder(.twoDaysBefore) == moment(20, 9))
  }

  @Test func keepsTheWallClockAcrossADaylightSavingChange() {
    // Clocks go back on 2026-11-01 in the US. A reminder the day before a 9:00 deadline is still at 9:00.
    let item = Deadline(title: "x", date: LocalDate(year: 2026, month: 11, day: 2), time: TimeOfDay(hour: 9, minute: 0))
    let expected = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 9))!
    #expect(item.reminderDate(calendar: calendar) == expected)
  }
}

@Suite("DeadlineBook")
struct DeadlineBookTests {
  private let book = DeadlineBook(deadlines: [
    Deadline(title: "Old", date: day(15)),
    Deadline(title: "Soon, timed", date: day(20), time: TimeOfDay(hour: 10, minute: 0)),
    Deadline(title: "Soon, all day", date: day(20)),
    Deadline(title: "Next week", date: day(27)),
    Deadline(title: "Far", date: day(30, month: 11)),
    Deadline(title: "Handed in", date: day(20), isDone: true),
  ])
  private let now = moment(19, 12)

  @Test func listsADaysDeadlinesEarliestFirst() {
    // A timed one comes before the all-day ones; those tie at the end of the day and go by title.
    #expect(book.on(day(20), calendar: calendar).map(\.title) == ["Soon, timed", "Handed in", "Soon, all day"])
  }

  @Test func separatesUpcomingFromOverdueAndDone() {
    #expect(
      book.upcoming(after: now, calendar: calendar).map(\.title) == [
        "Soon, timed", "Soon, all day", "Next week", "Far",
      ])
    #expect(book.overdue(at: now, calendar: calendar).map(\.title) == ["Old"])
    #expect(book.done(calendar: calendar).map(\.title) == ["Handed in"])
  }

  @Test func groupsByHowSoon() {
    let groups = book.grouped(now: now, calendar: calendar)
    #expect(groups.map(\.bucket) == [.overdue, .tomorrow, .thisWeek, .later])
    #expect(groups[1].deadlines.map(\.title) == ["Soon, timed", "Soon, all day"])
    #expect(groups[2].deadlines.map(\.title) == ["Next week"])

    let tomorrow = DeadlineBook(deadlines: [Deadline(title: "t", date: day(20))])
    #expect(tomorrow.grouped(now: now, calendar: calendar).first?.bucket == .tomorrow)
    let today = DeadlineBook(deadlines: [Deadline(title: "t", date: day(19))])
    #expect(today.grouped(now: now, calendar: calendar).first?.bucket == .today)
  }

  @Test func marksDaysForTheMonthPage() {
    #expect(book.openKinds(on: day(20)) == [.assignment, .assignment])
    #expect(book.hasDeadlines(on: day(20)))
    #expect(!book.hasDeadlines(on: day(21)))
  }

  @Test func addsReplacesAndRemoves() {
    var copy = book
    let first = copy.deadlines[0]
    var changed = first
    changed.title = "Renamed"
    copy.upsert(changed)
    #expect(copy.deadlines.count == book.deadlines.count)
    #expect(copy.deadlines[0].title == "Renamed")
    copy.upsert(Deadline(title: "New", date: day(25)))
    #expect(copy.deadlines.count == book.deadlines.count + 1)
    copy.remove(id: first.id)
    #expect(copy.deadlines.count == book.deadlines.count)
  }

  @Test func roundTripsThroughAFile() throws {
    let data = try book.fileData()
    #expect(try DeadlineBook(fileData: data) == book)
    #expect(try book.fileData() == book.fileData())
  }

  @Test func readsAHandWrittenFile() throws {
    let json = """
      { "deadlines": [ { "title": "Essay", "date": "2026-10-22" }, { "title": "Exam", "kind": "exam", "date": "2026-12-10", "time": "13:00", "reminder": "twoDaysBefore" } ] }
      """
    let loaded = try DeadlineBook(fileData: Data(json.utf8))
    #expect(loaded.deadlines.count == 2)
    #expect(loaded.deadlines[0].kind == .assignment)
    #expect(loaded.deadlines[0].reminder == .dayBefore)
    #expect(!loaded.deadlines[0].isDone)
    #expect(loaded.deadlines[1].time == TimeOfDay(hour: 13, minute: 0))
    #expect(loaded.deadlines[1].reminder == .twoDaysBefore)
  }

  @Test func rejectsABadDay() {
    let json = #"{"deadlines":[{"title":"x","date":"22/10/2026"}]}"#
    #expect(throws: DecodingError.self) { try DeadlineBook(fileData: Data(json.utf8)) }
  }
}
