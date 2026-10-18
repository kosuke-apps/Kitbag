import AppIntents
import KitbagCore
import WidgetKit

/// The tap on a deadline's circle in a widget. It runs in the widget's process: it marks the deadline done in the widget's
/// own copy of the data (so the list changes at once) and queues the change for the app (`WidgetActions`).
struct CompleteDeadlineIntent: AppIntent {
  static let title: LocalizedStringResource = "Complete deadline"
  static let isDiscoverable = false

  @Parameter(title: "Deadline") var deadlineID: String

  init() {}

  init(deadlineID: String) {
    self.deadlineID = deadlineID
  }

  func perform() async throws -> some IntentResult {
    if let url = AppGroup.url("deadlines.json"), let data = try? Data(contentsOf: url),
      var book = try? DeadlineBook(fileData: data), let id = UUID(uuidString: deadlineID),
      var deadline = book.deadlines.first(where: { $0.id == id })
    {
      deadline.isDone = true
      book.upsert(deadline)
      if let updated = try? book.fileData() { try? updated.write(to: url, options: .atomic) }
    }
    WidgetActions.record(.init(deadlineID: deadlineID, done: true, at: Date()))
    WidgetCenter.shared.reloadTimelines(ofKind: "dev.kosuke.kitbag.deadlines")
    return .result()
  }
}
