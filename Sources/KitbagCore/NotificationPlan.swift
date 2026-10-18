import Foundation

/// What the person wants to be reminded of, and when. Some people like reminders and some find them a nuisance, so every
/// kind can be turned off and the ones that are on can be tuned. Kept as a small JSON value and saved with the settings.
public struct NotificationPreferences: Codable, Equatable, Sendable {
  /// Remind about deadlines at all (each deadline still has its own lead time).
  public var deadlinesEnabled = true
  /// Which kinds of deadline to remind about.
  public var deadlineKinds: Set<DeadlineKind> = Set(DeadlineKind.allCases)
  /// Remind before a class starts. Off until it is turned on.
  public var classesEnabled = false
  public var classLeadMinutes = 10
  /// Courses that get no class reminder.
  public var mutedCourseIDs: Set<UUID> = []
  /// Warn before the signature of a free Apple ID runs out.
  public var signatureEnabled = true
  /// Hold back reminders that fall within these hours until they end (unless that would be after the thing is due).
  public var quietHoursEnabled = false
  public var quietStart = TimeOfDay(hour: 22, minute: 0)
  public var quietEnd = TimeOfDay(hour: 7, minute: 0)

  public init() {}

  private enum CodingKeys: String, CodingKey {
    case deadlinesEnabled, deadlineKinds, classesEnabled, classLeadMinutes, mutedCourseIDs, signatureEnabled
    case quietHoursEnabled, quietStart, quietEnd
  }

  /// A file from an older version lacks the newer choices; each falls back to its default.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = NotificationPreferences()
    deadlinesEnabled = try container.decodeIfPresent(Bool.self, forKey: .deadlinesEnabled) ?? defaults.deadlinesEnabled
    deadlineKinds =
      try container.decodeIfPresent(Set<DeadlineKind>.self, forKey: .deadlineKinds) ?? defaults.deadlineKinds
    classesEnabled = try container.decodeIfPresent(Bool.self, forKey: .classesEnabled) ?? defaults.classesEnabled
    classLeadMinutes = try container.decodeIfPresent(Int.self, forKey: .classLeadMinutes) ?? defaults.classLeadMinutes
    mutedCourseIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .mutedCourseIDs) ?? defaults.mutedCourseIDs
    signatureEnabled = try container.decodeIfPresent(Bool.self, forKey: .signatureEnabled) ?? defaults.signatureEnabled
    quietHoursEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .quietHoursEnabled) ?? defaults.quietHoursEnabled
    quietStart = try container.decodeIfPresent(TimeOfDay.self, forKey: .quietStart) ?? defaults.quietStart
    quietEnd = try container.decodeIfPresent(TimeOfDay.self, forKey: .quietEnd) ?? defaults.quietEnd
  }

  /// Whether `minutes` after midnight falls within the quiet hours (which may run past midnight).
  public func isQuiet(minutesOfDay minutes: Int) -> Bool {
    guard quietHoursEnabled, quietStart != quietEnd else { return false }
    let start = quietStart.minutes
    let end = quietEnd.minutes
    return start < end ? (start <= minutes && minutes < end) : (minutes >= start || minutes < end)
  }

  /// Moves a reminder that falls in the quiet hours to when they end, unless that is not before `notAfter` (the moment the
  /// thing is due or starts): a reminder that would come too late is better early.
  public func adjusted(_ fire: Date, notAfter: Date, calendar: Calendar) -> Date {
    let parts = calendar.dateComponents([.hour, .minute], from: fire)
    guard isQuiet(minutesOfDay: (parts.hour ?? 0) * 60 + (parts.minute ?? 0)),
      var moved = calendar.date(bySettingHour: quietEnd.hour, minute: quietEnd.minute, second: 0, of: fire)
    else { return fire }
    if moved <= fire { moved = calendar.date(byAdding: .day, value: 1, to: moved) ?? moved }
    return moved < notAfter ? moved : fire
  }
}

/// A reminder that a class is about to start.
public struct ClassReminder: Equatable, Sendable {
  /// Stable for one class on one day, so that scheduling it again replaces it.
  public var id: String
  public var fireDate: Date
  public var start: Date
  public var courseID: UUID
  public var code: String
  public var title: String
  public var location: String
}

public enum NotificationPlanner {
  /// The deadline reminders to have scheduled: the ones the preferences allow, not done, still to come, soonest first and
  /// no more than `limit`, moved out of the quiet hours.
  public static func deadlineReminders(
    _ book: DeadlineBook, preferences: NotificationPreferences, now: Date, calendar: Calendar, limit: Int
  ) -> [(deadline: Deadline, fireDate: Date)] {
    guard preferences.deadlinesEnabled else { return [] }
    return book.deadlines
      .compactMap { deadline -> (deadline: Deadline, fireDate: Date)? in
        guard !deadline.isDone, preferences.deadlineKinds.contains(deadline.kind),
          let fire = deadline.reminderDate(calendar: calendar)
        else { return nil }
        let adjusted = preferences.adjusted(fire, notAfter: deadline.dueInstant(calendar: calendar), calendar: calendar)
        return adjusted > now ? (deadline, adjusted) : nil
      }
      .sorted { $0.fireDate < $1.fireDate }
      .prefix(limit)
      .map { $0 }
  }

  /// A reminder for every class in the next `horizonDays` days (not for muted courses, and none outside a term's dates),
  /// soonest first and no more than `limit`. They are made for days ahead rather than as a weekly repeat so that they stop
  /// by themselves at the end of a term or when the app can no longer be opened.
  public static func classReminders(
    _ library: TimetableLibrary, preferences: NotificationPreferences, now: Date, calendar: Calendar, horizonDays: Int,
    limit: Int
  ) -> [ClassReminder] {
    guard preferences.classesEnabled else { return [] }
    var list: [ClassReminder] = []
    let today = calendar.startOfDay(for: now)
    for offset in 0..<max(1, horizonDays) {
      guard let dayStart = calendar.date(byAdding: .day, value: offset, to: today),
        let term = library.active(on: dayStart, calendar: calendar)
      else { continue }
      let day = LocalDate(dayStart, calendar: calendar)
      for slot in term.slots(on: day, calendar: calendar) where !preferences.mutedCourseIDs.contains(slot.course.id) {
        guard let start = calendar.date(byAdding: .minute, value: slot.meeting.start.minutes, to: dayStart) else {
          continue
        }
        let planned = start.addingTimeInterval(-Double(preferences.classLeadMinutes) * 60)
        let fire = preferences.adjusted(planned, notAfter: start, calendar: calendar)
        guard fire > now else { continue }
        list.append(
          ClassReminder(
            id: "kitbag.class.\(slot.meeting.id.uuidString).\(day.text)", fireDate: fire, start: start,
            courseID: slot.course.id, code: slot.course.code, title: slot.course.title, location: slot.meeting.location)
        )
      }
    }
    return list.sorted { $0.fireDate < $1.fireDate }.prefix(limit).map { $0 }
  }
}
