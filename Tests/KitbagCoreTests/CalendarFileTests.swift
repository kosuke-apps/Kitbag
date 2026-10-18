import Foundation
import Testing

@testable import KitbagCore

// The files below are invented, in the shapes that Canvas, Google Calendar and Apple Calendar write.

private let chicago: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "America/Chicago")!
  return calendar
}()

private func moment(_ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, year: Int = 2026) -> Date {
  chicago.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private let wholeSeason = DateInterval(start: moment(1, 1), end: moment(12, 31))

private func ics(_ lines: String...) -> String {
  (["BEGIN:VCALENDAR", "VERSION:2.0"] + lines + ["END:VCALENDAR"]).joined(separator: "\r\n") + "\r\n"
}

@Suite("ICalendar reader")
struct ICalendarReaderTests {
  @Test func readsAnEventInUTC() throws {
    let text = ics(
      "BEGIN:VEVENT", "UID:abc-1", "DTSTART:20261022T235900Z", "DTEND:20261023T005900Z",
      "SUMMARY:Lab 5 report [QR 271]",
      "LOCATION:Room 3654", "END:VEVENT")
    let event = try #require(ICalendar.parse(text, defaultTimeZone: chicago.timeZone).first)
    #expect(event.id == "abc-1")
    #expect(event.title == "Lab 5 report [QR 271]")
    #expect(event.location == "Room 3654")
    #expect(event.start == moment(10, 22, 18, 59))
    #expect(event.end == moment(10, 22, 19, 59))
    #expect(!event.isAllDay)
    #expect(event.day(of: event.start, calendar: chicago) == LocalDate(year: 2026, month: 10, day: 22))
  }

  @Test func readsAllDayEventsAsADayNotAMoment() throws {
    let text = ics(
      "BEGIN:VEVENT", "UID:d", "DTSTART;VALUE=DATE:20261105", "DTEND;VALUE=DATE:20261106", "SUMMARY:Holiday",
      "END:VEVENT")
    let event = try #require(ICalendar.parse(text).first)
    #expect(event.isAllDay)
    var tokyo = Calendar(identifier: .gregorian)
    tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    #expect(event.day(of: event.start, calendar: chicago) == LocalDate(year: 2026, month: 11, day: 5))
    #expect(event.day(of: event.start, calendar: tokyo) == LocalDate(year: 2026, month: 11, day: 5))
  }

  @Test func readsTimesInTheirOwnZoneAndFloatingTimesInTheDefault() throws {
    let text = ics(
      "BEGIN:VEVENT", "UID:z", "DTSTART;TZID=America/Chicago:20261022T130000", "SUMMARY:Zoned", "END:VEVENT",
      "BEGIN:VEVENT", "UID:f", "DTSTART:20261022T130000", "SUMMARY:Floating", "END:VEVENT")
    var tokyo = Calendar(identifier: .gregorian)
    tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    let events = ICalendar.parse(text, defaultTimeZone: tokyo.timeZone)
    #expect(events[0].start == moment(10, 22, 13))
    #expect(events[0].timeZoneID == "America/Chicago")
    #expect(events[1].start == tokyo.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 13)))
  }

  @Test func unfoldsLongLinesAndUnescapesText() throws {
    let text =
      "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:u\r\nDTSTART:20261022T130000Z\r\nSUMMARY:Read chapters 1\\, 2\\; and 3\r\nDESCRIPTION:First line\\nSecond line that is\r\n  folded here\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
    let event = try #require(ICalendar.parse(text).first)
    #expect(event.title == "Read chapters 1, 2; and 3")
    #expect(event.notes == "First line\nSecond line that is folded here")
  }

  @Test func readsLinesWithQuotedParametersAndLineEndsOfAnyKind() throws {
    let text =
      "BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:q\nDTSTART;TZID=\"America/Chicago\":20261022T130000\nSUMMARY:Quoted: with colon\nEND:VEVENT\nEND:VCALENDAR\n"
    let event = try #require(ICalendar.parse(text).first)
    #expect(event.title == "Quoted: with colon")
    #expect(event.start == moment(10, 22, 13))
  }

  @Test func readsATaskAtItsDueMoment() throws {
    let text = ics(
      "BEGIN:VTODO", "UID:t", "DTSTART:20261001T000000Z", "DUE:20261030T170000Z", "SUMMARY:Essay", "STATUS:COMPLETED",
      "END:VTODO")
    let task = try #require(ICalendar.parse(text).first)
    #expect(task.isTask)
    #expect(task.isCompleted)
    #expect(task.start == moment(10, 30, 12))
  }

  @Test func readsADurationInPlaceOfAnEnd() throws {
    let text = ics(
      "BEGIN:VEVENT", "UID:d", "DTSTART:20261022T130000Z", "DURATION:PT1H30M", "SUMMARY:Meeting", "END:VEVENT")
    let event = try #require(ICalendar.parse(text).first)
    #expect(event.end?.timeIntervalSince(event.start) == 5400)
    #expect(ICalendar.parseDuration("P1DT2H") == 93600)
    #expect(ICalendar.parseDuration("P2W") == 1_209_600.0)
    #expect(ICalendar.parseDuration("-PT15M") == -900)
  }

  @Test func ignoresWhatIsInsideAnAlarm() throws {
    let text = ics(
      "BEGIN:VEVENT", "UID:a", "DTSTART:20261022T130000Z", "SUMMARY:Real title", "BEGIN:VALARM", "ACTION:DISPLAY",
      "SUMMARY:Alarm text", "DESCRIPTION:Alarm description", "TRIGGER:-PT15M", "END:VALARM", "END:VEVENT")
    let event = try #require(ICalendar.parse(text).first)
    #expect(event.title == "Real title")
    #expect(event.notes == "")
  }

  @Test func skipsWhatItCannotRead() {
    let text = ics(
      "BEGIN:VEVENT", "UID:x", "SUMMARY:No start", "END:VEVENT", "not a content line", "BEGIN:VEVENT",
      "DTSTART:garbage", "END:VEVENT")
    #expect(ICalendar.parse(text).isEmpty)
    #expect(ICalendar.parse("").isEmpty)
  }
}

@Suite("Repeating events")
struct RecurrenceTests {
  private func days(_ event: CalendarEvent) -> [Int] {
    event.occurrences(in: wholeSeason, calendar: chicago).map { chicago.component(.day, from: $0.start) }
  }

  @Test func expandsAWeeklyRuleWithDaysUntilAndAnException() throws {
    let text = ics(
      "BEGIN:VEVENT", "UID:w", "SUMMARY:Class", "DTSTART;TZID=America/Chicago:20261019T140000",
      "RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR;UNTIL=20261030T235959Z", "EXDATE;TZID=America/Chicago:20261021T140000",
      "END:VEVENT")
    let event = try #require(ICalendar.parse(text, defaultTimeZone: chicago.timeZone).first)
    #expect(days(event) == [19, 23, 26, 28, 30])
  }

  @Test func keepsTheWallClockAcrossADaylightSavingChange() throws {
    // Clocks go back on 2026-11-01. A 14:00 class on Mondays is still at 14:00 after it.
    let text = ics(
      "BEGIN:VEVENT", "UID:w", "SUMMARY:Class", "DTSTART;TZID=America/Chicago:20261026T140000",
      "RRULE:FREQ=WEEKLY;COUNT=3",
      "END:VEVENT")
    let event = try #require(ICalendar.parse(text, defaultTimeZone: chicago.timeZone).first)
    let starts = event.occurrences(in: wholeSeason, calendar: chicago).map(\.start)
    #expect(starts == [moment(10, 26, 14), moment(11, 2, 14), moment(11, 9, 14)])
  }

  @Test func countsOccurrencesAndStepsByInterval() throws {
    let daily = try #require(
      ICalendar.parse(
        ics("BEGIN:VEVENT", "UID:d", "SUMMARY:x", "DTSTART:20261019T140000Z", "RRULE:FREQ=DAILY;COUNT=3", "END:VEVENT")
      ).first)
    #expect(daily.occurrences(in: wholeSeason, calendar: chicago).count == 3)
    let biweekly = try #require(
      ICalendar.parse(
        ics(
          "BEGIN:VEVENT", "UID:b", "SUMMARY:x", "DTSTART;TZID=America/Chicago:20261019T140000",
          "RRULE:FREQ=WEEKLY;INTERVAL=2;COUNT=3", "END:VEVENT"),
        defaultTimeZone: chicago.timeZone
      ).first)
    #expect(days(biweekly) == [19, 2, 16])
  }

  @Test func expandsMonthlyAndYearlyRules() throws {
    let monthly = try #require(
      ICalendar.parse(
        ics(
          "BEGIN:VEVENT", "UID:m", "SUMMARY:x", "DTSTART;TZID=America/Chicago:20261015T090000",
          "RRULE:FREQ=MONTHLY;COUNT=3", "END:VEVENT"),
        defaultTimeZone: chicago.timeZone
      ).first)
    #expect(days(monthly) == [15, 15, 15])
    let yearly = try #require(
      ICalendar.parse(
        ics("BEGIN:VEVENT", "UID:y", "SUMMARY:x", "DTSTART;VALUE=DATE:20261105", "RRULE:FREQ=YEARLY", "END:VEVENT"),
        defaultTimeZone: chicago.timeZone
      ).first)
    let window = DateInterval(start: moment(1, 1), end: moment(12, 31, year: 2029))
    #expect(yearly.occurrences(in: window, calendar: chicago).count == 4)
  }

  @Test func onlyReturnsWhatFallsInTheWindow() throws {
    let text = ics(
      "BEGIN:VEVENT", "UID:d", "SUMMARY:x", "DTSTART;TZID=America/Chicago:20261019T140000", "RRULE:FREQ=DAILY",
      "END:VEVENT")
    let event = try #require(ICalendar.parse(text, defaultTimeZone: chicago.timeZone).first)
    let week = DateInterval(start: moment(10, 25), end: moment(10, 31))
    #expect(event.occurrences(in: week, calendar: chicago).count == 6)
    let single = try #require(
      ICalendar.parse(ics("BEGIN:VEVENT", "UID:s", "SUMMARY:x", "DTSTART:20261201T140000Z", "END:VEVENT")).first)
    #expect(single.occurrences(in: week, calendar: chicago).isEmpty)
  }

  @Test func treatsARuleItDoesNotUnderstandAsASingleEvent() throws {
    let text = ics(
      "BEGIN:VEVENT", "UID:x", "SUMMARY:x", "DTSTART;TZID=America/Chicago:20261019T140000",
      "RRULE:FREQ=MONTHLY;BYDAY=1MO", "END:VEVENT")
    let event = try #require(ICalendar.parse(text, defaultTimeZone: chicago.timeZone).first)
    #expect(event.recurrence == nil)
    #expect(days(event) == [19])
  }
}

