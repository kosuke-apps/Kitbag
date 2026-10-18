import KitbagCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
  /// A Kitbag backup: `.kitbag`. Declared in Info.plist, so that a backup sent by AirDrop opens in Kitbag.
  static let kitbagBackup = UTType(exportedAs: "dev.kosuke.kitbag.backup")
}

/// What a backup holds, for asking the person before it replaces what is here.
struct BackupSummary {
  var createdAt: Date
  var hasTimetable: Bool
  var hasDeadlines: Bool
  var hasNotes: Bool
  var attachmentCount: Int
}

enum BackupError: Error {
  /// A file inside is not one Kitbag writes.
  case unexpectedContent
}

/// Writes everything Kitbag keeps into one file, and puts a file like that back. The backup holds the timetable, the
/// deadlines, the notes with their photos and files, and the settings (theme, layout, grade scale, weather place). It
/// leaves out what can be fetched again (weather, subscribed calendars) and the subscriptions' addresses, which are
/// secrets that should not sit in a file. The guests (Headway, Mantissa) keep their own data and are not included.
struct BackupManager {
  private static let dataFiles = ["timetables.json", "deadlines.json", "notes.json"]
  private static let settingsPrefixes = ["kitbag.", "weather."]
  private static let settingsPath = "settings.plist"

  private let fileManager = FileManager.default

  // MARK: Writing

  /// Makes a backup file in a temporary folder and returns where it is.
  func makeTemporaryBackup(now: Date = Date()) throws -> URL {
    let folder = fileManager.temporaryDirectory.appending(path: "KitbagBackup-\(UUID().uuidString)")
    try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appending(path: "Kitbag \(Self.dayText(now)).kitbag")
    try write(to: file, staging: folder, now: now)
    return file
  }

  func write(to destination: URL, staging: URL, now: Date) throws {
    var files: [(path: String, source: URL)] = []
    for name in Self.dataFiles where fileManager.fileExists(atPath: AppFiles.url(name).path) {
      files.append(("data/\(name)", AppFiles.url(name)))
    }
    let attachments = AppFiles.url("Attachments")
    if let walker = fileManager.enumerator(at: attachments, includingPropertiesForKeys: [.isRegularFileKey]) {
      for case let url as URL in walker
      where (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
        let relative = url.path.replacingOccurrences(of: attachments.path + "/", with: "")
        files.append(("attachments/\(relative)", url))
      }
    }
    let settings = staging.appending(path: Self.settingsPath)
    try settingsData().write(to: settings)
    files.append((Self.settingsPath, settings))
    try BackupArchive.write(files, createdAt: now, to: destination)
  }

  /// The settings of Kitbag in UserDefaults: the keys that start with `kitbag.` or `weather.`.
  private func settingsData() throws -> Data {
    let all = UserDefaults.standard.dictionaryRepresentation().filter { key, _ in
      Self.settingsPrefixes.contains { key.hasPrefix($0) }
    }
    return try PropertyListSerialization.data(fromPropertyList: all, format: .xml, options: 0)
  }

  // MARK: Reading

  func summary(of url: URL) throws -> BackupSummary {
    let manifest = try BackupArchive.manifest(of: url)
    let paths = manifest.entries.map(\.path)
    guard paths.allSatisfy(Self.isExpected) else { throw BackupError.unexpectedContent }
    return BackupSummary(
      createdAt: manifest.createdAt, hasTimetable: paths.contains("data/timetables.json"),
      hasDeadlines: paths.contains("data/deadlines.json"), hasNotes: paths.contains("data/notes.json"),
      attachmentCount: paths.filter { $0.hasPrefix("attachments/") }.count)
  }

  private static func isExpected(_ path: String) -> Bool {
    path == settingsPath || path.hasPrefix("attachments/") || dataFiles.map { "data/\($0)" }.contains(path)
  }

  /// Replaces what Kitbag keeps with the contents of the backup. What was there is first saved as a backup of its own in
  /// `Backups/`, which is never deleted, so a restore can be undone by restoring that.
  @discardableResult
  func restore(from url: URL, now: Date = Date()) throws -> URL {
    _ = try summary(of: url)

    let staging = fileManager.temporaryDirectory.appending(path: "KitbagRestore-\(UUID().uuidString)")
    try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: staging) }

    // Unpack first: if the file is damaged, nothing has been touched yet.
    let unpacked = staging.appending(path: "unpacked")
    try BackupArchive.unpack(url, into: unpacked)

    let safety = AppFiles.url("Backups/Before restore \(Self.stampText(now)).kitbag")
    try fileManager.createDirectory(at: safety.deletingLastPathComponent(), withIntermediateDirectories: true)
    try write(to: safety, staging: staging, now: now)

    for name in Self.dataFiles {
      let source = unpacked.appending(path: "data/\(name)")
      let target = AppFiles.url(name)
      try? fileManager.removeItem(at: target)
      if fileManager.fileExists(atPath: source.path) {
        try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: source, to: target)
      }
    }

    let attachmentsTarget = AppFiles.url("Attachments")
    try? fileManager.removeItem(at: attachmentsTarget)
    let attachmentsSource = unpacked.appending(path: "attachments")
    if fileManager.fileExists(atPath: attachmentsSource.path) {
      try fileManager.moveItem(at: attachmentsSource, to: attachmentsTarget)
    }

    let settings = unpacked.appending(path: Self.settingsPath)
    if let data = try? Data(contentsOf: settings),
      let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    {
      let defaults = UserDefaults.standard
      for key in defaults.dictionaryRepresentation().keys where Self.settingsPrefixes.contains(where: key.hasPrefix) {
        defaults.removeObject(forKey: key)
      }
      for (key, value) in values where Self.settingsPrefixes.contains(where: key.hasPrefix) {
        defaults.set(value, forKey: key)
      }
    }
    return safety
  }

  // MARK: Names

  private static func dayText(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }

  private static func stampText(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
    return formatter.string(from: date)
  }
}
