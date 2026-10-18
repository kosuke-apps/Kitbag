import Foundation

/// A note: free text whose first line is its title. Pinned notes show on the Today screen.
public struct Note: Hashable, Codable, Identifiable, Sendable {
  public var id: UUID
  public var body: String
  public var isPinned: Bool
  public var createdAt: Date
  public var modifiedAt: Date
  /// The course it belongs to, if any (`Course.id`).
  public var courseID: UUID?

  public init(
    id: UUID = UUID(), body: String = "", isPinned: Bool = false, createdAt: Date = Date(), modifiedAt: Date? = nil,
    courseID: UUID? = nil
  ) {
    self.id = id
    self.body = body
    self.isPinned = isPinned
    self.createdAt = createdAt
    self.modifiedAt = modifiedAt ?? createdAt
    self.courseID = courseID
  }

  /// The lines that are not blank, trimmed.
  private var lines: [String] {
    body.split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }

  /// The first line, without the `#` marks of a Markdown heading. Empty for an empty note.
  public var title: String {
    guard let first = lines.first else { return "" }
    return String(first.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)
  }

  /// The text after the title, on one line and cut short, for a list row.
  public var preview: String {
    let rest = lines.dropFirst().joined(separator: " ")
    return rest.count > 160 ? String(rest.prefix(160)) + "…" : rest
  }

  public var isEmpty: Bool { lines.isEmpty }
}

/// All the notes, and the ways a list shows them.
public struct NoteBook: Hashable, Codable, Sendable {
  public var notes: [Note]

  public init(notes: [Note] = []) {
    self.notes = notes
  }

  /// Pinned notes first, then the most recently changed.
  public var sorted: [Note] {
    notes.sorted { lhs, rhs in
      if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
      return lhs.modifiedAt > rhs.modifiedAt
    }
  }

  public var pinned: [Note] { sorted.filter(\.isPinned) }

  /// Notes whose text contains every word of the query, ignoring case and accents. An empty query matches all.
  public func search(_ query: String) -> [Note] {
    let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
    guard !words.isEmpty else { return sorted }
    return sorted.filter { note in
      words.allSatisfy { note.body.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
  }

  public func note(id: UUID) -> Note? { notes.first { $0.id == id } }

  public mutating func upsert(_ note: Note) {
    if let index = notes.firstIndex(where: { $0.id == note.id }) {
      notes[index] = note
    } else {
      notes.append(note)
    }
  }

  public mutating func remove(id: UUID) {
    notes.removeAll { $0.id == id }
  }

  // MARK: Files

  private enum CodingKeys: String, CodingKey {
    case version, notes
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(notes: try container.decodeIfPresent([Note].self, forKey: .notes) ?? [])
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(Self.fileVersion, forKey: .version)
    try container.encode(notes, forKey: .notes)
  }

  public static let fileVersion = 1

  public func fileData() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(self)
  }

  public init(fileData: Data) throws {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    self = try decoder.decode(NoteBook.self, from: fileData)
  }
}
