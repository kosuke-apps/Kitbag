import Foundation

/// Which notifications of the apps inside Kitbag are given an icon. iOS draws Kitbag's icon at the left of every notification
/// and cannot be told otherwise, so what can differ is one picture attached to the notification, drawn as a thumbnail at the
/// right; the app puts Headway's there (`GuestNotificationBranding`).
public enum GuestNotificationRule {
  /// The start of the identifier of every notification Headway makes.
  public static let headwayPrefix = "headway."

  /// Whether to attach Headway's icon to a notification that is about to be added or is waiting.
  ///
  /// Only a notification of Headway's, and only one that has no picture yet: since Headway 0.7 its late and early
  /// notifications carry one of their own (the route's colour and the minutes), which is what they have to say, and only one
  /// picture is drawn. One that was branded already is left alone, so that setting it again changes nothing.
  public static func shouldAddHeadwayIcon(identifier: String, attachmentCount: Int, alreadyBranded: Bool) -> Bool {
    identifier.hasPrefix(headwayPrefix) && attachmentCount == 0 && !alreadyBranded
  }
}
