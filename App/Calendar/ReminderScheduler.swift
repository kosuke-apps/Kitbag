import KitbagCore
import UserNotifications

/// Keeps the phone's pending notifications in step with what Kitbag wants shown: a reminder for each open deadline and
/// the warnings that the signature is about to run out. They are local notifications, so they need no server and no paid
/// developer account, and iOS shows them at the time even when Kitbag is closed.
@MainActor
struct ReminderScheduler {
  /// iOS keeps at most 64 pending notifications per app, and the guests' own (Headway's departure reminders) count too, so
  /// Kitbag keeps to part of them: the signature's three, up to `classLimit` for classes, and what is left of
  /// `ownLimit` for deadlines. The soonest of each kind come first, and the rest are scheduled as time passes (the app
  /// plans again whenever it runs).
  static let ownLimit = 54
  static let classLimit = 28
  static let horizonDays = 7

  private static let signingPrefix = "kitbag.signing."
  private static let classPrefix = "kitbag.class."
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

  /// Makes the pending notifications match what is wanted now (the deadlines, the classes, the signature, all by the
  /// person's preferences): reminders that are no longer wanted are removed, the others are added again (an existing
  /// request with the same id is replaced). Only notifications that Kitbag made are touched; a guest's own are left alone.
  func sync(
    deadlines: DeadlineBook, library: TimetableLibrary, preferences: NotificationPreferences,
    courseCode: (UUID) -> String?, signatureExpiry: Date?, now: Date = Date(), calendar: Calendar = .current
  ) async {
    var wanted: [UNNotificationRequest] = []
    var used = 0

    if preferences.signatureEnabled, let signatureExpiry {
      for reminder in SigningReminder.plan(expiresAt: signatureExpiry, now: now, calendar: calendar) {
        wanted.append(
          request(
            id: Self.signingPrefix + reminder.kind.rawValue, fire: reminder.fireDate, calendar: calendar,
            content: signingContent(reminder.kind, expiresAt: signatureExpiry)))
        used += 1
      }
    }

    let horizon =
      signatureExpiry.map { min(Self.horizonDays, max(1, Int($0.timeIntervalSince(now) / 86400) + 1)) }
      ?? Self.horizonDays
    let classes = NotificationPlanner.classReminders(
      library, preferences: preferences, now: now, calendar: calendar, horizonDays: horizon,
      limit: min(Self.classLimit, Self.ownLimit - used))
    for reminder in classes {
      wanted.append(
        request(
          id: reminder.id, fire: reminder.fireDate, calendar: calendar,
          content: classContent(reminder, lead: preferences.classLeadMinutes)))
    }
    used += classes.count

    for (deadline, fire) in NotificationPlanner.deadlineReminders(
      deadlines, preferences: preferences, now: now, calendar: calendar, limit: max(0, Self.ownLimit - used))
    {
      wanted.append(
        request(
          id: deadline.id.uuidString, fire: fire, calendar: calendar,
          content: deadlineContent(deadline, courseCode: deadline.courseID.flatMap(courseCode), calendar: calendar)))
    }

    let wantedIDs = Set(wanted.map(\.identifier))
    let ours = await center.pendingNotificationRequests().map(\.identifier).filter {
      UUID(uuidString: $0) != nil || $0.hasPrefix(Self.signingPrefix) || $0.hasPrefix(Self.classPrefix)
    }
    center.removePendingNotificationRequests(withIdentifiers: ours.filter { !wantedIDs.contains($0) })
    guard !wanted.isEmpty, await authorize() else { return }
    for request in wanted { try? await center.add(request) }
  }

  /// A notification in five seconds, to see that they arrive. False when they are not allowed.
  func sendTest() async -> Bool {
    guard await authorize() else { return false }
    let content = UNMutableNotificationContent()
    content.title = L10n.string("Notifications are working", table: "Settings")
    content.body = L10n.string("Kitbag can remind you of deadlines on this iPhone.", table: "Settings")
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
      ? due.formattedInLanguage(date: .abbreviated, time: .omitted)
      : due.formattedInLanguage(date: .abbreviated, time: .shortened)
    let dueText = L10n.string("Due \(when)", table: "Calendar")
    content.body = [courseCode, dueText].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    content.sound = .default
    return content
  }

  private func classContent(_ reminder: ClassReminder, lead: Int) -> UNNotificationContent {
    let content = UNMutableNotificationContent()
    content.title = L10n.string("\(reminder.code) starts in \(lead) min", table: "Settings")
    let time = reminder.start.formattedInLanguage(date: .omitted, time: .shortened)
    content.body = [reminder.title, reminder.location, time].filter { !$0.isEmpty }.joined(separator: " · ")
    content.sound = .default
    return content
  }

  private func signingContent(_ kind: SigningReminder.Kind, expiresAt: Date) -> UNNotificationContent {
    let content = UNMutableNotificationContent()
    switch kind {
    case .twoDays: content.title = L10n.string("Kitbag stops opening in 2 days", table: "Settings")
    case .oneDay: content.title = L10n.string("Kitbag stops opening tomorrow", table: "Settings")
    case .today:
      let time = expiresAt.formattedInLanguage(date: .omitted, time: .shortened)
      content.title = L10n.string("Kitbag stops opening today at \(time)", table: "Settings")
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
