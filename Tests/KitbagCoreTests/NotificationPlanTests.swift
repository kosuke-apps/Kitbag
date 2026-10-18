import Foundation
import Testing

@testable import KitbagCore

private let chicago: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "America/Chicago") ?? .gmt
  return calendar
}()

private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
  chicago.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)) ?? .distantPast
}

private func deadline(
  _ title: String, day: Int, hour: Int = 12, kind: DeadlineKind = .assignment, done: Bool = false
)
  -> Deadline
{
  Deadline(
    title: title, kind: kind, date: LocalDate(year: 2026, month: 10, day: day), time: TimeOfDay(hour: hour, minute: 0),
    isDone: done, reminder: .hourBefore)
}

@Suite("Notification preferences")
struct NotificationPreferencesTests {
  @Test func startsConservative() {
    let preferences = NotificationPreferences()
    #expect(preferences.deadlinesEnabled)
    #expect(!preferences.classesEnabled)
    #expect(!preferences.quietHoursEnabled)
    #expect(preferences.signatureEnabled)
    #expect(preferences.classLeadMinutes == 10)
  }

  @Test func fillsInWhatAnOlderValueLacks() throws {
    let preferences = try JSONDecoder().decode(
      NotificationPreferences.self, from: Data("{\"classesEnabled\":true}".utf8))
    #expect(preferences.classesEnabled)
    #expect(preferences.deadlinesEnabled)
    #expect(preferences.deadlineKinds.count == DeadlineKind.allCases.count)
  }

  @Test func roundTrips() throws {
    var preferences = NotificationPreferences()
    preferences.classesEnabled = true
    preferences.classLeadMinutes = 30
    preferences.mutedCourseIDs = [UUID()]
    preferences.deadlineKinds = [.exam, .quiz]
    preferences.quietHoursEnabled = true
    let data = try JSONEncoder().encode(preferences)
    #expect(try JSONDecoder().decode(NotificationPreferences.self, from: data) == preferences)
  }

  @Test func holdsBackAReminderInQuietHours() {
    var preferences = NotificationPreferences()
    preferences.quietHoursEnabled = true  // 22:00 to 07:00
    let due = date(25, 12)
    #expect(preferences.adjusted(date(24, 23), notAfter: due, calendar: chicago) == date(25, 7))
    #expect(preferences.adjusted(date(25, 3), notAfter: due, calendar: chicago) == date(25, 7))
    #expect(preferences.adjusted(date(24, 21, 59), notAfter: due, calendar: chicago) == date(24, 21, 59))
    #expect(preferences.adjusted(date(25, 7), notAfter: due, calendar: chicago) == date(25, 7))
    // When the thing is due before the quiet hours end, the reminder stays where it was.
    #expect(preferences.adjusted(date(25, 3), notAfter: date(25, 6), calendar: chicago) == date(25, 3))
    preferences.quietHoursEnabled = false
    #expect(preferences.adjusted(date(24, 23), notAfter: due, calendar: chicago) == date(24, 23))
  }

  @Test func quietHoursThatDoNotCrossMidnight() {
    var preferences = NotificationPreferences()
    preferences.quietHoursEnabled = true
    preferences.quietStart = TimeOfDay(hour: 13, minute: 0)
    preferences.quietEnd = TimeOfDay(hour: 15, minute: 0)
    #expect(preferences.adjusted(date(24, 14), notAfter: date(26, 0), calendar: chicago) == date(24, 15))
    #expect(preferences.adjusted(date(24, 12), notAfter: date(26, 0), calendar: chicago) == date(24, 12))
  }
}

@Suite("Notification planner")
struct NotificationPlannerTests {
  @Test func planDeadlineRemindersByThePreferences() {
    let book = DeadlineBook(deadlines: [
      deadline("quiz", day: 20, kind: .quiz), deadline("exam", day: 21, kind: .exam),
      deadline("done", day: 22, done: true), deadline("past", day: 10), deadline("hw", day: 23),
    ])
    let now = date(18, 12)
    let all = NotificationPlanner.deadlineReminders(
      book, preferences: NotificationPreferences(), now: now, calendar: chicago, limit: 10)
    #expect(all.map(\.deadline.title) == ["quiz", "exam", "hw"])

    var examsOnly = NotificationPreferences()
    examsOnly.deadlineKinds = [.exam]
    #expect(
      NotificationPlanner.deadlineReminders(book, preferences: examsOnly, now: now, calendar: chicago, limit: 10)
        .map(\.deadline.title) == ["exam"])

