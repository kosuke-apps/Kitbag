import KitbagCore
import UserNotifications

/// Keeps the phone's pending notifications in step with what Kitbag wants shown: a reminder for each open deadline and
/// the warnings that the signature is about to run out. They are local notifications, so they need no server and no paid
/// developer account, and iOS shows them at the time even when Kitbag is closed.
@MainActor
struct ReminderScheduler {
  /// Room for the deadlines. iOS keeps at most 64 pending notifications per app; the signature's three and a test fit
  /// in what is left.
  static let deadlineLimit = 58

  private static let signingPrefix = "kitbag.signing."
  private let center = UNUserNotificationCenter.current()

  func status() async -> UNAuthorizationStatus {
    await center.notificationSettings().authorizationStatus
  }

  /// Asks for permission the first time; true when notifications may be shown.
  func authorize() async -> Bool {
    switch await status() {
    case .authorized, .provisional, .ephemeral: return true
    case .notDetermined: return (try? await center.requestAuthorization(options: [.alert, .sound])) == true
    default: return false
    }
  }

  /// Makes the pending notifications match the deadlines and the signature as they are now: reminders that are no longer
  /// wanted are removed, the others are added again (an existing request with the same id is replaced). Only
  /// notifications that Kitbag made are touched; a guest's own (Headway's departure reminders) are left alone.
  func sync(
    deadlines: DeadlineBook, courseCode: (UUID) -> String?, signatureExpiry: Date?, now: Date = Date(),
    calendar: Calendar = .current
  ) async {
    var wanted: [UNNotificationRequest] = []
    for (deadline, fire) in deadlines.reminderPlan(now: now, calendar: calendar, limit: Self.deadlineLimit) {
      wanted.append(
        request(
          id: deadline.id.uuidString, fire: fire, calendar: calendar,
          content: deadlineContent(deadline, courseCode: deadline.courseID.flatMap(courseCode), calendar: calendar)))
    }
    if let signatureExpiry {
      for reminder in SigningReminder.plan(expiresAt: signatureExpiry, now: now, calendar: calendar) {
        wanted.append(
          request(
            id: Self.signingPrefix + reminder.kind.rawValue, fire: reminder.fireDate, calendar: calendar,
            content: signingContent(reminder.kind, expiresAt: signatureExpiry)))
      }
    }

    let wantedIDs = Set(wanted.map(\.identifier))
    let ours = await center.pendingNotificationRequests().map(\.identifier).filter {
      UUID(uuidString: $0) != nil || $0.hasPrefix(Self.signingPrefix)
    }
    center.removePendingNotificationRequests(withIdentifiers: ours.filter { !wantedIDs.contains($0) })
    guard !wanted.isEmpty, await authorize() else { return }
    for request in wanted { try? await center.add(request) }
  }

  /// A notification in five seconds, to see that they arrive. False when they are not allowed.
  func sendTest() async -> Bool {
    guard await authorize() else { return false }
    let content = UNMutableNotificationContent()
    content.title = String(localized: "Notifications are working", table: "Settings")
    content.body = String(localized: "Kitbag can remind you of deadlines on this iPhone.", table: "Settings")
    content.sound = .default
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
    do {
      try await center.add(UNNotificationRequest(identifier: "kitbag.test", content: content, trigger: trigger))
      return true
    } catch {
      return false
    }
  }

  // MARK: Content

  private func request(
    id: String, fire: Date, calendar: Calendar, content: UNNotificationContent
  )
    -> UNNotificationRequest
  {
    let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
    return UNNotificationRequest(
      identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
  }

  private func deadlineContent(
    _ deadline: Deadline, courseCode: String?, calendar: Calendar
  )
    -> UNNotificationContent
  {
    let content = UNMutableNotificationContent()
    content.title = deadline.title
    let due = deadline.dueInstant(calendar: calendar)
    let when =
      deadline.time == nil
      ? due.formatted(date: .abbreviated, time: .omitted) : due.formatted(date: .abbreviated, time: .shortened)
    let dueText = String(localized: "Due \(when)", table: "Calendar")
    content.body = [courseCode, dueText].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    content.sound = .default
    return content
  }

  private func signingContent(_ kind: SigningReminder.Kind, expiresAt: Date) -> UNNotificationContent {
    let content = UNMutableNotificationContent()
    switch kind {
    case .twoDays: content.title = String(localized: "Kitbag stops opening in 2 days", table: "Settings")
    case .oneDay: content.title = String(localized: "Kitbag stops opening tomorrow", table: "Settings")
    case .today:
      let time = expiresAt.formatted(date: .omitted, time: .shortened)
      content.title = String(localized: "Kitbag stops opening today at \(time)", table: "Settings")
    }
    content.body = String(
      localized: "Connect your iPhone to your Mac and install Kitbag again to renew it.", table: "Settings")
    content.sound = .default
    return content
  }
}

/// Shows a notification as a banner even while Kitbag is open (iOS hides it otherwise).
final class KitbagNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
  static let shared = KitbagNotificationDelegate()

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list, .sound])
  }
}
