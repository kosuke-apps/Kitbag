import Foundation

/// Where Kitbag keeps its data files: JSON in the app's Application Support folder.
enum AppFiles {
  static func url(_ name: String) -> URL {
    URL.applicationSupportDirectory.appending(path: "Kitbag/\(name)")
  }

  static func write(_ data: Data, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
  }

  /// Moves a file that could not be read out of the way, so that the next save does not overwrite it.
  static func setAside(_ url: URL) {
    let stamp = Int(Date().timeIntervalSince1970)
    let name = url.deletingPathExtension().lastPathComponent
    let aside = url.deletingLastPathComponent().appending(path: "\(name).unreadable-\(stamp).json")
    try? FileManager.default.moveItem(at: url, to: aside)
  }
}