    var off = NotificationPreferences()
    off.deadlinesEnabled = false
    #expect(
      NotificationPlanner.deadlineReminders(book, preferences: off, now: now, calendar: chicago, limit: 10).isEmpty)
    #expect(
      NotificationPlanner.deadlineReminders(
        book, preferences: NotificationPreferences(), now: now, calendar: chicago, limit: 2
      )
      .count == 2)
  }

  private func library() -> (TimetableLibrary, Course, Course) {
    let lecture = Course(
      code: "AA 100", title: "Lecture",
      meetings: [
        Meeting(
          kind: "LEC", section: "001", days: [.monday, .wednesday], start: TimeOfDay(hour: 8, minute: 50),
          end: TimeOfDay(hour: 9, minute: 40), location: "Hall 1")
      ])
    let lab = Course(
      code: "BB 200",
      meetings: [
        Meeting(
          kind: "LAB", section: "002", days: [.monday], start: TimeOfDay(hour: 13, minute: 20),
          end: TimeOfDay(hour: 15, minute: 15), location: "Lab 2")
      ])
    let term = Timetable(
      title: "T", startDate: LocalDate(year: 2026, month: 9, day: 1),
      endDate: LocalDate(year: 2026, month: 12, day: 15),
      courses: [lecture, lab])
    return (TimetableLibrary(timetables: [term]), lecture, lab)
  }

  @Test func plansClassRemindersAheadOfTime() {
    let (library, _, _) = library()
    var preferences = NotificationPreferences()
    #expect(
      NotificationPlanner.classReminders(
        library, preferences: preferences, now: date(18, 12), calendar: chicago, horizonDays: 7, limit: 50
      ).isEmpty)
    preferences.classesEnabled = true
    preferences.classLeadMinutes = 10
    // Sunday the 18th: the week ahead has Monday 19 (lecture, lab) and Wednesday 21 (lecture).
    let plan = NotificationPlanner.classReminders(
      library, preferences: preferences, now: date(18, 12), calendar: chicago, horizonDays: 7, limit: 50)
    #expect(plan.map(\.code) == ["AA 100", "BB 200", "AA 100"])
    #expect(plan[0].fireDate == date(19, 8, 40))
    #expect(plan[0].start == date(19, 8, 50))
    #expect(plan[0].location == "Hall 1")
    #expect(Set(plan.map(\.id)).count == 3)
  }

  @Test func skipsMutedCoursesPastClassesAndDaysOutsideTheTerm() {
    let (library, lecture, _) = library()
    var preferences = NotificationPreferences()
    preferences.classesEnabled = true
    preferences.mutedCourseIDs = [lecture.id]
    let muted = NotificationPlanner.classReminders(
      library, preferences: preferences, now: date(18, 12), calendar: chicago, horizonDays: 7, limit: 50)
    #expect(muted.map(\.code) == ["BB 200"])

    preferences.mutedCourseIDs = []
    // Monday the 19th at 8:45: the lecture's reminder (8:40) is already past, the lab's is not.
    let late = NotificationPlanner.classReminders(
      library, preferences: preferences, now: date(19, 8, 45), calendar: chicago, horizonDays: 1, limit: 50)
    #expect(late.map(\.code) == ["BB 200"])

    let after = NotificationPlanner.classReminders(
      library, preferences: preferences, now: date(18, 12).addingTimeInterval(60 * 86400), calendar: chicago,
      horizonDays: 7, limit: 50)
    #expect(after.isEmpty)
    #expect(
      NotificationPlanner.classReminders(
        library, preferences: preferences, now: date(18, 12), calendar: chicago, horizonDays: 7, limit: 2
      ).count == 2)
  }
}
