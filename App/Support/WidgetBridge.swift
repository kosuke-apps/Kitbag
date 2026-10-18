import Foundation
import WidgetKit

/// Copies what the widgets show into the shared App Group folder and asks them to redraw. The copy is derived data: the
/// app's own files stay the only source, and losing the copy loses nothing.
enum WidgetBridge {
  /// The files the widgets read, by the same names as in the app's own folder.
  private static let files = ["timetables.json", "deadlines.json"]

  @MainActor
  static func sync(theme: ThemeID) {
    guard let group = AppGroup.containerURL else { return }
    var changed = false
    for name in files {
      guard let data = try? Data(contentsOf: AppFiles.url(name)) else { continue }
      let target = group.appending(path: name)
      if (try? Data(contentsOf: target)) != data {
        try? data.write(to: target, options: .atomic)
        changed = true
      }
    }
    let settings = WidgetSettings(theme: theme.rawValue)
    if let data = try? JSONEncoder().encode(settings), let url = AppGroup.url(AppGroup.settingsFile),
      (try? Data(contentsOf: url)) != data
    {
      try? data.write(to: url, options: .atomic)
      changed = true
    }
    if changed { WidgetCenter.shared.reloadAllTimelines() }
  }
}
