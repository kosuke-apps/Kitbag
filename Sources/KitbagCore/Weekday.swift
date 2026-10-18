import Foundation

/// A day of the week, numbered like ISO 8601: Monday is 1 and Sunday is 7.
public enum Weekday: Int, CaseIterable, Codable, Comparable, Sendable {
  case monday = 1
  case tuesday
  case wednesday
  case thursday
  case friday
  case saturday
  case sunday

  /// Monday to Friday, the days a school timetable shows by default.
  public static let schoolWeek: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday]

  public static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }

  /// The weekday of a date in a calendar.
  public init(date: Date, calendar: Calendar) {
    // `Calendar` numbers Sunday as 1 and Saturday as 7.
    let number = calendar.component(.weekday, from: date)
    self = Weekday(rawValue: number == 1 ? 7 : number - 1) ?? .monday
  }

  /// The index of this day in `Calendar`'s symbol arrays (`weekdaySymbols` starts with Sunday).
  public var calendarSymbolIndex: Int { rawValue % 7 }

  private static let fileNames = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]

  /// The name written to files: `"monday"`.
  public var fileName: String { Self.fileNames[rawValue - 1] }

  /// Files hold the day's name; a number from 1 (Monday) to 7 is read as well.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let name = try? container.decode(String.self), let index = Self.fileNames.firstIndex(of: name.lowercased()) {
      self = Weekday(rawValue: index + 1) ?? .monday
      return
    }
    if let number = try? container.decode(Int.self), let day = Weekday(rawValue: number) {
      self = day
      return
    }
    throw DecodingError.dataCorruptedError(
      in: container, debugDescription: "Expected a weekday name such as \"monday\".")
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(fileName)
  }
}
