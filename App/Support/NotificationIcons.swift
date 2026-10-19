import SwiftUI
import UserNotifications

/// The picture on the right of a notification, which shows which tool it came from.
///
/// iOS puts the icon of the app on the left of every notification and does not let an app change it, so for a notification
/// from Headway or from the calendar the app icon is always Kitbag's. What can differ is a picture attached to the
/// notification: it is drawn as a small thumbnail at the right of the banner. Kitbag attaches the icon of the tool, the same
/// one that tool has on the home screen.
@MainActor
enum NotificationIcon {
  /// The PNGs, made once per run.
  private static var cache: [ModuleID: Data] = [:]

  /// The tool's icon as an attachment, from a copy of the picture in a file of its own (the system moves the file it is given
  /// into its own storage, so every notification needs its own).
  static func attachment(for module: ModuleID) -> UNNotificationAttachment? {
    guard let data = png(for: module) else { return nil }
    let url = FileManager.default.temporaryDirectory.appending(path: "kitbag-icon-\(UUID().uuidString).png")
    guard (try? data.write(to: url)) != nil else { return nil }
    return try? UNNotificationAttachment(identifier: module.rawValue, url: url)
  }

  private static func png(for module: ModuleID) -> Data? {
    if let cached = cache[module] { return cached }
    let data: Data?
    switch module.icon {
    case .guest(let name):
      data = GuestIcon.load(name)?.pngData()
    case .symbol(let symbol, let color):
      let renderer = ImageRenderer(content: SymbolIcon(name: symbol, color: color, size: 96))
      renderer.scale = 3
      data = renderer.uiImage?.pngData()
    }
    cache[module] = data
    return data
  }
}
