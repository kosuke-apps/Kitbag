import KitbagCore
import UserNotifications

/// Schedules a deadline's reminder as a local notification. Local notifications need no server and no paid developer
/// account; they are shown by iOS at the time even when Kitbag is closed.
@MainActor
struct ReminderScheduler {
  private let center = UNUserNotificationCenter.current()

  /// Asks for permission the first time; true when notifications may be shown.
  func authorize() async -> Bool {
    switch await center.notificationSettings().authorizationStatus {
    case .authorized, .provisional, .ephemeral: return true
    case .notDetermined: return (try? await center.requestAuthorization(options: [.alert, .sound])) == true
    default: return false
    }
  }

  func cancel(id: UUID) {
    center.removePendingNotificationRequests(withIdentifiers: [id.uuidString])
  }

  /// Replaces the deadline's reminder: removes the old one, and adds a new one when it is still in the future.
  func schedule(_ deadline: Deadline, courseCode: String?, calendar: Calendar = .current) {
    cancel(id: deadline.id)
    guard !deadline.isDone, let fire = deadline.reminderDate(calendar: calendar), fire > Date() else { return }
    Task {
      guard await authorize() else { return }
      let content = UNMutableNotificationContent()
      content.title = deadline.title
      let due = deadline.dueInstant(calendar: calendar)
      let when =
        deadline.time == nil
        ? due.formatted(date: .abbreviated, time: .omitted) : due.formatted(date: .abbreviated, time: .shortened)
      let dueText = String(localized: "Due \(when)", table: "Calendar")
      content.body = [courseCode, dueText].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
      content.sound = .default
      let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
      let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
      try? await center.add(
        UNNotificationRequest(identifier: deadline.id.uuidString, content: content, trigger: trigger))
    }
  }
}
