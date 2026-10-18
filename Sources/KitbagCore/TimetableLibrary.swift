import Foundation

/// All the terms (semesters) the person keeps, past and future, and which one counts as the current one.
public struct TimetableLibrary: Hashable, Codable, Sendable {
  public var timetables: [Timetable]
  /// The term to fall back on when no term's dates contain today.
  public var preferredID: UUID?

  public init(timetables: [Timetable] = [], preferredID: UUID? = nil) {
    self.timetables = timetables
    self.preferredID = preferredID
  }

  public func timetable(id: UUID) -> Timetable? {
    timetables.first { $0.id == id }
  }

  /// The terms, the latest first: by start date, with those without dates after the ones with.
  public var ordered: [Timetable] {
    timetables.sorted { lhs, rhs in
      switch (lhs.startDate, rhs.startDate) {
      case (let a?, let b?): a > b
      case (_?, nil): true
      case (nil, _?): false
      case (nil, nil): (lhs.year ?? 0, lhs.season?.rawValue ?? "") > (rhs.year ?? 0, rhs.season?.rawValue ?? "")
      }
    }
  }

  /// The term in force on a day: the one whose dates contain it (the latest started, if several), else the latest term
  /// that has begun, else the preferred one, else any.
  public func active(on date: Date, calendar: Calendar) -> Timetable? {
    let today = LocalDate(date, calendar: calendar)
    let longAgo = LocalDate(year: 1, month: 1, day: 1)
    func startedLatest(_ terms: [Timetable]) -> Timetable? {
      terms.max { ($0.startDate ?? longAgo) < ($1.startDate ?? longAgo) }
    }
    let dated = timetables.filter(\.hasDates)
    if let current = startedLatest(dated.filter { $0.contains(today) }) { return current }
    if let begun = startedLatest(dated.filter { ($0.startDate ?? today) < today || $0.startDate == today }) {
      return begun
    }
    if let preferredID, let preferred = timetable(id: preferredID) { return preferred }
    return timetables.first
  }

  public mutating func upsert(_ timetable: Timetable) {
    if let index = timetables.firstIndex(where: { $0.id == timetable.id }) {
      timetables[index] = timetable
    } else {
      timetables.append(timetable)
    }
  }

  public mutating func remove(id: UUID) {
    timetables.removeAll { $0.id == id }
    if preferredID == id { preferredID = nil }
  }

  /// A copy of a term for a new one: its courses without grades and with new ids, so that editing the new term does not
  /// touch the old one and the deadlines of the old courses are not claimed by the new ones.
  public func continuing(from term: Timetable) -> [Course] {
    term.courses.map { course in
      var copy = course
      copy.id = UUID()
      copy.grade = nil
      copy.meetings = course.meetings.map { meeting in
        var m = meeting
        m.id = UUID()
        return m
      }
      return copy
    }
  }

  // MARK: Files

  private enum CodingKeys: String, CodingKey {
    case version, timetables, preferredID
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      timetables: try container.decodeIfPresent([Timetable].self, forKey: .timetables) ?? [],
      preferredID: try container.decodeIfPresent(UUID.self, forKey: .preferredID))
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(Self.fileVersion, forKey: .version)
    try container.encode(timetables, forKey: .timetables)
    try container.encodeIfPresent(preferredID, forKey: .preferredID)
  }

  public static let fileVersion = 1

  public func fileData() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(self)
  }

  public init(fileData: Data) throws {
    self = try JSONDecoder().decode(TimetableLibrary.self, from: fileData)
  }
}
