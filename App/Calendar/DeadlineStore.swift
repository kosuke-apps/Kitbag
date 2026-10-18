import KitbagCore
import Observation
import SwiftUI

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
  private var syncing: Task<Void, Never>?
  /// The code of a course (`ME 101`), for a reminder's text; set once the timetable is loaded.
  var courseCode: (UUID) -> String? = { _ in nil }

  init(url: URL = AppFiles.url("deadlines.json")) {
    self.url = url
    var loaded = DeadlineBook()
    if let data = try? Data(contentsOf: url) {
      do {
        loaded = try DeadlineBook(fileData: data)
        if let normalized = try? loaded.fileData(), normalized != data { try? AppFiles.write(normalized, to: url) }
      } catch {
        AppFiles.setAside(url)
        setAsideUnreadableFile = true
      }
    }
    book = loaded
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
    let snapshot = book
    let lookup = courseCode
    let expiry = SigningStatus.expiresAt
    let reminders = reminders
    let previous = syncing
    syncing = Task {
      await previous?.value
      await reminders.sync(deadlines: snapshot, courseCode: lookup, signatureExpiry: expiry)
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