@Suite("ICS writer")
struct ICSWriterTests {
  private let course = Course(code: "Q R 271", title: "Sample Laboratory")

  private func sample() -> [Deadline] {
    [
      Deadline(
        title: "Lab 5 report, part A; draft", kind: .assignment, courseID: course.id,
        date: LocalDate(year: 2026, month: 10, day: 22), time: TimeOfDay(hour: 14, minute: 30),
        note: "Bring the data.\nUse tables.",
        alerts: [.days(1), .hours(1)]),
      Deadline(
        title: "Midterm", kind: .exam, date: LocalDate(year: 2026, month: 10, day: 27), isDone: true, alerts: []),
    ]
  }

  @Test func writesEventsThatReadBackTheSame() throws {
    let text = ICSWriter.deadlines(sample(), courseCode: { _ in course.code }, calendar: chicago, now: moment(10, 1))
    let events = ICalendar.parse(text, defaultTimeZone: chicago.timeZone)
    #expect(events.count == 2)
    #expect(events[0].title == "Lab 5 report, part A; draft")
    #expect(events[0].start == moment(10, 22, 14, 30))
    #expect(events[0].notes == "Q R 271\nBring the data.\nUse tables.")
    #expect(events[0].kitbagKind == "assignment")
    #expect(events[0].kitbagCourse == "Q R 271")
    #expect(events[1].isAllDay)
    #expect(events[1].kitbagDone)
    #expect(events[1].kitbagKind == "exam")
  }

