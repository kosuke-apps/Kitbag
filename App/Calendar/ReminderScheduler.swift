import KitbagCore
import OSLog
import UserNotifications

private let log = Logger(subsystem: "dev.kosuke.kitbag", category: "reminders")

/// Keeps the phone's pending notifications in step with what Kitbag wants shown: the alerts of each open deadline and the
/// warnings that the signature is about to run out. They are local notifications, so they need no server and no paid
/// developer account, and iOS shows them at the time even when Kitbag is closed. A deadline's notification carries three
/// buttons (done, snooze, tomorrow) that work without opening Kitbag.
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
  private static let deadlinePrefix = "kitbag.deadline."
  /// A snoozed reminder, one per deadline (snoozing again replaces it).
  static let snoozePrefix = "kitbag.snooze."
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
    registerCategories()
    var wanted: [UNNotificationRequest] = []
    var used = 0
    let pending = await center.pendingNotificationRequests()

    // A snooze the person asked for stays while its deadline is open and reminders of it are on; it counts against the budget.
    let open = Set(
      deadlines.deadlines
        .filter { !$0.isDone && preferences.deadlinesEnabled && preferences.deadlineKinds.contains($0.kind) }
        .map(\.id))
    let snoozes = pending.map(\.identifier).filter { identifier in
      identifier.hasPrefix(Self.snoozePrefix)
        && UUID(uuidString: String(identifier.dropFirst(Self.snoozePrefix.count))).map(open.contains) == true
    }
    used += snoozes.count

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
      limit: max(0, min(Self.classLimit, Self.ownLimit - used)))
    for reminder in classes {
      wanted.append(
        request(
          id: reminder.id, fire: reminder.fireDate, calendar: calendar,
          content: classContent(reminder, lead: preferences.classLeadMinutes)))
    }
    used += classes.count

    for reminder in NotificationPlanner.deadlineReminders(
      deadlines, preferences: preferences, now: now, calendar: calendar, limit: max(0, Self.ownLimit - used))
    {
      wanted.append(
        request(
          id: reminder.id, fire: reminder.fireDate, calendar: calendar,
          content: deadlineContent(
            reminder, courseCode: reminder.deadline.courseID.flatMap(courseCode), preferences: preferences,
            calendar: calendar)))
    }

    let wantedIDs = Set(wanted.map(\.identifier)).union(snoozes)
    let ours = pending.map(\.identifier).filter {
      UUID(uuidString: $0) != nil  // a reminder made before deadlines could have several
        || $0.hasPrefix(Self.deadlinePrefix) || $0.hasPrefix(Self.snoozePrefix) || $0.hasPrefix(Self.signingPrefix)
        || $0.hasPrefix(Self.classPrefix)
    }
    center.removePendingNotificationRequests(withIdentifiers: ours.filter { !wantedIDs.contains($0) })
    guard !wanted.isEmpty, await authorize() else {
      await decorateGuestNotifications()
      return
    }
    for request in wanted { try? await center.add(request) }
    await decorateGuestNotifications()
  }

  // MARK: Notifications of the apps inside Kitbag

  /// Puts the icon of the app on the notifications that Headway scheduled before Kitbag could brand them on their way in
  /// (`GuestNotificationBranding`, which does the same for every new one). Headway's code, which Kitbag does not change,
  /// makes them with no picture; Kitbag finds the waiting ones by the `headway.` its identifiers start with and sets each
  /// one again with the same identifier, the same text and sound, and the same moment (a trigger of "in so many seconds" is
  /// worked out again from when it would have come), with Headway's icon attached and its name as the subtitle. One that is
  /// already done is left alone. If Headway changes how it names them, this quietly does nothing.
  func decorateGuestNotifications() async {
    let marker = GuestNotificationBranding.decoratedKey
    for request in await center.pendingNotificationRequests()
    where request.identifier.hasPrefix("headway.") && request.content.userInfo[marker] == nil {
      guard let content = request.content.mutableCopy() as? UNMutableNotificationContent,
        let icon = NotificationIcon.attachment(for: .headway)
      else { continue }
      content.attachments = [icon]
      if content.subtitle.isEmpty { content.subtitle = L10n.string(ModuleID.headway.title) }
      var info = content.userInfo
      info[marker] = true
      content.userInfo = info
      var trigger = request.trigger
      if let interval = trigger as? UNTimeIntervalNotificationTrigger, let next = interval.nextTriggerDate() {
        trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, next.timeIntervalSinceNow), repeats: false)
      }
      try? await center.add(UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger))
      let after = await center.pendingNotificationRequests().first { $0.identifier == request.identifier }
      log.info("decorated a guest notification, attachments now: \(after?.content.attachments.count ?? -1)")
    }
  }

  // MARK: Actions on a notification

  /// The buttons of a deadline's notification, in the language chosen for Kitbag. They are registered every time the
  /// reminders are planned, so that a change of language shows on the next notification.
  func registerCategories() {
    let done = UNNotificationAction(
      identifier: DeadlineAction.done.rawValue, title: L10n.string("Done", table: "Calendar"), options: [],
      icon: UNNotificationActionIcon(systemImageName: "checkmark.circle"))
    let tenMinutes = UNNotificationAction(
      identifier: DeadlineAction.snoozeTenMinutes.rawValue, title: L10n.string("Snooze 10 min", table: "Calendar"),
      options: [], icon: UNNotificationActionIcon(systemImageName: "zzz"))
    let hour = UNNotificationAction(
      identifier: DeadlineAction.snoozeHour.rawValue, title: L10n.string("Snooze 1 hour", table: "Calendar"),
      options: [], icon: UNNotificationActionIcon(systemImageName: "clock"))
    let tomorrow = UNNotificationAction(
      identifier: DeadlineAction.remindTomorrow.rawValue, title: L10n.string("Remind me tomorrow", table: "Calendar"),
      options: [], icon: UNNotificationActionIcon(systemImageName: "sunrise"))
    let category = UNNotificationCategory(
      identifier: Self.categoryID, actions: [done, tenMinutes, hour, tomorrow], intentIdentifiers: [],
      options: [.hiddenPreviewsShowTitle])
    center.setNotificationCategories([category])
  }

  static let categoryID = "kitbag.deadline"

  /// Puts a deadline's notification off: in ten minutes, in an hour, or tomorrow morning. The text is the same as the one
  /// that was snoozed. Snoozing again replaces the earlier snooze.
  func snooze(
    _ deadlineID: UUID, content original: UNNotificationContent, action: DeadlineAction, morning: TimeOfDay,
    now: Date = Date(), calendar: Calendar = .current
  ) async {
    guard let content = original.mutableCopy() as? UNMutableNotificationContent else { return }
    let trigger: UNNotificationTrigger
    switch action {
    case .snoozeTenMinutes: trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10 * 60, repeats: false)
    case .snoozeHour: trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60 * 60, repeats: false)
    case .remindTomorrow:
      guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
        let fire = calendar.date(
          bySettingHour: min(morning.hour, 23), minute: morning.minute, second: 0, of: tomorrow)
      else { return }
      trigger = UNCalendarNotificationTrigger(
        dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false)
    case .done: return
    }
    try? await center.add(
      UNNotificationRequest(identifier: Self.snoozePrefix + deadlineID.uuidString, content: content, trigger: trigger))
  }

  /// Takes a deadline's pending notifications away, for a deadline that was just done.
  func cancelAll(for deadlineID: UUID) async {
    let prefix = DeadlineReminder.idPrefix(for: deadlineID)
    let pending = await center.pendingNotificationRequests().map(\.identifier).filter {
      $0.hasPrefix(prefix) || $0 == Self.snoozePrefix + deadlineID.uuidString || $0 == deadlineID.uuidString
    }
    center.removePendingNotificationRequests(withIdentifiers: pending)
  }

  /// What is waiting on this phone to be shown, by what Kitbag scheduled and what the guests did (those only counted).
  func pendingSummary() async -> (kitbag: [PendingReminder], others: Int) {
    var mine: [PendingReminder] = []
    var others = 0
    for request in await center.pendingNotificationRequests() {
      let id = request.identifier
      let kind: PendingReminder.Kind
      if id.hasPrefix(Self.deadlinePrefix) || UUID(uuidString: id) != nil {
        kind = .deadline
      } else if id.hasPrefix(Self.snoozePrefix) {
        kind = .snoozed
      } else if id.hasPrefix(Self.classPrefix) {
        kind = .classStart
      } else if id.hasPrefix(Self.signingPrefix) {
        kind = .signature
      } else {
        others += 1
        continue
      }
      let date =
        (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
        ?? (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
      mine.append(
        PendingReminder(
          id: id, title: request.content.title, subtitle: request.content.subtitle, body: request.content.body,
          date: date, kind: kind))
    }
    return (mine.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }, others)
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
    _ reminder: DeadlineReminder, courseCode: String?, preferences: NotificationPreferences, calendar: Calendar
  )
    -> UNNotificationContent
  {
    let deadline = reminder.deadline
    let content = UNMutableNotificationContent()
    let due = deadline.dueInstant(calendar: calendar)
    let style = Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day().locale(LanguageStore.shared.locale)
    let when =
      deadline.time == nil
      ? due.formatted(style)
      : due.formatted(style.hour().minute())
    switch reminder.kind {
    case .alert:
      content.title = deadline.title
      let dueText = L10n.string("Due \(when)", table: "Calendar")
      let near = Self.nearness(of: deadline, from: reminder.fireDate, calendar: calendar)
      content.body = [dueText, near].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    case .followUp:
      content.title = L10n.string("Not done yet: \(deadline.title)", table: "Calendar")
      content.body = L10n.string("It was due \(when)", table: "Calendar")
    }
    content.subtitle = [L10n.string(deadline.kind.title), courseCode].compactMap { $0 }.filter { !$0.isEmpty }
      .joined(separator: " · ")
    content.sound = .default
    content.categoryIdentifier = Self.categoryID
    content.threadIdentifier = deadline.courseID?.uuidString ?? "kitbag.deadlines"
    content.attachments = [NotificationIcon.attachment(for: .calendar)].compactMap { $0 }
    content.userInfo = [
      "deadlineID": deadline.id.uuidString, "morning": preferences.allDayTime.minutes,
    ]
    return content
  }

  /// How near the deadline is when a reminder fires, in words ("in 2 hours", "tomorrow"), or nil when it is already past.
  /// With no time on the deadline it counts whole days.
  private static func nearness(of deadline: Deadline, from fire: Date, calendar: Calendar) -> String? {
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = LanguageStore.shared.locale
    formatter.unitsStyle = .full
    formatter.dateTimeStyle = .named
    if deadline.time == nil {
      let days = deadline.date.days(since: LocalDate(fire, calendar: calendar), calendar: calendar)
      return days < 0 ? nil : formatter.localizedString(from: DateComponents(day: days))
    }
    let due = deadline.dueInstant(calendar: calendar)
    guard due >= fire else { return nil }
    let minutes = Int(due.timeIntervalSince(fire) / 60)
    if minutes < 1 { return L10n.string("now", table: "Calendar") }
    return formatter.localizedString(for: due, relativeTo: fire)
  }

  private func classContent(_ reminder: ClassReminder, lead: Int) -> UNNotificationContent {
    let content = UNMutableNotificationContent()
    content.title = L10n.string("\(reminder.code) starts in \(lead) min", table: "Settings")
    let time = reminder.start.formattedInLanguage(date: .omitted, time: .shortened)
    content.body = [reminder.title, reminder.location, time].filter { !$0.isEmpty }.joined(separator: " · ")
    content.sound = .default
    content.attachments = [NotificationIcon.attachment(for: .timetable)].compactMap { $0 }
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

/// One notification that is waiting to be shown, for the list in Settings > Reminders.
struct PendingReminder: Identifiable {
  enum Kind { case deadline, snoozed, classStart, signature }
  let id: String
  let title: String
  let subtitle: String
  let body: String
  let date: Date?
  let kind: Kind
}

/// What a button on a deadline's notification does.
enum DeadlineAction: String {
  case done = "kitbag.action.done"
  case snoozeTenMinutes = "kitbag.action.snooze10"
  case snoozeHour = "kitbag.action.snooze60"
  case remindTomorrow = "kitbag.action.tomorrow"
}

/// Shows a notification as a banner even while Kitbag is open (iOS hides it otherwise), and carries out the buttons of a
/// deadline's notification. The buttons run without opening Kitbag in front: iOS starts it in the background just for that.
final class KitbagNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
  static let shared = KitbagNotificationDelegate()

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list, .sound])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let content = response.notification.request.content
    log.info("notification response: \(response.actionIdentifier, privacy: .public)")
    guard let action = DeadlineAction(rawValue: response.actionIdentifier),
      let id = (content.userInfo["deadlineID"] as? String).flatMap(UUID.init(uuidString:))
    else {
      completionHandler()
      return
    }
    let minutes = content.userInfo["morning"] as? Int ?? TimeOfDay.usualReminder.minutes
    nonisolated(unsafe) let finish = completionHandler
    nonisolated(unsafe) let kept = content
    Task { @MainActor in
      await DeadlineStore.perform(action, deadline: id, content: kept, morning: TimeOfDay(minutes: minutes))
      log.info("notification action finished: \(action.rawValue, privacy: .public)")
      finish()
    }
  }
}
