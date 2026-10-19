import KitbagCore
import Observation
import SwiftUI
import UserNotifications

/// The deadlines, kept in a JSON file in the app's Application Support folder, with their reminders.
@MainActor
@Observable
final class DeadlineStore {
  private(set) var book: DeadlineBook
  /// True when the saved file could not be read; it was set aside (not overwritten) and an empty list started.
  private(set) var setAsideUnreadableFile = false
  private(set) var saveFailed = false
  private let url: URL
  private let reminders = ReminderScheduler()
  /// The store the app is using, for a notification button that arrives while no screen is looking at it.
  private(set) static weak var live: DeadlineStore?
  private var syncing: Task<Void, Never>?
  /// The code of a course (`ME 101`), for a reminder's text; set once the timetable is loaded.
  var courseCode: (UUID) -> String? = { _ in nil }
  /// The terms and the person's reminder preferences, which decide what is scheduled; set once the stores are loaded.
  var library: () -> TimetableLibrary = { TimetableLibrary() }
  var preferences: () -> NotificationPreferences = { NotificationPreferences() }

  init(url: URL = AppFiles.url("deadlines.json")) {
    self.url = url
    (book, setAsideUnreadableFile) = Self.load(url: url)
    Self.live = self
  }

  /// Reads the file again, after a backup was restored over it.
  func reload() {
    (book, setAsideUnreadableFile) = Self.load(url: url)
    syncReminders()
  }

  private static func load(url: URL) -> (DeadlineBook, Bool) {
    var loaded = DeadlineBook()
    var setAside = false
    if let data = try? Data(contentsOf: url) {
      do {
        loaded = try DeadlineBook(fileData: data)
        if let normalized = try? loaded.fileData(), normalized != data { try? AppFiles.write(normalized, to: url) }
      } catch {
        AppFiles.setAside(url)
        setAside = true
      }
    }
    return (loaded, setAside)
  }

  /// Adds a deadline, or replaces the one with the same id, and schedules its reminder.
  func upsert(_ deadline: Deadline, courseCode: String?) {
    book.upsert(deadline)
    save()
    syncReminders()
  }

  /// Adds or replaces many deadlines at once (an import).
  func importDeadlines(_ imported: [Deadline], courseCode: (UUID) -> String?) {
    for deadline in imported { book.upsert(deadline) }
    save()
    syncReminders()
  }

  /// Applies what widgets queued since the app last ran (a tap on a deadline's circle), then forgets it.
  func applyWidgetActions() {
    let actions = WidgetActions.take()
    guard !actions.isEmpty else { return }
    for action in actions {
      guard let id = UUID(uuidString: action.deadlineID), var deadline = book.deadlines.first(where: { $0.id == id })
      else { continue }
      deadline.isDone = action.done
      book.upsert(deadline)
    }
    save()
    syncReminders()
  }

  func setDone(id: UUID, _ done: Bool, courseCode: String?) {
    guard var deadline = book.deadlines.first(where: { $0.id == id }) else { return }
    deadline.isDone = done
    upsert(deadline, courseCode: courseCode)
  }

  func remove(id: UUID) {
    book.remove(id: id)
    save()
    syncReminders()
  }

  /// Makes the phone's pending notifications match the deadlines (and the signature's warnings) as they are now. Called
  /// after every change and whenever Kitbag opens, so that a reinstall or a changed course code cannot leave them stale.
  /// One run follows another, so that two changes in a row do not interleave.
  func syncReminders() {
    startSync()
  }

  /// The same, and waits until the phone's notifications have been brought up to date.
  func syncRemindersAndWait() async {
    await startSync().value
  }

  @discardableResult
  private func startSync() -> Task<Void, Never> {
    let snapshot = book
    let lookup = courseCode
    let terms = library()
    let chosen = preferences()
    let expiry = SigningStatus.expiresAt
    let reminders = reminders
    let previous = syncing
    let task = Task {
      await previous?.value
      await reminders.sync(
        deadlines: snapshot, library: terms, preferences: chosen, courseCode: lookup, signatureExpiry: expiry)
    }
    syncing = task
    return task
  }

  /// Puts the icon of Headway on the notifications it has scheduled (see `ReminderScheduler.decorateGuestNotifications`).
  func decorateGuestNotifications() async {
    await reminders.decorateGuestNotifications()
  }

  // MARK: Buttons on a notification

  /// Carries out a button of a deadline's notification. Kitbag may have been started just for this, with no screen yet, so
  /// the stores are the ones the app made at launch, and the work is finished before iOS is told it is over.
  static func perform(
    _ action: DeadlineAction, deadline id: UUID, content: UNNotificationContent, morning: TimeOfDay
  ) async {
    let store = live ?? DeadlineStore()
    switch action {
    case .done:
      guard store.book.deadlines.contains(where: { $0.id == id }) else { return }
      store.setDone(id: id, true, courseCode: nil)
      await store.syncRemindersAndWait()
      await store.reminders.cancelAll(for: id)
      WidgetBridge.syncFromSavedTheme()
    case .snoozeTenMinutes, .snoozeHour, .remindTomorrow:
      await store.reminders.snooze(id, content: content, action: action, morning: morning)
    }
  }

  func dismissNotices() {
    setAsideUnreadableFile = false
    saveFailed = false
  }

  private func save() {
    do {
      try AppFiles.write(try book.fileData(), to: url)
      saveFailed = false
    } catch {
      saveFailed = true
    }
  }
}
