import Foundation

/// A photo or a file kept with a note. The bytes live in a file in the note's folder; this is what the note knows of it.
public struct NoteAttachment: Hashable, Codable, Identifiable, Sendable {
  public var id: UUID
  /// The name the person sees: the file's own name.
  public var name: String
  /// Where the file is kept inside the note's folder: a folder named for the attachment, then the file's own name, so
  /// that Quick Look and the share sheet show the real name and two attachments never clash.
  public var storedName: String
  public var byteCount: Int
  public var addedAt: Date

  public init(id: UUID = UUID(), name: String, storedName: String, byteCount: Int, addedAt: Date = Date()) {
    self.id = id
    self.name = name
    self.storedName = storedName
    self.byteCount = byteCount
    self.addedAt = addedAt
  }

  /// The file extensions that are shown as a picture.
  public static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "webp"]

  public var isImage: Bool {
    Self.imageExtensions.contains((storedName as NSString).pathExtension.lowercased())
  }

  /// The place for a file called `originalName`: `<id>/<name>`, with characters that cannot be in a file name replaced.
  public static func storedName(id: UUID, originalName: String) -> String {
    let cleaned = originalName.map { "/:\\".contains($0) ? "-" : $0 }
    let name = String(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
    return "\(id.uuidString)/\(name.isEmpty ? "file" : name)"
  }
}

/// A note: Markdown text whose first line is its title, and the photos and files kept with it. Pinned notes show on
/// the Today screen.
public struct Note: Hashable, Codable, Identifiable, Sendable {
  public var id: UUID
  public var body: String
  public var isPinned: Bool
  public var createdAt: Date
  public var modifiedAt: Date
  /// The course it belongs to, if any (`Course.id`).
  public var courseID: UUID?
  public var attachments: [NoteAttachment]

  public init(
    id: UUID = UUID(), body: String = "", isPinned: Bool = false, createdAt: Date = Date(), modifiedAt: Date? = nil,
    courseID: UUID? = nil, attachments: [NoteAttachment] = []
  ) {
    self.id = id
    self.body = body
    self.isPinned = isPinned
    self.createdAt = createdAt
    self.modifiedAt = modifiedAt ?? createdAt
    self.courseID = courseID
    self.attachments = attachments
  }

  private enum CodingKeys: String, CodingKey {
    case id, body, isPinned, createdAt, modifiedAt, courseID, attachments
  }

  /// A file from before attachments existed has no `attachments`.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decode(UUID.self, forKey: .id),
      body: try container.decode(String.self, forKey: .body),
      isPinned: try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false,
      createdAt: try container.decode(Date.self, forKey: .createdAt),
      modifiedAt: try container.decodeIfPresent(Date.self, forKey: .modifiedAt),
      courseID: try container.decodeIfPresent(UUID.self, forKey: .courseID),
      attachments: try container.decodeIfPresent([NoteAttachment].self, forKey: .attachments) ?? [])
  }

  /// The lines that are not blank, trimmed.
  private var lines: [String] {
    body.split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }

  /// The first line without its Markdown marks (`## **Plan**` is `Plan`). Empty for an empty note.
  public var title: String {
    guard let first = lines.first else { return "" }
    return Markdown.plain(first)
  }

  /// The text after the title, without marks, on one line and cut short, for a list row.
  public var preview: String {
    let rest = lines.dropFirst().map { Markdown.plain($0, decorated: true) }.filter { !$0.isEmpty }.joined(
      separator: " ")
    return rest.count > 160 ? String(rest.prefix(160)) + "…" : rest
  }

  /// A note with no text and nothing attached.
  public var isEmpty: Bool { lines.isEmpty && attachments.isEmpty }
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
      let haystack = ([note.body] + note.attachments.map(\.name)).joined(separator: "\n")
      return words.allSatisfy { haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
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
