import Foundation

/// What a backup file lists about itself: when it was made and the files inside, in order.
public struct BackupManifest: Codable, Equatable, Sendable {
  public struct Entry: Codable, Equatable, Sendable {
    /// Where the file goes, relative to the folder the backup is unpacked into: `data/notes.json`.
    public var path: String
    public var size: Int

    public init(path: String, size: Int) {
      self.path = path
      self.size = size
    }
  }

  public var version: Int
  public var createdAt: Date
  public var entries: [Entry]

  public init(version: Int = BackupArchive.currentVersion, createdAt: Date, entries: [Entry]) {
    self.version = version
    self.createdAt = createdAt
    self.entries = entries
  }
}

/// One file in one piece, with no compression: a short header, a list of the files, then their bytes one after the
/// other. It is read and written in chunks, so a backup with many photos in it never has to fit in memory, and it needs
/// no library. Anything that comes out of it is checked: a name that tries to leave the folder is refused.
///
///     KITBAGBACKUP1\n | length of the list (8 bytes, big endian) | the list (JSON) | file 1 | file 2 | ...
public enum BackupArchive {
  public static let currentVersion = 1

  public enum Failure: Error, Equatable {
    /// The file is not a Kitbag backup.
    case notABackup
    /// Made by a newer Kitbag than this one.
    case newerVersion(Int)
    /// A name that would leave the folder, or is empty.
    case unsafePath(String)
    /// The file ends before everything the list promises.
    case truncated
    /// A file changed while it was being copied.
    case changedWhileReading(String)
  }

  private static let magic = Data("KITBAGBACKUP1\n".utf8)
  private static let chunk = 1 << 20
  private static let maxManifestBytes = 16 << 20

  // MARK: Writing

  /// Writes the files to `destination`. `files` are in-backup paths and where to read each from.
  public static func write(_ files: [(path: String, source: URL)], createdAt: Date, to destination: URL) throws {
    var entries: [BackupManifest.Entry] = []
    for file in files {
      try validate(path: file.path)
      let size = try FileManager.default.attributesOfItem(atPath: file.source.path)[.size] as? Int ?? 0
      entries.append(BackupManifest.Entry(path: file.path, size: size))
    }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let manifest = try encoder.encode(BackupManifest(createdAt: createdAt, entries: entries))

    try? FileManager.default.removeItem(at: destination)
    FileManager.default.createFile(atPath: destination.path, contents: nil)
    let output = try FileHandle(forWritingTo: destination)
    defer { try? output.close() }
    try output.write(contentsOf: magic)
    var length = UInt64(manifest.count).bigEndian
    try output.write(contentsOf: Data(bytes: &length, count: 8))
    try output.write(contentsOf: manifest)
    for (file, entry) in zip(files, entries) {
      let input = try FileHandle(forReadingFrom: file.source)
      defer { try? input.close() }
      var copied = 0
      while let data = try input.read(upToCount: chunk), !data.isEmpty {
        try output.write(contentsOf: data)
        copied += data.count
      }
      if copied != entry.size { throw Failure.changedWhileReading(file.path) }
    }
  }

  // MARK: Reading

  /// The list at the start of a backup, without unpacking anything.
  public static func manifest(of url: URL) throws -> BackupManifest {
    let input = try FileHandle(forReadingFrom: url)
    defer { try? input.close() }
    return try readManifest(from: input)
  }

  /// Unpacks every file into `directory`, creating folders as needed.
  @discardableResult
  public static func unpack(_ url: URL, into directory: URL) throws -> BackupManifest {
    let input = try FileHandle(forReadingFrom: url)
    defer { try? input.close() }
    let manifest = try readManifest(from: input)
    for entry in manifest.entries { try validate(path: entry.path) }
    for entry in manifest.entries {
      let target = directory.appending(path: entry.path)
      try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
      FileManager.default.createFile(atPath: target.path, contents: nil)
      let output = try FileHandle(forWritingTo: target)
      defer { try? output.close() }
      var remaining = entry.size
      while remaining > 0 {
        guard let data = try input.read(upToCount: min(chunk, remaining)), !data.isEmpty else {
          throw Failure.truncated
        }
        try output.write(contentsOf: data)
        remaining -= data.count
      }
    }
    return manifest
  }

  private static func readManifest(from input: FileHandle) throws -> BackupManifest {
    guard let head = try input.read(upToCount: magic.count + 8), head.count == magic.count + 8,
      head.prefix(magic.count) == magic
    else { throw Failure.notABackup }
    let length = head.suffix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    guard length > 0, length <= UInt64(maxManifestBytes) else { throw Failure.notABackup }
    guard let body = try input.read(upToCount: Int(length)), body.count == Int(length) else { throw Failure.truncated }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let manifest = try? decoder.decode(BackupManifest.self, from: body) else { throw Failure.notABackup }
    if manifest.version > currentVersion { throw Failure.newerVersion(manifest.version) }
    return manifest
  }

  /// A path must be relative, have no empty, `.` or `..` part and be of a sane length.
  static func validate(path: String) throws {
    let parts = path.split(separator: "/", omittingEmptySubsequences: false)
    guard !path.isEmpty, path.count <= 512, !path.hasPrefix("/"), !path.contains("\0"),
      !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
    else { throw Failure.unsafePath(path) }
  }
}
