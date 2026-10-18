import Foundation

/// How an event repeats: the subset of iCalendar's RRULE that school and work calendars use.
public struct Recurrence: Hashable, Codable, Sendable {
  public enum Frequency: String, Codable, Sendable {
    case daily
    case weekly
    case monthly
    case yearly
  }

  public var frequency: Frequency
  public var interval: Int
  /// The number of occurrences in all, when the rule is counted.
  public var count: Int?
  /// The last moment an occurrence may start, when the rule ends on a date.
  public var until: Date?
  /// For weekly rules, the days of the week; empty means the weekday of the first occurrence.
  public var days: [Weekday]

  public init(frequency: Frequency, interval: Int = 1, count: Int? = nil, until: Date? = nil, days: [Weekday] = []) {
    self.frequency = frequency
    self.interval = max(interval, 1)
    self.count = count
    self.until = until
    self.days = Array(Set(days)).sorted()
  }
}

/// An event or task from an iCalendar file or feed.
public struct CalendarEvent: Hashable, Codable, Identifiable, Sendable {
  /// The calendar's own id (UID) for the event.
  public var id: String
  public var title: String
  public var notes: String
  public var location: String
  /// When it starts. For an all-day event, midnight UTC of its day (an all-day event has no time zone).
  public var start: Date
  public var end: Date?
  public var isAllDay: Bool
  /// A task (VTODO) rather than an event; its `start` is the due moment.
  public var isTask: Bool
  public var isCompleted: Bool
  public var recurrence: Recurrence?
  /// Starts that are left out of a repeating event.
  public var exceptions: [Date]
  /// The time zone the event was written in (`America/Chicago`); repeating events keep their wall-clock time in it.
  public var timeZoneID: String?
  /// A Kitbag deadline's kind and course, when the file came from Kitbag.
  public var kitbagKind: String?
  public var kitbagCourse: String?
  public var kitbagDone: Bool

  public init(
    id: String, title: String, notes: String = "", location: String = "", start: Date, end: Date? = nil,
    isAllDay: Bool = false, isTask: Bool = false, isCompleted: Bool = false, recurrence: Recurrence? = nil,
    exceptions: [Date] = [], timeZoneID: String? = nil, kitbagKind: String? = nil, kitbagCourse: String? = nil,
    kitbagDone: Bool = false
  ) {
    self.id = id
    self.title = title
    self.notes = notes
    self.location = location
    self.start = start
    self.end = end
    self.isAllDay = isAllDay
    self.isTask = isTask
    self.isCompleted = isCompleted
    self.recurrence = recurrence
    self.exceptions = exceptions
    self.timeZoneID = timeZoneID
    self.kitbagKind = kitbagKind
    self.kitbagCourse = kitbagCourse
    self.kitbagDone = kitbagDone
  }

  /// One time an event takes place.
  public struct Occurrence: Hashable, Identifiable, Sendable {
    public let eventID: String
    public let title: String
    public let start: Date
    public let end: Date?
    public let isAllDay: Bool

    public var id: String { "\(eventID)@\(start.timeIntervalSince1970)" }
  }

  /// The day an occurrence starting at `start` falls on: for an all-day event the day written in the file, for others the
  /// day in the given calendar's time zone.
  public func day(of start: Date, calendar: Calendar) -> LocalDate {
    if isAllDay {
      var utc = Calendar(identifier: .gregorian)
      utc.timeZone = .gmt
      return LocalDate(start, calendar: utc)
    }
    return LocalDate(start, calendar: calendar)
  }

  /// The occurrences that start within `window`, earliest first. A repeating event is expanded by its rule (at most a few
  /// thousand occurrences); `calendar` supplies the time zone for events with none of their own.
  public func occurrences(in window: DateInterval, calendar: Calendar) -> [Occurrence] {
    func make(_ start: Date) -> Occurrence {
      let length = end.map { $0.timeIntervalSince(self.start) }
      return Occurrence(
        eventID: id, title: title, start: start, end: length.map { start.addingTimeInterval($0) }, isAllDay: isAllDay)
    }
    guard let recurrence else {
      return window.contains(start) || (isAllDay && overlaps(window)) ? [make(start)] : []
    }
    var zoneCalendar = calendar
    if !isAllDay, let timeZoneID, let zone = TimeZone(identifier: timeZoneID) { zoneCalendar.timeZone = zone }
    if isAllDay { zoneCalendar.timeZone = .gmt }
    let excluded = Set(exceptions.map { $0.timeIntervalSince1970 })
    var result: [Occurrence] = []
    var produced = 0
    for candidate in Self.starts(of: recurrence, from: start, calendar: zoneCalendar) {
      if let until = recurrence.until, candidate > until { break }
      if candidate > window.end { break }
      produced += 1
      if let count = recurrence.count, produced > count { break }
      if produced > 5000 { break }
      if candidate >= window.start, !excluded.contains(candidate.timeIntervalSince1970) {
        result.append(make(candidate))
      }
    }
    return result
  }

  private func overlaps(_ window: DateInterval) -> Bool {
    guard let end else { return false }
    return start < window.end && end > window.start
  }

  /// The starts a rule generates, from the first, in order, without end (the caller stops).
  private static func starts(of rule: Recurrence, from first: Date, calendar: Calendar) -> AnySequence<Date> {
    AnySequence { () -> AnyIterator<Date> in
      var index = 0
      var queue: [Date] = []
      return AnyIterator {
        while queue.isEmpty {
          guard index < 20000 else { return nil }
          queue = batch(rule, first, index, calendar)
          index += 1
        }
        return queue.removeFirst()
      }
    }
  }

  /// The occurrences of the `index`-th period of a rule (one day, one week, one month or one year of the series).
  private static func batch(_ rule: Recurrence, _ first: Date, _ index: Int, _ calendar: Calendar) -> [Date] {
    let step = index * rule.interval
    switch rule.frequency {
    case .daily:
      return calendar.date(byAdding: .day, value: step, to: first).map { [$0] } ?? []
    case .weekly:
      guard let weekStart = calendar.date(byAdding: .weekOfYear, value: step, to: first) else { return [] }
      if rule.days.isEmpty { return [weekStart] }
      let firstWeekday = Weekday(date: first, calendar: calendar)
      return rule.days.compactMap { day -> Date? in
        let offset = day.rawValue - firstWeekday.rawValue
        guard let moved = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
        return moved >= first ? moved : nil
      }
      .sorted()
    case .monthly:
      return calendar.date(byAdding: .month, value: step, to: first)
        .flatMap { moved in
          calendar.component(.day, from: moved) == calendar.component(.day, from: first) ? [moved] : []
        } ?? []
    case .yearly:
      return calendar.date(byAdding: .year, value: step, to: first).map { [$0] } ?? []
    }
  }
}
