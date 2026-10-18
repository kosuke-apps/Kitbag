import Foundation
import Testing

@testable import KitbagCore

private func makeFolder() throws -> URL {
  let url = FileManager.default.temporaryDirectory.appending(path: "kitbag-backup-test-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

private let moment = Date(timeIntervalSince1970: 1_790_000_000)

@Suite("BackupArchive")
struct BackupArchiveTests {
  @Test func roundTripsFilesOfAnySize() throws {
    let work = try makeFolder()
    defer { try? FileManager.default.removeItem(at: work) }
    let small = work.appending(path: "a.json")
    let empty = work.appending(path: "empty")
    let large = work.appending(path: "large.bin")
    try Data("{\"x\":1}".utf8).write(to: small)
    try Data().write(to: empty)
    // More than one chunk, with a pattern that would show a byte out of place.
    let bytes = Data((0..<(3 << 20) + 17).map { UInt8(truncatingIfNeeded: $0 &* 31) })
    try bytes.write(to: large)

    let backup = work.appending(path: "out.kitbag")
    try BackupArchive.write(
      [("data/a.json", small), ("attachments/n1/f1/empty", empty), ("attachments/n1/f2/large.bin", large)],
      createdAt: moment, to: backup)

    let manifest = try BackupArchive.manifest(of: backup)
    #expect(manifest.entries.map(\.path) == ["data/a.json", "attachments/n1/f1/empty", "attachments/n1/f2/large.bin"])
    #expect(manifest.entries.map(\.size) == [7, 0, bytes.count])
    #expect(manifest.createdAt == moment)

    let out = work.appending(path: "unpacked")
    try BackupArchive.unpack(backup, into: out)
    #expect(try Data(contentsOf: out.appending(path: "data/a.json")) == Data("{\"x\":1}".utf8))
    #expect(try Data(contentsOf: out.appending(path: "attachments/n1/f1/empty")).isEmpty)
    #expect(try Data(contentsOf: out.appending(path: "attachments/n1/f2/large.bin")) == bytes)
  }

  @Test func refusesNamesThatLeaveTheFolder() throws {
    let work = try makeFolder()
    defer { try? FileManager.default.removeItem(at: work) }
    let file = work.appending(path: "a")
    try Data("x".utf8).write(to: file)
    for bad in ["../evil", "/etc/passwd", "a/../../b", "", "a//b", "./a"] {
      #expect(throws: BackupArchive.Failure.unsafePath(bad)) {
        try BackupArchive.write([(bad, file)], createdAt: moment, to: work.appending(path: "x"))
      }
    }
  }

  @Test func refusesAHandMadeBackupWithAnUnsafeName() throws {
    let work = try makeFolder()
    defer { try? FileManager.default.removeItem(at: work) }
    let manifest = Data(
      """
      {"version":1,"createdAt":"2026-10-18T00:00:00Z","entries":[{"path":"../escape","size":1}]}
      """.utf8)
    var length = UInt64(manifest.count).bigEndian
    var data = Data("KITBAGBACKUP1\n".utf8)
    data.append(Data(bytes: &length, count: 8))
    data.append(manifest)
    data.append(Data("x".utf8))
    let backup = work.appending(path: "evil.kitbag")
    try data.write(to: backup)
    let out = work.appending(path: "out")
    #expect(throws: BackupArchive.Failure.unsafePath("../escape")) {
      try BackupArchive.unpack(backup, into: out)
    }
    #expect(!FileManager.default.fileExists(atPath: work.appending(path: "escape").path))
  }

  @Test func recognisesWhatIsNotABackupOrIsCutShort() throws {
    let work = try makeFolder()
    defer { try? FileManager.default.removeItem(at: work) }
    let junk = work.appending(path: "junk")
    try Data("this is not a backup at all".utf8).write(to: junk)
    #expect(throws: BackupArchive.Failure.notABackup) { try BackupArchive.manifest(of: junk) }

    let file = work.appending(path: "a")
    try Data(repeating: 7, count: 5000).write(to: file)
    let backup = work.appending(path: "ok.kitbag")
    try BackupArchive.write([("data/a", file)], createdAt: moment, to: backup)
    let whole = try Data(contentsOf: backup)
    let cut = work.appending(path: "cut.kitbag")
    try whole.prefix(whole.count - 100).write(to: cut)
    #expect(throws: BackupArchive.Failure.truncated) {
      try BackupArchive.unpack(cut, into: work.appending(path: "o"))
    }
  }

  @Test func refusesABackupFromANewerKitbag() throws {
    let work = try makeFolder()
    defer { try? FileManager.default.removeItem(at: work) }
    let manifest = Data("{\"version\":99,\"createdAt\":\"2026-10-18T00:00:00Z\",\"entries\":[]}".utf8)
    var length = UInt64(manifest.count).bigEndian
    var data = Data("KITBAGBACKUP1\n".utf8)
    data.append(Data(bytes: &length, count: 8))
    data.append(manifest)
    let backup = work.appending(path: "future.kitbag")
    try data.write(to: backup)
    #expect(throws: BackupArchive.Failure.newerVersion(99)) { try BackupArchive.manifest(of: backup) }
  }
}
