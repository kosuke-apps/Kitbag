import Foundation

/// How automatic backups in a folder are named and kept. A backup is `Kitbag 2026-10-18.kitbag`: one per day, so a second
/// backup on the same day replaces the first, and the date in the name is what decides which is the newest and which are
/// old enough to remove. Other files in the folder are never touched.
public enum BackupNaming {
  public static let prefix = "Kitbag "
  public static let fileExtension = "kitbag"

  /// `Kitbag 2026-10-18.kitbag`, for the day `date` falls on in `calendar`.
  public static func fileName(for date: Date, calendar: Calendar) -> String {
    "\(prefix)\(LocalDate(date, calendar: calendar).text).\(fileExtension)"
  }

  /// The day in a name made by `fileName`, or nil for any other name.
  public static func day(in name: String) -> LocalDate? {
    guard name.hasPrefix(prefix), name.hasSuffix(".\(fileExtension)") else { return nil }
    let text = name.dropFirst(prefix.count).dropLast(fileExtension.count + 1)
    return LocalDate(String(text))
  }

  /// The names among `existing` that are automatic backups, the newest day first.
  public static func backups(in existing: [String]) -> [String] {
    existing.compactMap { name in day(in: name).map { (name, $0) } }
      .sorted { $0.1 > $1.1 }
      .map(\.0)
  }

  /// The automatic backups to remove so that only the newest `keep` remain.
  public static func namesToPrune(existing: [String], keep: Int) -> [String] {
    Array(backups(in: existing).dropFirst(max(1, keep)))
  }

  /// Whether another automatic backup is due: none was made yet, or the last was made `minimumHours` or more ago.
  public static func isDue(lastBackup: Date?, now: Date, minimumHours: Double = 20) -> Bool {
    guard let lastBackup else { return true }
    return now.timeIntervalSince(lastBackup) >= minimumHours * 3600
  }
}