  @Test func comesBackAsTheSameDeadlinesThroughTheImport() {
    let text = ICSWriter.deadlines(sample(), courseCode: { _ in course.code }, calendar: chicago, now: moment(10, 1))
    let events = ICalendar.parse(text, defaultTimeZone: chicago.timeZone)
    let back = DeadlineImport.deadlines(from: events, courses: [course], calendar: chicago, window: wholeSeason)
    #expect(back.count == 2)
    #expect(back[0].date == LocalDate(year: 2026, month: 10, day: 22))
    #expect(back[0].time == TimeOfDay(hour: 14, minute: 30))
    #expect(back[0].courseID == course.id)
    #expect(back[0].kind == .assignment)
    #expect(back[1].kind == .exam)
    #expect(back[1].isDone)
    #expect(back[1].time == nil)
  }

  @Test func addsAnAlarmForEachAlertAndLeavesThemOutWhenDone() {
    let text = ICSWriter.deadlines(sample(), courseCode: { _ in nil }, calendar: chicago, now: moment(10, 1))
    #expect(text.components(separatedBy: "BEGIN:VALARM").count == 3)  // two alarms for the lab report, none for the exam
    #expect(text.contains("TRIGGER;VALUE=DATE-TIME:20261021T193000Z"))  // one day before 14:30 Chicago
    #expect(text.contains("TRIGGER;VALUE=DATE-TIME:20261022T183000Z"))  // one hour before
    var done = sample()
    done[0].isDone = true
    let quiet = ICSWriter.deadlines(done, courseCode: { _ in nil }, calendar: chicago, now: moment(10, 1))
    #expect(!quiet.contains("BEGIN:VALARM"))
  }

