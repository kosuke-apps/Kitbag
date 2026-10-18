import Foundation

/// The colours a course can take on the timetable. The app draws each name in a light and a dark variant.
public enum CourseColor: String, CaseIterable, Codable, Sendable {
  case lavender
  case periwinkle
  case mint
  case rose
  case peach
  case butter
  case sky
  case sage
}

/// One recurring class of a course: a lecture, a lab or a discussion, on one or more weekdays.
public struct Meeting: Hashable, Codable, Identifiable, Sendable {
  public var id: UUID
  /// The kind of section as the university writes it: `"LEC"`, `"LAB"`, `"DIS"`.
  public var kind: String
  /// The section number as written: `"001"`.
  public var section: String
  public var days: [Weekday]
  public var start: TimeOfDay
  public var end: TimeOfDay
  public var location: String
  public var instructor: String

  public init(
    id: UUID = UUID(), kind: String, section: String, days: [Weekday], start: TimeOfDay, end: TimeOfDay,
    location: String = "", instructor: String = ""
  ) {
    self.id = id
    self.kind = kind
    self.section = section
    self.days = Array(Set(days)).sorted()
    self.start = start
    self.end = end
    self.location = location
    self.instructor = instructor
  }

  private enum CodingKeys: String, CodingKey {
    case id, kind, section, days, start, end, location, instructor
  }

  /// A hand-written file may leave out the id, the location and the instructor.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
      kind: try container.decodeIfPresent(String.self, forKey: .kind) ?? "",
      section: try container.decodeIfPresent(String.self, forKey: .section) ?? "",
      days: try container.decode([Weekday].self, forKey: .days),
      start: try container.decode(TimeOfDay.self, forKey: .start),
      end: try container.decode(TimeOfDay.self, forKey: .end),
      location: try container.decodeIfPresent(String.self, forKey: .location) ?? "",
      instructor: try container.decodeIfPresent(String.self, forKey: .instructor) ?? "")
  }

  /// `"LEC 001"`.
  public var label: String { [kind, section].filter { !$0.isEmpty }.joined(separator: " ") }
}

/// A course with the meetings that make it up.
public struct Course: Hashable, Codable, Identifiable, Sendable {
  public var id: UUID
  /// The catalogue code as the university writes it: `"A B 123"`.
  public var code: String
  public var title: String
  public var color: CourseColor
  public var meetings: [Meeting]
  /// The credits (units) the course is worth, if known.
  public var credits: Double?
  /// The grade received, as the grade scale writes it (`"AB"`); nil until there is one.
  public var grade: String?

  public init(
    id: UUID = UUID(), code: String, title: String = "", color: CourseColor = .lavender, meetings: [Meeting] = [],
    credits: Double? = nil, grade: String? = nil
  ) {
    self.id = id
    self.code = code
    self.title = title
    self.color = color
    self.meetings = meetings
    self.credits = credits
    self.grade = grade
  }

  private enum CodingKeys: String, CodingKey {
    case id, code, title, color, meetings, credits, grade
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
      code: try container.decode(String.self, forKey: .code),
      title: try container.decodeIfPresent(String.self, forKey: .title) ?? "",
      color: try container.decodeIfPresent(CourseColor.self, forKey: .color) ?? .lavender,
      meetings: try container.decodeIfPresent([Meeting].self, forKey: .meetings) ?? [],
      credits: try container.decodeIfPresent(Double.self, forKey: .credits),
      grade: try container.decodeIfPresent(String.self, forKey: .grade))
  }

  /// The instructors of the course's classes, each once, in the order they appear.
  public var instructors: [String] {
    var seen = Set<String>()
    return meetings.map(\.instructor).filter { !$0.isEmpty && seen.insert($0).inserted }
  }

  /// The sections this course is taken in, as a printed timetable's legend writes them: `"LEC 001 + LAB 309"`.
  public var sectionsSummary: String {
    var seen = Set<String>()
    return meetings.map(\.label).filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: " + ")
  }
}
