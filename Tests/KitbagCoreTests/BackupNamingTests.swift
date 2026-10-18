import Foundation
import Testing

@testable import KitbagCore

private let chicago: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "America/Chicago") ?? .gmt
  return calendar
}()

@Suite("BackupNaming")
struct BackupNamingTests {
  @Test func namesABackupAfterItsDay() {
    let evening = chicago.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 23, minute: 30)) ?? Date()
    #expect(BackupNaming.fileName(for: evening, calendar: chicago) == "Kitbag 2026-10-18.kitbag")
    #expect(BackupNaming.day(in: "Kitbag 2026-10-18.kitbag") == LocalDate(year: 2026, month: 10, day: 18))
    #expect(BackupNaming.day(in: "Kitbag 2026-13-40.kitbag") == nil)
    #expect(BackupNaming.day(in: "notes.kitbag") == nil)
    #expect(BackupNaming.day(in: "Kitbag 2026-10-18.zip") == nil)
    #expect(BackupNaming.day(in: "Before restore 2026-10-18 11.32.03.kitbag") == nil)
  }

  @Test func ordersAndPrunesOnlyItsOwnFiles() {
    let names = [
      "Kitbag 2026-10-01.kitbag", "Kitbag 2026-10-17.kitbag", "photo.png", "Kitbag 2026-10-09.kitbag",
      "Kitbag 2026-10-18.kitbag", "My thesis.kitbag", "Kitbag 2026-09-30.kitbag",
    ]
    #expect(
      BackupNaming.backups(in: names) == [
        "Kitbag 2026-10-18.kitbag", "Kitbag 2026-10-17.kitbag", "Kitbag 2026-10-09.kitbag", "Kitbag 2026-10-01.kitbag",
        "Kitbag 2026-09-30.kitbag",
      ])
    #expect(
      BackupNaming.namesToPrune(existing: names, keep: 3) == ["Kitbag 2026-10-01.kitbag", "Kitbag 2026-09-30.kitbag"])
    #expect(BackupNaming.namesToPrune(existing: names, keep: 10).isEmpty)
    // At least the newest is always kept.
    #expect(BackupNaming.namesToPrune(existing: names, keep: 0).count == 4)
  }

  @Test func decidesWhenAnotherBackupIsDue() {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    #expect(BackupNaming.isDue(lastBackup: nil, now: now))
    #expect(!BackupNaming.isDue(lastBackup: now.addingTimeInterval(-3600), now: now))
    #expect(!BackupNaming.isDue(lastBackup: now.addingTimeInterval(-19 * 3600), now: now))
    #expect(BackupNaming.isDue(lastBackup: now.addingTimeInterval(-20 * 3600), now: now))
  }
}
