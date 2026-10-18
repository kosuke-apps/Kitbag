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
    reminders.schedule(deadline, courseCode: courseCode)
  }

  /// Adds or replaces many deadlines at once (an import) and schedules the reminders of the nearest ones. iOS keeps at
  /// most 64 pending notifications, so only the soonest few are scheduled.
  func importDeadlines(_ imported: [Deadline], courseCode: (UUID) -> String?) {
    for deadline in imported { book.upsert(deadline) }
    save()
    let now = Date()
    let soonest = imported.filter { !$0.isDone && $0.dueInstant(calendar: .current) >= now }
      .sorted { $0.dueInstant(calendar: .current) < $1.dueInstant(calendar: .current) }
      .prefix(40)
    for deadline in soonest { reminders.schedule(deadline, courseCode: deadline.courseID.flatMap(courseCode)) }
  }

  func setDone(id: UUID, _ done: Bool, courseCode: String?) {
    guard var deadline = book.deadlines.first(where: { $0.id == id }) else { return }
    deadline.isDone = done
    upsert(deadline, courseCode: courseCode)
  }

  func remove(id: UUID) {
    book.remove(id: id)
    save()
    reminders.cancel(id: id)
  }

  /// Schedules every reminder again, for example after the timetable changed a course's code.
  func rescheduleReminders(timetable: Timetable) {
    for deadline in book.deadlines {
      reminders.schedule(deadline, courseCode: deadline.courseID.flatMap { timetable.course(id: $0)?.code })
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
