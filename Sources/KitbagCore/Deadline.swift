import Foundation

public enum DeadlineKind: String, CaseIterable, Codable, Sendable {
  case assignment
  case exam
  case quiz
  case project
  case other
}

/// The single reminder choice that deadlines had before they could have several (`DeadlineAlert`). Files written by an
/// earlier version still say `"reminder": "dayBefore"`; it is read as the alerts it stood for and never written again.
public enum ReminderLead: String, CaseIterable, Codable, Sendable {
  case none
  case atDue
  case hourBefore
  case dayBefore
  case twoDaysBefore
}

/// Something due on a day, with or without a time: an assignment, an exam, a quiz.
public struct Deadline: Hashable, Codable, Identifiable, Sendable {
  public var id: UUID
  public var title: String
  public var kind: DeadlineKind
  /// The course it belongs to, if any (`Course.id`).
  public var courseID: UUID?
  public var date: LocalDate
  /// The time it is due; nil when it is due at some point that day.
  public var time: TimeOfDay?
  public var isDone: Bool
  public var note: String
  /// When to remind, as many times as wanted; none means this deadline stays silent.
  public var alerts: [DeadlineAlert]
  /// The id of the calendar event it was imported from, so that importing the same file again updates it.
  public var sourceUID: String?

  public init(
    id: UUID = UUID(), title: String, kind: DeadlineKind = .assignment, courseID: UUID? = nil, date: LocalDate,
    time: TimeOfDay? = nil, isDone: Bool = false, note: String = "", alerts: [DeadlineAlert]? = nil,
    sourceUID: String? = nil
  ) {
    self.id = id
    self.title = title
    self.kind = kind
    self.courseID = courseID
    self.date = date
    self.time = time
    self.isDone = isDone
    self.note = note
    self.alerts = alerts ?? DeadlineAlert.standard(for: kind)
    self.sourceUID = sourceUID
  }

  private enum CodingKeys: String, CodingKey {
    case id, title, kind, courseID, date, time, isDone, note, alerts, sourceUID
    /// Only read: what deadlines had before `alerts`.
    case reminder
  }

  /// A hand-written file may leave out everything except the title and the day. A file from before deadlines could have
  /// several reminders has one choice, `reminder`, which becomes the alerts it stood for.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try container.decodeIfPresent(DeadlineKind.self, forKey: .kind) ?? .assignment
    let alerts: [DeadlineAlert]
    if let stored = try container.decodeIfPresent([DeadlineAlert].self, forKey: .alerts) {
      alerts = stored
    } else if let lead = try container.decodeIfPresent(ReminderLead.self, forKey: .reminder) {
      alerts = lead.alerts
    } else {
      alerts = ReminderLead.dayBefore.alerts
    }
    self.init(
      id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
      title: try container.decode(String.self, forKey: .title),
      kind: kind,
      courseID: try container.decodeIfPresent(UUID.self, forKey: .courseID),
      date: try container.decode(LocalDate.self, forKey: .date),
      time: try container.decodeIfPresent(TimeOfDay.self, forKey: .time),
      isDone: try container.decodeIfPresent(Bool.self, forKey: .isDone) ?? false,
      note: try container.decodeIfPresent(String.self, forKey: .note) ?? "",
      alerts: alerts,
      sourceUID: try container.decodeIfPresent(String.self, forKey: .sourceUID))
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(title, forKey: .title)
    try container.encode(kind, forKey: .kind)
    try container.encodeIfPresent(courseID, forKey: .courseID)
    try container.encode(date, forKey: .date)
    try container.encodeIfPresent(time, forKey: .time)
    try container.encode(isDone, forKey: .isDone)
    try container.encode(note, forKey: .note)
    try container.encode(alerts, forKey: .alerts)
    try container.encodeIfPresent(sourceUID, forKey: .sourceUID)
  }

  /// The moment it is due. With no time, the last minute of the day.
  public func dueInstant(calendar: Calendar) -> Date {
    let start = date.date(calendar: calendar)
    let minutes = time?.minutes ?? (24 * 60 - 1)
    return calendar.date(byAdding: .minute, value: minutes, to: start) ?? start
  }

  public func isOverdue(at now: Date, calendar: Calendar) -> Bool {
    !isDone && dueInstant(calendar: calendar) < now
  }

  /// The moment each alert fires, the earliest first. A deadline with a time is reminded that long before it. One with no
  /// time is reminded on the day it counts back to, at the alert's own time or else `defaultTime`.
  public func alertDates(
    defaultTime: TimeOfDay = .usualReminder, calendar: Calendar
  ) -> [(alert: DeadlineAlert, fire: Date)] {
    let start = date.date(calendar: calendar)
    let due = time.flatMap { calendar.date(byAdding: .minute, value: $0.minutes, to: start) } ?? start
    return
      alerts
      .compactMap { alert in
        alert.fireDate(due: due, hasTime: time != nil, defaultTime: defaultTime, calendar: calendar).map { (alert, $0) }
      }
      .sorted { $0.fire < $1.fire }
  }
}