  @Test func foldsLongLinesWithoutBreakingText() throws {
    let long = String(repeating: "日本語のとても長い課題名 ", count: 12)
    let text = ICSWriter.deadlines(
      [Deadline(title: long, date: LocalDate(year: 2026, month: 10, day: 22))], courseCode: { _ in nil },
      calendar: chicago)
    for line in text.components(separatedBy: "\r\n") { #expect(line.utf8.count <= 75) }
    #expect(text.hasSuffix("\r\n"))
    let event = try #require(ICalendar.parse(text, defaultTimeZone: chicago.timeZone).first)
    #expect(event.title == long.trimmingCharacters(in: .whitespaces))
  }

  @Test func writesTheClassesOfATermAsWeeklyEvents() throws {
    let term = Timetable(
      startDate: LocalDate(year: 2026, month: 9, day: 2), endDate: LocalDate(year: 2026, month: 12, day: 9),
      courses: [
        Course(
          code: "Z Z 376", title: "Sample Lecture",
          meetings: [
            Meeting(
              kind: "LEC", section: "001", days: [.monday, .wednesday, .friday], start: TimeOfDay(hour: 8, minute: 50),
              end: TimeOfDay(hour: 9, minute: 40), location: "1800 Hall", instructor: "A. Prof")
          ])
      ])
    let text = ICSWriter.classes(of: term, calendar: chicago, now: moment(9, 1))
    let event = try #require(ICalendar.parse(text, defaultTimeZone: chicago.timeZone).first)
    #expect(event.title == "Z Z 376 · LEC 001")
    #expect(event.location == "1800 Hall")
    #expect(event.recurrence?.days == [.monday, .wednesday, .friday])
    #expect(event.start == moment(9, 2, 8, 50))
    let starts = event.occurrences(in: wholeSeason, calendar: chicago).map(\.start)
    #expect(starts.first == moment(9, 2, 8, 50))
    #expect(starts.last == moment(12, 9, 8, 50))
    var expected = 0
    var day = LocalDate(year: 2026, month: 9, day: 2)
    while day <= LocalDate(year: 2026, month: 12, day: 9) {
      if [Weekday.monday, .wednesday, .friday].contains(day.weekday(calendar: chicago)) { expected += 1 }
      day = day.adding(days: 1, calendar: chicago)
    }
    #expect(starts.count == expected)
  }
}

@Suite("Deadline import")
struct DeadlineImportTests {
  @Test func guessesTheKindFromTheTitle() {
    #expect(DeadlineImport.guessKind("Midterm Exam 1") == .exam)
    #expect(DeadlineImport.guessKind("FINAL") == .exam)
    #expect(DeadlineImport.guessKind("Quiz 3: circuits") == .quiz)
    #expect(DeadlineImport.guessKind("Group project demo") == .project)
    #expect(DeadlineImport.guessKind("Problem set 4") == .assignment)
    #expect(DeadlineImport.guessKind("中間試験") == .exam)
  }

