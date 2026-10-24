import KitbagCore
import Observation
import SwiftUI
import UIKit

/// A folder the person chose (in iCloud Drive, for example) where Kitbag keeps automatic backups. This is how Kitbag gets
/// its data onto another device without the iCloud capability, which a free Apple ID cannot use: the person picks the folder
/// with the system picker, Kitbag writes a dated backup into it, and the other device picks the same folder to restore the
/// newest one. It is not live sync: a device restores when asked, and the last one to back up is the newest.
@MainActor
@Observable
final class BackupFolderStore {
  private(set) var folderName: String?
  private(set) var lastBackup: Date?
  private(set) var lastError: String?
  private(set) var isWorking = false

  @ObservationIgnored private let defaults: UserDefaults
  /// The backups kept in the folder: the newest ones, one per day.
  nonisolated static let keep = 10

  /// Device-specific values that a backup must not carry to another device.
  nonisolated static let bookmarkKey = "kitbag.backupFolderBookmark"
  nonisolated static let lastBackupKey = "kitbag.backupFolderLast"
  nonisolated static let nameKey = "kitbag.backupFolderName"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    folderName = defaults.string(forKey: Self.nameKey)
    lastBackup = defaults.object(forKey: Self.lastBackupKey) as? Date
  }

  var isSet: Bool { defaults.data(forKey: Self.bookmarkKey) != nil }

  // MARK: Choosing

  /// Remembers a folder picked with the system picker.
  func choose(_ url: URL) {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    do {
      let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
      defaults.set(bookmark, forKey: Self.bookmarkKey)
      defaults.set(url.lastPathComponent, forKey: Self.nameKey)
      folderName = url.lastPathComponent
      lastError = nil
    } catch {
      lastError = L10n.string("That folder could not be used.", table: "Settings")
    }
  }

  func forget() {
    defaults.removeObject(forKey: Self.bookmarkKey)
    defaults.removeObject(forKey: Self.nameKey)
    defaults.removeObject(forKey: Self.lastBackupKey)
    folderName = nil
    lastBackup = nil
    lastError = nil
  }

  // MARK: Backing up

  /// Backs up into the folder when it is set and another backup is due (or `force`). Does nothing otherwise.
  func backUpIfDue(force: Bool = false, now: Date = Date()) async {
    guard isSet, !isWorking else { return }
    guard force || BackupNaming.isDue(lastBackup: lastBackup, now: now) else { return }
    isWorking = true
    defer { isWorking = false }
    // A few seconds of grace if the app is being left while the backup is written.
    let assertion = UIApplication.shared.beginBackgroundTask(withName: "Kitbag backup")
    defer { if assertion != .invalid { UIApplication.shared.endBackgroundTask(assertion) } }
    let bookmark = defaults.data(forKey: Self.bookmarkKey)
    let outcome = await Task.detached(priority: .utility) { () -> Result<Data?, Error> in
      Result { try Self.writeBackup(bookmark: bookmark, now: now) }
    }.value
    switch outcome {
    case .success(let renewed):
      // The system calls a bookmark stale when it still resolves but may not for much longer (after an update, or when the
      // folder was moved); a new one made now keeps the backups going.
      if let renewed { defaults.set(renewed, forKey: Self.bookmarkKey) }
      lastBackup = now
      defaults.set(now, forKey: Self.lastBackupKey)
      lastError = nil
    case .failure(let error):
      lastError = Self.describe(error)
    }
  }

  /// Writes the backup and prunes the old ones. Returns a new bookmark of the folder when the one in use had gone stale.
  nonisolated private static func writeBackup(bookmark: Data?, now: Date) throws -> Data? {
    let (folder, stale) = try resolve(bookmark)
    let scoped = folder.startAccessingSecurityScopedResource()
    defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
    let renewed =
      stale ? try? folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) : nil

    let made = try BackupManager().makeTemporaryBackup(now: now)
    defer { try? FileManager.default.removeItem(at: made.deletingLastPathComponent()) }

    let target = folder.appending(path: BackupNaming.fileName(for: now, calendar: .current))
    var coordinationError: NSError?
    var copyError: Error?
    NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordinationError) { url in
      do {
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.copyItem(at: made, to: url)
      } catch {
        copyError = error
      }
    }
    if let error = coordinationError ?? copyError { throw error }

    let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    for name in BackupNaming.namesToPrune(existing: names, keep: keep) {
      var pruneError: NSError?
      NSFileCoordinator().coordinate(
        writingItemAt: folder.appending(path: name), options: .forDeleting, error: &pruneError
      ) { url in try? FileManager.default.removeItem(at: url) }
    }
    return renewed
  }

  // MARK: Restoring

  /// A copy of the newest backup in the folder, in a temporary place, ready for the restore flow; nil when there is none.
  func newestBackupCopy() async throws -> URL? {
    let bookmark = defaults.data(forKey: Self.bookmarkKey)
    return try await Task.detached(priority: .userInitiated) { () -> URL? in
      let (folder, _) = try Self.resolve(bookmark)
      let scoped = folder.startAccessingSecurityScopedResource()
      defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
      // A file that iCloud has not downloaded yet shows up as `.Name.icloud`; its real name is what a backup is named by.
      let listed = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
      let names = listed.map { name -> String in
        name.hasPrefix(".") && name.hasSuffix(".icloud") ? String(name.dropFirst().dropLast(".icloud".count)) : name
      }
      guard let newest = BackupNaming.backups(in: names).first else { return nil }
      let source = folder.appending(path: newest)
      try? FileManager.default.startDownloadingUbiquitousItem(at: source)

      let folderCopy = FileManager.default.temporaryDirectory.appending(
        path: "KitbagFolderRestore-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: folderCopy, withIntermediateDirectories: true)
      let copy = folderCopy.appending(path: newest)
      var coordinationError: NSError?
      var copyError: Error?
      // A coordinated read waits for a file that is still downloading.
      NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { url in
        do { try FileManager.default.copyItem(at: url, to: copy) } catch { copyError = error }
      }
      if let error = coordinationError ?? copyError { throw error }
      return copy
    }.value
  }

  // MARK: Helpers

  /// The folder a bookmark points at, and whether the bookmark has gone stale.
  nonisolated private static func resolve(_ bookmark: Data?) throws -> (url: URL, stale: Bool) {
    guard let bookmark else { throw CocoaError(.fileNoSuchFile) }
    var stale = false
    let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    return (url, stale)
  }

  nonisolated private static func describe(_ error: Error) -> String {
    if (error as? CocoaError)?.code == .fileNoSuchFile {
      return L10n.string("The backup folder is not there any more. Choose it again.", table: "Settings")
    }
    return L10n.string("The backup could not be saved: \(error.localizedDescription)", table: "Settings")
  }
}
