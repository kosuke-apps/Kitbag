import Foundation

public enum DeadlineKind: String, CaseIterable, Codable, Sendable {
  case assignment
  case exam
  case quiz
  case project
  case other
}

/// How long before the deadline a reminder is shown.
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
  public var reminder: ReminderLead
  /// The id of the calendar event it was imported from, so that importing the same file again updates it.
  public var sourceUID: String?

  public init(
    id: UUID = UUID(), title: String, kind: DeadlineKind = .assignment, courseID: UUID? = nil, date: LocalDate,
    time: TimeOfDay? = nil, isDone: Bool = false, note: String = "", reminder: ReminderLead = .dayBefore,
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
    self.reminder = reminder
    self.sourceUID = sourceUID
  }

  private enum CodingKeys: String, CodingKey {
    case id, title, kind, courseID, date, time, isDone, note, reminder, sourceUID
  }

  /// A hand-written file may leave out everything except the title and the day.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
      title: try container.decode(String.self, forKey: .title),
      kind: try container.decodeIfPresent(DeadlineKind.self, forKey: .kind) ?? .assignment,
      courseID: try container.decodeIfPresent(UUID.self, forKey: .courseID),
      date: try container.decode(LocalDate.self, forKey: .date),
      time: try container.decodeIfPresent(TimeOfDay.self, forKey: .time),
      isDone: try container.decodeIfPresent(Bool.self, forKey: .isDone) ?? false,
      note: try container.decodeIfPresent(String.self, forKey: .note) ?? "",
      reminder: try container.decodeIfPresent(ReminderLead.self, forKey: .reminder) ?? .dayBefore,
      sourceUID: try container.decodeIfPresent(String.self, forKey: .sourceUID))
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

  /// When to remind, or nil for no reminder. A deadline with a time is reminded that long before it. One without a
  /// time is reminded at 9:00 on the day it is due, or on the day (or two days) before it.
  public func reminderDate(calendar: Calendar) -> Date? {
    guard reminder != .none else { return nil }
    if let time {
      let start = date.date(calendar: calendar)
      let due = calendar.date(byAdding: .minute, value: time.minutes, to: start) ?? start
      switch reminder {
      case .none, .atDue: return due
      case .hourBefore: return calendar.date(byAdding: .hour, value: -1, to: due)
      case .dayBefore: return calendar.date(byAdding: .day, value: -1, to: due)
      case .twoDaysBefore: return calendar.date(byAdding: .day, value: -2, to: due)
      }
    }
    let daysBefore: Int
    switch reminder {
    case .none, .atDue, .hourBefore: daysBefore = 0
    case .dayBefore: daysBefore = 1
    case .twoDaysBefore: daysBefore = 2
    }
    let day = date.adding(days: -daysBefore, calendar: calendar).date(calendar: calendar)
    return calendar.date(byAdding: .hour, value: 9, to: day)
  }
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
