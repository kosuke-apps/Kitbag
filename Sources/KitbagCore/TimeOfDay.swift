import Foundation

/// A time of day with minute precision, independent of any date or time zone.
///
/// It is stored and written as 24-hour text, `"13:20"`, so that a timetable file can be read and edited by hand.
public struct TimeOfDay: Hashable, Comparable, Codable, Sendable {
  /// Minutes since midnight. 24:00 (1440) is allowed as the end of the day.
  public var minutes: Int

  public init(minutes: Int) {
    self.minutes = min(max(minutes, 0), 24 * 60)
  }

  public init(hour: Int, minute: Int) {
    self.init(minutes: hour * 60 + minute)
  }

  /// Reads `"8:50"` or `"13:20"` (24-hour). Returns nil for anything else.
  public init?(_ text: String) {
    let parts = text.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2, parts[1].count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
      (0...24).contains(hour), (0...59).contains(minute), hour * 60 + minute <= 24 * 60
    else { return nil }
    self.init(hour: hour, minute: minute)
  }

  public var hour: Int { minutes / 60 }
  public var minute: Int { minutes % 60 }

  /// `"13:20"`, the form that is written to files.
  public var text: String { String(format: "%d:%02d", hour, minute) }

  /// `"1:20"`: the 12-hour clock without AM or PM, as a printed school timetable shows it.
  public var twelveHourText: String {
    let h = hour % 12 == 0 ? 12 : hour % 12
    return String(format: "%d:%02d", h, minute)
  }

  public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool { lhs.minutes < rhs.minutes }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let string = try container.decode(String.self)
    guard let time = TimeOfDay(string) else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Expected a 24-hour time such as \"13:20\", found \"\(string)\".")
    }
    self = time
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(text)
  }
}