  @Test func matchesTheCourseByItsCodeIgnoringSpaces() {
    let courses = [Course(code: "Q R 352"), Course(code: "Q R 271"), Course(code: "A 1"), Course(code: "A 12")]
    #expect(DeadlineImport.matchCourse(in: "Lab report [QR 271 LAB 001 FA26]", courses: courses)?.code == "Q R 271")
    #expect(DeadlineImport.matchCourse(in: "Read for a 12 class", courses: courses)?.code == "A 12")
    #expect(DeadlineImport.matchCourse(in: "Dentist", courses: courses) == nil)
  }

  @Test func importsEachOccurrenceOfARepeatingEventOnce() throws {
    let text = ics(
      "BEGIN:VEVENT", "UID:hw", "SUMMARY:Weekly quiz", "DTSTART;VALUE=DATE:20261023", "RRULE:FREQ=WEEKLY;COUNT=3",
      "END:VEVENT")
    let events = ICalendar.parse(text, defaultTimeZone: chicago.timeZone)
    let deadlines = DeadlineImport.deadlines(from: events, courses: [], calendar: chicago, window: wholeSeason)
    #expect(
      deadlines.map(\.date) == [
        LocalDate(year: 2026, month: 10, day: 23), LocalDate(year: 2026, month: 10, day: 30),
        LocalDate(year: 2026, month: 11, day: 6),
      ])
    #expect(Set(deadlines.compactMap(\.sourceUID)).count == 3)
    #expect(deadlines.allSatisfy { $0.kind == .quiz && $0.time == nil })
  }

  @Test func givesNewDeadlinesTheAlertsOfTheirKind() {
    let text = ics(
      "BEGIN:VEVENT", "UID:u1", "SUMMARY:Midterm exam", "DTSTART;VALUE=DATE:20261030", "END:VEVENT",
      "BEGIN:VEVENT", "UID:u2", "SUMMARY:Essay", "DTSTART:20261030T150000Z", "END:VEVENT")
    let events = ICalendar.parse(text, defaultTimeZone: chicago.timeZone)
    let result = DeadlineImport.deadlines(
      from: events, courses: [], calendar: chicago, window: wholeSeason,
      defaultAlerts: { $0 == .exam ? [.weeks(1), .hours(2)] : [.hours(3)] })
    let exam = result.first { $0.title == "Midterm exam" }
    let essay = result.first { $0.title == "Essay" }
    // An exam with no time cannot be reminded in hours: that becomes "on the day".
    #expect(exam?.alerts.map(\.leadMinutes) == [7 * 1440, 0])
    #expect(essay?.alerts.map(\.leadMinutes) == [180])
  }

  @Test func keepsWhatThePersonChangedWhenImportingAgain() {
    let text = ics(
      "BEGIN:VEVENT", "UID:u1", "SUMMARY:Essay", "DTSTART;VALUE=DATE:20261030", "DESCRIPTION:New text", "END:VEVENT")
    let events = ICalendar.parse(text, defaultTimeZone: chicago.timeZone)
    let course = Course(code: "X 1")
    var earlier = Deadline(
      title: "Essay", courseID: course.id, date: LocalDate(year: 2026, month: 10, day: 29), isDone: true,
      alerts: [], sourceUID: "u1")
    earlier.note = "old"
    let result = DeadlineImport.deadlines(
      from: events, courses: [], existing: [earlier], calendar: chicago, window: wholeSeason)
    #expect(result.count == 1)
    #expect(result[0].id == earlier.id)
    #expect(result[0].isDone)
    #expect(result[0].courseID == course.id)
    #expect(result[0].alerts.isEmpty)
    #expect(result[0].date == LocalDate(year: 2026, month: 10, day: 30))
    #expect(result[0].note == "New text")
  }
}