extension TimeOfDay {
  /// When a reminder for a deadline with no time is shown, until the person chooses another.
  public static let usualReminder = TimeOfDay(hour: 9, minute: 0)
}

/// Where a deadline falls relative to today, for grouping a list.
public enum DeadlineBucket: Hashable, Sendable {
  case overdue
  case today
  case tomorrow
  /// The next seven days after tomorrow's.
  case thisWeek
  case later
}

/// All the deadlines, and the questions a calendar asks of them.
public struct DeadlineBook: Hashable, Codable, Sendable {
  public var deadlines: [Deadline]

  public init(deadlines: [Deadline] = []) {
    self.deadlines = deadlines
  }

  private func ordered(_ list: [Deadline], calendar: Calendar) -> [Deadline] {
    list.sorted { lhs, rhs in
      let (a, b) = (lhs.dueInstant(calendar: calendar), rhs.dueInstant(calendar: calendar))
      return a == b ? lhs.title < rhs.title : a < b
    }
  }

  /// Everything due on a day, done or not, earliest first.
  public func on(_ day: LocalDate, calendar: Calendar) -> [Deadline] {
    ordered(deadlines.filter { $0.date == day }, calendar: calendar)
  }

  /// Not done and not yet due, earliest first.
  public func upcoming(after now: Date, calendar: Calendar) -> [Deadline] {
    ordered(deadlines.filter { !$0.isDone && $0.dueInstant(calendar: calendar) >= now }, calendar: calendar)
  }

  /// Not done and already due, the longest overdue first.
  public func overdue(at now: Date, calendar: Calendar) -> [Deadline] {
    ordered(deadlines.filter { $0.isOverdue(at: now, calendar: calendar) }, calendar: calendar)
  }

  /// Done, the latest first.
  public func done(calendar: Calendar) -> [Deadline] {
    ordered(deadlines.filter(\.isDone), calendar: calendar).reversed()
  }

  public func bucket(for deadline: Deadline, now: Date, calendar: Calendar) -> DeadlineBucket {
    if deadline.isOverdue(at: now, calendar: calendar) { return .overdue }
    let today = LocalDate(now, calendar: calendar)
    let ahead = deadline.date.days(since: today, calendar: calendar)
    switch ahead {
    case ...0: return .today
    case 1: return .tomorrow
    case 2...8: return .thisWeek
    default: return .later
    }
  }

  /// The not-done deadlines grouped in the order a list shows them; empty groups are left out.
  public func grouped(now: Date, calendar: Calendar) -> [(bucket: DeadlineBucket, deadlines: [Deadline])] {
    let open = ordered(deadlines.filter { !$0.isDone }, calendar: calendar)
    let order: [DeadlineBucket] = [.overdue, .today, .tomorrow, .thisWeek, .later]
    return order.compactMap { bucket in
      let members = open.filter { self.bucket(for: $0, now: now, calendar: calendar) == bucket }
      return members.isEmpty ? nil : (bucket, members)
    }
  }

  /// The kinds of the deadlines on a day that are not done, for the dots on a month page.
  public func openKinds(on day: LocalDate) -> [DeadlineKind] {
    deadlines.filter { $0.date == day && !$0.isDone }.map(\.kind)
  }

  public func hasDeadlines(on day: LocalDate) -> Bool {
    deadlines.contains { $0.date == day }
  }

  public mutating func upsert(_ deadline: Deadline) {
    if let index = deadlines.firstIndex(where: { $0.id == deadline.id }) {
      deadlines[index] = deadline
    } else {
      deadlines.append(deadline)
    }
  }

  public mutating func remove(id: UUID) {
    deadlines.removeAll { $0.id == id }
  }

  // MARK: Files

  private enum CodingKeys: String, CodingKey {
    case version, deadlines
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(deadlines: try container.decodeIfPresent([Deadline].self, forKey: .deadlines) ?? [])
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(Self.fileVersion, forKey: .version)
    try container.encode(deadlines, forKey: .deadlines)
  }

  public static let fileVersion = 1

  public func fileData() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(self)
  }

  public init(fileData: Data) throws {
    self = try JSONDecoder().decode(DeadlineBook.self, from: fileData)
  }
}
