import Foundation

/// A term's courses, and the questions a timetable answers: what is on a day, what comes next, which rows to draw.
public struct Timetable: Hashable, Codable, Sendable {
  /// The heading of the printed timetable, for example `"2026 Fall Semester Timetable (UW-Madison)"`.
  public var title: String
  public var courses: [Course]

  public init(title: String = "", courses: [Course] = []) {
    self.title = title
    self.courses = courses
  }

  /// One class on one day.
  public struct Slot: Hashable, Identifiable, Sendable {
    public let course: Course
    public let meeting: Meeting
    public let day: Weekday

    public var id: String { "\(meeting.id.uuidString)-\(day.rawValue)" }
  }

  /// The class that is on now or comes next, with its dates.
  public struct Upcoming: Hashable, Sendable {
    public let slot: Slot
    public let start: Date
    public let end: Date

    public func isInProgress(at date: Date) -> Bool { start <= date && date < end }
  }

  /// Every class on a weekday, earliest first.
  public func slots(on day: Weekday) -> [Slot] {
    courses
      .flatMap { course in
        course.meetings.filter { $0.days.contains(day) }.map { Slot(course: course, meeting: $0, day: day) }
      }
      .sorted { ($0.meeting.start, $0.course.code) < ($1.meeting.start, $1.course.code) }
  }

  /// The class in progress at `date`, or else the next one to start, looking up to `days` days ahead.
  public func upcoming(after date: Date, calendar: Calendar, days: Int = 7) -> Upcoming? {
    let today = calendar.startOfDay(for: date)
    for offset in 0...days {
      guard let dayStart = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
      for slot in slots(on: Weekday(date: dayStart, calendar: calendar)) {
        let end = Self.date(of: slot.meeting.end, on: dayStart, calendar: calendar)
        if end > date {
          return Upcoming(
            slot: slot, start: Self.date(of: slot.meeting.start, on: dayStart, calendar: calendar), end: end)
        }
      }
    }
    return nil
  }

  private static func date(of time: TimeOfDay, on dayStart: Date, calendar: Calendar) -> Date {
    if time.minutes >= 24 * 60 {
      return calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
    }
    return calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: dayStart) ?? dayStart
  }

  /// The hours to draw as rows: 8 AM to 5 PM, widened when a class falls outside them.
  public var hourRange: ClosedRange<Int> {
    let meetings = courses.flatMap(\.meetings)
    let first = min(8, meetings.map(\.start.hour).min() ?? 8)
    let last = max(17, min(23, meetings.map { ($0.end.minutes - 1) / 60 }.max() ?? 17))
    return first...last
  }

  /// Monday to Friday, plus the weekend when a class is held on it.
  public var visibleDays: [Weekday] {
    let used = Set(courses.flatMap { $0.meetings.flatMap(\.days) })
    var days = Weekday.schoolWeek
    if used.contains(.saturday) || used.contains(.sunday) { days.append(.saturday) }
    if used.contains(.sunday) { days.append(.sunday) }
    return days
  }

  // MARK: Files

  private enum CodingKeys: String, CodingKey {
    case version, title, courses
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      title: try container.decodeIfPresent(String.self, forKey: .title) ?? "",
      courses: try container.decodeIfPresent([Course].self, forKey: .courses) ?? [])
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(Self.fileVersion, forKey: .version)
    try container.encode(title, forKey: .title)
    try container.encode(courses, forKey: .courses)
  }

  /// The version written into files, for readers of a future format.
  public static let fileVersion = 1

  /// The file form: readable, with stable key order, so that two saves of the same timetable are identical.
  public func fileData() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(self)
  }

  public init(fileData: Data) throws {
    self = try JSONDecoder().decode(Timetable.self, from: fileData)
  }
}
