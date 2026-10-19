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
    isDone: done, alerts: [.hours(1)])
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

  @Test func givesEachKindItsOwnDefaultAlerts() throws {
    var preferences = NotificationPreferences()
    #expect(preferences.alerts(for: .exam).map(\.leadMinutes) == [7 * 1440, 1440, 60])
    #expect(!preferences.hasCustomAlerts(for: .exam))
    preferences.setAlerts([.hours(2)], for: .exam)
    preferences.setAlerts([], for: .quiz)
    #expect(preferences.alerts(for: .exam).map(\.leadMinutes) == [120])
    #expect(preferences.alerts(for: .quiz).isEmpty)  // an empty list is a choice, not a missing one
    #expect(preferences.alerts(for: .project).count == 2)
    #expect(preferences.hasCustomAlerts(for: .quiz))
    let data = try JSONEncoder().encode(preferences)
    #expect(try JSONDecoder().decode(NotificationPreferences.self, from: data) == preferences)
  }

  @Test func readsAFileFromBeforeTheNewChoices() throws {
    let old = #"{"deadlinesEnabled":true,"quietHoursEnabled":true,"quietStart":"22:00","quietEnd":"07:00"}"#
    let preferences = try JSONDecoder().decode(NotificationPreferences.self, from: Data(old.utf8))
    #expect(preferences.allDayTime == TimeOfDay(hour: 9, minute: 0))
    #expect(preferences.followUpDays == 0)
    #expect(preferences.defaultAlerts.isEmpty)
    let clamped = try JSONDecoder().decode(NotificationPreferences.self, from: Data(#"{"followUpDays":40}"#.utf8))
    #expect(clamped.followUpDays == NotificationPreferences.maxFollowUps)
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

  private func multi(_ alerts: [DeadlineAlert], day: Int = 22, hour: Int? = 12, done: Bool = false) -> Deadline {
    Deadline(
      title: "multi", date: LocalDate(year: 2026, month: 10, day: day),
      time: hour.map { TimeOfDay(hour: $0, minute: 0) },
      isDone: done, alerts: alerts)
  }

  @Test func makesOneReminderForEachAlert() {
    let item = multi([.days(1), .hours(1), .minutes(0)])
    let plan = NotificationPlanner.deadlineReminders(
      DeadlineBook(deadlines: [item]), preferences: NotificationPreferences(), now: date(18, 12), calendar: chicago,
      limit: 10)
    #expect(plan.map(\.fireDate) == [date(21, 12), date(22, 11), date(22, 12)])
    #expect(Set(plan.map(\.id)).count == 3)
    #expect(plan.allSatisfy { $0.id.hasPrefix(DeadlineReminder.idPrefix(for: item.id)) })
    #expect(plan.allSatisfy { $0.deadline == item })
    // Past ones are left out.
    let later = NotificationPlanner.deadlineReminders(
      DeadlineBook(deadlines: [item]), preferences: NotificationPreferences(), now: date(21, 13), calendar: chicago,
      limit: 10)
    #expect(later.map(\.fireDate) == [date(22, 11), date(22, 12)])
  }

  @Test func idsStayTheSameWhenPlannedAgain() {
    let book = DeadlineBook(deadlines: [multi([.days(1), .hours(1)])])
    func ids() -> [String] {
      NotificationPlanner.deadlineReminders(
        book, preferences: NotificationPreferences(), now: date(18, 12), calendar: chicago, limit: 10
      ).map(\.id)
    }
    #expect(ids() == ids())
  }

  @Test func staysSilentWithoutAlertsAndAfterBeingDone() {
    var preferences = NotificationPreferences()
    preferences.followUpDays = 2
    let book = DeadlineBook(deadlines: [multi([]), multi([.days(1)], done: true)])
    #expect(
      NotificationPlanner.deadlineReminders(
        book, preferences: preferences, now: date(18, 12), calendar: chicago, limit: 10
      )
      .isEmpty)
  }

  @Test func collapsesAlertsThatWouldComeAtTheSameMinute() {
    // "1 hour before" and "60 minutes before" are one reminder; quiet hours can also make two alerts land together.
    let book = DeadlineBook(deadlines: [multi([.hours(1), .minutes(60)])])
    #expect(
      NotificationPlanner.deadlineReminders(
        book, preferences: NotificationPreferences(), now: date(18, 12), calendar: chicago, limit: 10
      ).count == 1)
    var quiet = NotificationPreferences()
    quiet.quietHoursEnabled = true  // 22:00 to 07:00
    // Due Thursday 12:00. "1 day before" is Wednesday 12:00 and "13 hours before" is Wednesday 23:00, held to 7:00 Thursday;
    // "5 hours before" is Thursday 7:00 as well.
    let crowded = DeadlineBook(deadlines: [multi([.days(1), .hours(13), .hours(5)])])
    let plan = NotificationPlanner.deadlineReminders(
      crowded, preferences: quiet, now: date(18, 12), calendar: chicago, limit: 10)
    #expect(plan.map(\.fireDate) == [date(21, 12), date(22, 7)])
  }

  @Test func followsUpOnTheMorningsAfterADeadlineThatIsNotDone() {
    var preferences = NotificationPreferences()
    preferences.followUpDays = 2
    let item = multi([.hours(1)])
    let plan = NotificationPlanner.deadlineReminders(
      DeadlineBook(deadlines: [item]), preferences: preferences, now: date(18, 12), calendar: chicago, limit: 10)
    #expect(plan.map(\.fireDate) == [date(22, 11), date(23, 9), date(24, 9)])
    #expect(plan.map(\.kind) == [.alert(item.alerts[0]), .followUp(1), .followUp(2)])
    #expect(Set(plan.map(\.id)).count == 3)
    preferences.allDayTime = TimeOfDay(hour: 8, minute: 30)
    let early = NotificationPlanner.deadlineReminders(
      DeadlineBook(deadlines: [item]), preferences: preferences, now: date(18, 12), calendar: chicago, limit: 10)
    #expect(early.map(\.fireDate) == [date(22, 11), date(23, 8, 30), date(24, 8, 30)])
  }

  @Test func plansTheMorningTimeForADeadlineWithoutATime() {
    var preferences = NotificationPreferences()
    preferences.allDayTime = TimeOfDay(hour: 7, minute: 45)
    let book = DeadlineBook(deadlines: [multi([.days(1), .days(0, at: TimeOfDay(hour: 20, minute: 0))], hour: nil)])
    let plan = NotificationPlanner.deadlineReminders(
      book, preferences: preferences, now: date(18, 12), calendar: chicago, limit: 10)
    #expect(plan.map(\.fireDate) == [date(21, 7, 45), date(22, 20)])
  }

  @Test func keepsTheSoonestWhenThereAreMoreThanFit() {
    let book = DeadlineBook(deadlines: [
      multi([.days(1), .hours(1)], day: 22), multi([.hours(1)], day: 20), multi([.days(1)], day: 25),
    ])
    let plan = NotificationPlanner.deadlineReminders(
      book, preferences: NotificationPreferences(), now: date(18, 12), calendar: chicago, limit: 3)
    #expect(plan.map(\.fireDate) == [date(20, 11), date(21, 12), date(22, 11)])
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
