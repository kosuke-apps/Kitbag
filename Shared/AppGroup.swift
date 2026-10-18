import Foundation

/// The folder that Kitbag and its widgets both can read. The app keeps its data in its own folder and copies what the
/// widgets show into this one (`WidgetBridge`), so a widget never touches the app's files and the app never depends on a
/// widget. A free Apple ID can use App Groups; the group id is registered with the team when the app is first built.
enum AppGroup {
  static let identifier = "group.dev.kosuke.kitbag"

  static var containerURL: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
  }

  static func url(_ name: String) -> URL? {
    containerURL?.appending(path: name)
  }

  /// The settings that the widgets need and cannot read from the app's own defaults.
  static let settingsFile = "widget-settings.json"
}

struct WidgetSettings: Codable, Equatable {
  /// A `ThemeID` raw value.
  var theme: String
}
