import Foundation

/// A calendar day with no time and no time zone: `2026-10-22`. A deadline "on the 22nd" means the 22nd wherever the
/// phone is, so the day is kept as numbers and only turned into a `Date` in the calendar that asks.
public struct LocalDate: Hashable, Comparable, Codable, Sendable {
  public var year: Int
  public var month: Int
  public var day: Int

  public init(year: Int, month: Int, day: Int) {
    self.year = year
    self.month = month
    self.day = day
  }

  /// The day that `date` falls on in the calendar's time zone.
  public init(_ date: Date, calendar: Calendar) {
    let parts = Self.gregorian(like: calendar).dateComponents([.year, .month, .day], from: date)
    self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
  }

  /// Reads `"2026-10-22"`. Returns nil for anything else, including days that do not exist.
  public init?(_ text: String) {
    let parts = text.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
      let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
    else { return nil }
    let candidate = LocalDate(year: year, month: month, day: day)
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    guard let date = utc.date(from: DateComponents(year: year, month: month, day: day)),
      LocalDate(date, calendar: utc) == candidate
    else { return nil }
    self = candidate
  }

  /// `"2026-10-22"`, the form that is written to files.
  public var text: String { String(format: "%04d-%02d-%02d", year, month, day) }

  /// Midnight at the start of this day.
  public func date(calendar: Calendar) -> Date {
    Self.gregorian(like: calendar).date(from: DateComponents(year: year, month: month, day: day))
      ?? Date(timeIntervalSince1970: 0)
  }

  public func adding(days: Int, calendar: Calendar) -> LocalDate {
    let gregorian = Self.gregorian(like: calendar)
    guard let moved = gregorian.date(byAdding: .day, value: days, to: date(calendar: calendar)) else { return self }
    return LocalDate(moved, calendar: calendar)
  }

  /// The number of days from `other` to this day (negative when this day is earlier).
  public func days(since other: LocalDate, calendar: Calendar) -> Int {
    Self.gregorian(like: calendar).dateComponents(
      [.day], from: other.date(calendar: calendar), to: date(calendar: calendar)
    ).day ?? 0
  }

  public func weekday(calendar: Calendar) -> Weekday { Weekday(date: date(calendar: calendar), calendar: calendar) }

  public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
    (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
  }

  /// The Gregorian calendar in the given calendar's time zone. Day arithmetic is done in it so that a phone set to
  /// another calendar system (Japanese eras, Buddhist years) still gets the same numbers.
  static func gregorian(like calendar: Calendar) -> Calendar {
    var gregorian = Calendar(identifier: .gregorian)
    gregorian.timeZone = calendar.timeZone
    gregorian.firstWeekday = calendar.firstWeekday
    gregorian.minimumDaysInFirstWeek = calendar.minimumDaysInFirstWeek
    return gregorian
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let string = try container.decode(String.self)
    guard let date = LocalDate(string) else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Expected a day such as \"2026-10-22\", found \"\(string)\".")
    }
    self = date
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(text)
  }
}
