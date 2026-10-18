import Foundation

/// One reminder of a deadline, given as a distance from when the deadline is due: "1 day before", "30 minutes before",
/// "when it is due". A deadline can have as many as it likes.
public struct DeadlineAlert: Hashable, Codable, Identifiable, Sendable {
  public enum Unit: String, CaseIterable, Codable, Sendable {
    case minutes, hours, days, weeks

    /// Days and weeks count in calendar days, so that a reminder "1 day before" keeps its clock time across a change of
    /// the clocks.
    public var isWholeDays: Bool { self == .days || self == .weeks }
  }

  public var id: UUID
  /// How many `unit`s before. 0 means when it is due (or on the day, for a deadline with no time).
  public var amount: Int
  public var unit: Unit
  /// For a deadline with no time, when on that day to remind. nil means the person's usual time.
  public var timeOfDay: TimeOfDay?

  public init(id: UUID = UUID(), amount: Int, unit: Unit, timeOfDay: TimeOfDay? = nil) {
    self.id = id
    self.amount = max(0, amount)
    self.unit = unit
    self.timeOfDay = timeOfDay
  }

  public static func minutes(_ amount: Int) -> DeadlineAlert { DeadlineAlert(amount: amount, unit: .minutes) }
  public static func hours(_ amount: Int) -> DeadlineAlert { DeadlineAlert(amount: amount, unit: .hours) }
  public static func days(_ amount: Int, at time: TimeOfDay? = nil) -> DeadlineAlert {
    DeadlineAlert(amount: amount, unit: .days, timeOfDay: time)
  }
  public static func weeks(_ amount: Int, at time: TimeOfDay? = nil) -> DeadlineAlert {
    DeadlineAlert(amount: amount, unit: .weeks, timeOfDay: time)
  }

  private enum CodingKeys: String, CodingKey { case id, amount, unit, timeOfDay }

  /// A hand-written file needs only the amount and the unit.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
      amount: try container.decode(Int.self, forKey: .amount),
      unit: try container.decode(Unit.self, forKey: .unit),
      timeOfDay: try container.decodeIfPresent(TimeOfDay.self, forKey: .timeOfDay))
  }

  /// The distance in minutes, to put alerts in order (the farthest first, as they fire).
  public var leadMinutes: Int {
    switch unit {
    case .minutes: amount
    case .hours: amount * 60
    case .days: amount * 24 * 60
    case .weeks: amount * 7 * 24 * 60
    }
  }

  /// The same distance, whatever the id and the clock time: two alerts that are alike remind at the same moment.
  public var signature: String { "\(leadMinutes)|\(timeOfDay?.minutes ?? -1)" }

  /// The moment this alert fires for a deadline due at `due`, counted back from it. For a deadline with no time `due` is
  /// the start of its day and only whole days count: the alert fires that many days earlier at `timeOfDay`.
  func fireDate(due: Date, hasTime: Bool, defaultTime: TimeOfDay, calendar: Calendar) -> Date? {
    if hasTime {
      switch unit {
      case .minutes: return calendar.date(byAdding: .minute, value: -amount, to: due)
      case .hours: return calendar.date(byAdding: .hour, value: -amount, to: due)
      case .days: return calendar.date(byAdding: .day, value: -amount, to: due)
      case .weeks: return calendar.date(byAdding: .day, value: -7 * amount, to: due)
      }
    }
    let days = unit.isWholeDays ? (unit == .weeks ? 7 * amount : amount) : 0
    guard let day = calendar.date(byAdding: .day, value: -days, to: due) else { return nil }
    let time = timeOfDay ?? defaultTime
    return calendar.date(bySettingHour: min(time.hour, 23), minute: time.minute, second: 0, of: day)
  }

  // MARK: Lists of alerts

  /// What a new deadline of a kind gets until the person chooses otherwise: more for what matters more.
  public static func standard(for kind: DeadlineKind) -> [DeadlineAlert] {
    switch kind {
    case .assignment: [.days(1), .hours(3)]
    case .exam: [.weeks(1), .days(1), .hours(1)]
    case .quiz: [.days(1), .hours(1)]
    case .project: [.weeks(1), .days(1)]
    case .other: [.days(1)]
    }
  }

  /// The alerts in the order they fire (the farthest first), without two that fire at the same moment, and, for a deadline
  /// with no time, with the ones counted in hours or minutes turned into "on the day" (they cannot mean anything else).
  public static func normalized(_ alerts: [DeadlineAlert], hasTime: Bool) -> [DeadlineAlert] {
    var seen = Set<String>()
    var list: [DeadlineAlert] = []
    for var alert in alerts {
      if !hasTime, !alert.unit.isWholeDays {
        alert.unit = .days
        alert.amount = 0
      }
      if hasTime { alert.timeOfDay = nil }
      if seen.insert(alert.signature).inserted { list.append(alert) }
    }
    return list.sorted {
      $0.leadMinutes != $1.leadMinutes
        ? $0.leadMinutes > $1.leadMinutes : ($0.timeOfDay?.minutes ?? -1) < ($1.timeOfDay?.minutes ?? -1)
    }
  }
}

extension ReminderLead {
  /// The alerts that the one choice of an earlier version stood for.
  public var alerts: [DeadlineAlert] {
    switch self {
    case .none: []
    case .atDue: [.minutes(0)]
    case .hourBefore: [.hours(1)]
    case .dayBefore: [.days(1)]
    case .twoDaysBefore: [.days(2)]
    }
  }
}
