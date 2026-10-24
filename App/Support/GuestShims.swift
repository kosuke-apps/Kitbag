import ObjectiveC
import UIKit
import UserNotifications

/// Two small adjustments for the apps inside Kitbag, which are built unchanged and so cannot ask the host for anything. Both
/// are made with the Objective-C runtime, touch only what belongs to a guest, and leave everything else as it was; if one
/// stops applying (a system update changes the method it replaces) the guest just behaves as it did before.
///
/// - A notification that Headway posts gets Headway's icon (`GuestNotificationBranding`).
/// - While a guest is on screen, the version it shows for itself is its own, not Kitbag's (`GuestVersionShim`).
enum GuestShims {
  /// Called once, when the app starts.
  @MainActor static func install() {
    GuestNotificationBranding.install()
    GuestVersionShim.install()
  }
}

// MARK: Notifications

/// Puts the icon of the app on a notification that Headway posts. iOS draws Kitbag's own icon at the left of every
/// notification and does not let the app change it; what can differ is a picture attached to the notification, drawn as a
/// thumbnail at the right. Headway's code makes its notifications without one, and some are posted at once (a route running
/// late, found while the app runs in the background), so they cannot be touched afterwards: this replaces the one method
/// that adds a notification, so that a request whose identifier starts with `headway.` is given the picture on its way in.
/// Headway's reminders that were scheduled earlier are set again by `ReminderScheduler`.
enum GuestNotificationBranding {
  static let decoratedKey = "kitbag.decorated"
  private static let lock = NSLock()
  nonisolated(unsafe) private static var icon: Data?

  @MainActor static func install() {
    lock.withLock { icon = GuestIcon.load("Headway")?.pngData() }
    guard
      let original = class_getInstanceMethod(
        UNUserNotificationCenter.self, #selector(UNUserNotificationCenter.add(_:withCompletionHandler:))),
      let replacement = class_getInstanceMethod(
        UNUserNotificationCenter.self, #selector(UNUserNotificationCenter.kitbagAdd(_:withCompletionHandler:)))
    else { return }
    method_exchangeImplementations(original, replacement)
  }

  /// The request as it should be added: Headway's with its icon attached; any other as it is.
  static func decorated(_ request: UNNotificationRequest) -> UNNotificationRequest {
    guard request.identifier.hasPrefix("headway."), request.content.userInfo[decoratedKey] == nil,
      let png = lock.withLock({ icon }),
      let content = request.content.mutableCopy() as? UNMutableNotificationContent
    else { return request }
    let url = FileManager.default.temporaryDirectory.appending(path: "kitbag-icon-\(UUID().uuidString).png")
    guard (try? png.write(to: url)) != nil,
      let attachment = try? UNNotificationAttachment(identifier: "headway", url: url)
    else { return request }
    content.attachments = [attachment]
    var info = content.userInfo
    info[decoratedKey] = true
    content.userInfo = info
    return UNNotificationRequest(identifier: request.identifier, content: content, trigger: request.trigger)
  }
}

extension UNUserNotificationCenter {
  /// After the methods are exchanged, this name runs the original: it adds what `decorated` makes of the request.
  @objc fileprivate func kitbagAdd(
    _ request: UNNotificationRequest, withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?
  ) {
    kitbagAdd(GuestNotificationBranding.decorated(request), withCompletionHandler: completionHandler)
  }
}

// MARK: Version

/// The apps inside Kitbag show their version in their own settings, reading it from the app's Info.plist, which is Kitbag's.
/// While one of them is on screen, the version of the main bundle's Info dictionary is that app's own (from
/// `GuestVersions.json`, which tools/sync_guests.sh writes from the guest's project file). Kitbag's own screens never run
/// while a guest is open, so they still show Kitbag's.
enum GuestVersionShim {
  struct Version: Decodable {
    let version: String
    let build: String
  }

  private static let lock = NSLock()
  nonisolated(unsafe) private static var current: Version?
  nonisolated(unsafe) private static var all: [String: Version] = [:]

  @MainActor static func install() {
    if let url = Bundle.main.url(forResource: "GuestVersions", withExtension: "json"),
      let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([String: Version].self, from: data)
    {
      lock.withLock { all = decoded }
    }
    guard let original = class_getInstanceMethod(Bundle.self, #selector(getter: Bundle.infoDictionary)),
      let replacement = class_getInstanceMethod(Bundle.self, #selector(Bundle.kitbagInfoDictionary))
    else { return }
    method_exchangeImplementations(original, replacement)
  }

  /// The version of a guest (by its name in `tools/guests.txt`), or nil when none is known.
  static func version(of guest: String) -> Version? { lock.withLock { all[guest] } }

  /// Says which guest is on screen, or none.
  static func show(_ guest: String?) {
    lock.withLock { current = guest.flatMap { all[$0] } }
  }

  fileprivate static var shown: Version? { lock.withLock { current } }
}

extension Bundle {
  /// After the methods are exchanged, this name runs the original getter.
  @objc fileprivate func kitbagInfoDictionary() -> [String: Any]? {
    var info = kitbagInfoDictionary()
    if self === Bundle.main, let guest = GuestVersionShim.shown, info != nil {
      info?["CFBundleShortVersionString"] = guest.version
      info?["CFBundleVersion"] = guest.build
    }
    return info
  }
}
