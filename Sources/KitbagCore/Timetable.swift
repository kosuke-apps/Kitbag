import Foundation

public enum Season: String, CaseIterable, Codable, Sendable {
  case spring
  case summer
  case fall
  case winter
}

/// One term's courses (a semester's timetable), and the questions it answers: what is on a day, what comes next, which
/// rows to draw, where in the term a day falls.
public struct Timetable: Hashable, Codable, Identifiable, Sendable {
  public var id: UUID
  /// The heading of the printed timetable, for example `"2026 Fall Semester Timetable (UW-Madison)"`.
  public var title: String
  public var year: Int?
  public var season: Season?
  /// The first and last day of classes. With neither set, every day counts as in the term.
  public var startDate: LocalDate?
  public var endDate: LocalDate?
  public var courses: [Course]
  /// The id of the grade scale this term is graded on, when it is not the one chosen for everything (a term abroad).
  public var gradeScaleID: String?
  /// Whether the term counts in the cumulative GPA.
  public var countsInCumulativeGPA: Bool
  /// A term entered only for its grades (an old one): it has no classes to draw, and is never the term in force.
  public var gradesOnly: Bool

  public init(
    id: UUID = UUID(), title: String = "", year: Int? = nil, season: Season? = nil, startDate: LocalDate? = nil,
    endDate: LocalDate? = nil, courses: [Course] = [], gradeScaleID: String? = nil, countsInCumulativeGPA: Bool = true,
    gradesOnly: Bool = false
  ) {
    self.id = id
    self.title = title
    self.year = year
    self.season = season
    self.startDate = startDate
    self.endDate = endDate
    self.courses = courses
    self.gradeScaleID = gradeScaleID
    self.countsInCumulativeGPA = countsInCumulativeGPA
    self.gradesOnly = gradesOnly
  }

  /// A term kept for its grades whose courses have no classes: there is nothing to draw.
  public var isGradesOnly: Bool { gradesOnly && courses.allSatisfy { $0.meetings.isEmpty } }

  /// Whether classes are held on this day: it lies within the term's dates (when they are set).
  public func contains(_ day: LocalDate) -> Bool {
    if let startDate, day < startDate { return false }
    if let endDate, day > endDate { return false }
    return true
  }

  public var hasDates: Bool { startDate != nil || endDate != nil }

  /// The week of the term that a day is in, counting from 1 for the week of the first day; nil before it or with no start.
  public func weekNumber(on day: LocalDate, calendar: Calendar) -> Int? {
    guard let startDate else { return nil }
    let days = day.days(since: startDate, calendar: calendar)
    return days >= 0 ? days / 7 + 1 : nil
  }

  /// The number of weeks from the first to the last day, when both are set.
  public func totalWeeks(calendar: Calendar) -> Int? {
    guard let startDate, let endDate, endDate >= startDate else { return nil }
    return endDate.days(since: startDate, calendar: calendar) / 7 + 1
  }

  public var totalCredits: Double { courses.compactMap(\.credits).reduce(0, +) }

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

  public func course(id: UUID) -> Course? {
    courses.first { $0.id == id }
  }

  /// Every class on a weekday, earliest first.
  public func slots(on day: Weekday) -> [Slot] {
    courses
      .flatMap { course in
        course.meetings.filter { $0.days.contains(day) }.map { Slot(course: course, meeting: $0, day: day) }
      }
      .sorted { ($0.meeting.start, $0.course.code) < ($1.meeting.start, $1.course.code) }
  }

  /// Every class on a day: none outside the term's dates.
  public func slots(on day: LocalDate, calendar: Calendar) -> [Slot] {
    contains(day) ? slots(on: day.weekday(calendar: calendar)) : []
  }

  /// The class in progress at `date`, or else the next one to start, looking up to `days` days ahead. Days outside the
  /// term's dates are skipped.
  public func upcoming(after date: Date, calendar: Calendar, days: Int = 14) -> Upcoming? {
    let today = calendar.startOfDay(for: date)
    for offset in 0...days {
      guard let dayStart = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
      for slot in slots(on: LocalDate(dayStart, calendar: calendar), calendar: calendar) {
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
    case version, id, title, year, season, startDate, endDate, courses, gradeScaleID, countsInCumulativeGPA, gradesOnly
  }

  /// Older files have no id, year, season or dates; those are left empty.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
      title: try container.decodeIfPresent(String.self, forKey: .title) ?? "",
      year: try container.decodeIfPresent(Int.self, forKey: .year),
      season: try container.decodeIfPresent(Season.self, forKey: .season),
      startDate: try container.decodeIfPresent(LocalDate.self, forKey: .startDate),
      endDate: try container.decodeIfPresent(LocalDate.self, forKey: .endDate),
      courses: try container.decodeIfPresent([Course].self, forKey: .courses) ?? [],
      gradeScaleID: try container.decodeIfPresent(String.self, forKey: .gradeScaleID),
      countsInCumulativeGPA: try container.decodeIfPresent(Bool.self, forKey: .countsInCumulativeGPA) ?? true,
      gradesOnly: try container.decodeIfPresent(Bool.self, forKey: .gradesOnly) ?? false)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(Self.fileVersion, forKey: .version)
    try container.encode(id, forKey: .id)
    try container.encode(title, forKey: .title)
    try container.encodeIfPresent(year, forKey: .year)
    try container.encodeIfPresent(season, forKey: .season)
    try container.encodeIfPresent(startDate, forKey: .startDate)
    try container.encodeIfPresent(endDate, forKey: .endDate)
    try container.encode(courses, forKey: .courses)
    try container.encodeIfPresent(gradeScaleID, forKey: .gradeScaleID)
    if !countsInCumulativeGPA { try container.encode(false, forKey: .countsInCumulativeGPA) }
    if gradesOnly { try container.encode(true, forKey: .gradesOnly) }
  }

  /// The version written into files, for readers of a future format.
  public static let fileVersion = 2

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
