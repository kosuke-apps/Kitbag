import Foundation

/// What a widget asks the app to do the next time it runs. A widget cannot write the app's files, so a tap on a
/// deadline's circle is recorded here (the widget also changes its own copy so that the list updates at once) and the
/// app applies it when it is opened. The app's files stay the only source of truth.
enum WidgetActions {
  struct Action: Codable, Equatable {
    var deadlineID: String
    var done: Bool
    var at: Date
  }

  private static let fileName = "widget-actions.json"

  /// Adds an action to the queue.
  static func record(_ action: Action) {
    guard let url = AppGroup.url(fileName) else { return }
    var queue = read(url)
    queue.removeAll { $0.deadlineID == action.deadlineID }
    queue.append(action)
    write(queue, to: url)
  }

  /// Returns the queued actions, oldest first, and empties the queue.
  static func take() -> [Action] {
    guard let url = AppGroup.url(fileName) else { return [] }
    let queue = read(url)
    if !queue.isEmpty { try? FileManager.default.removeItem(at: url) }
    return queue.sorted { $0.at < $1.at }
  }

  private static func read(_ url: URL) -> [Action] {
    guard let data = try? Data(contentsOf: url) else { return [] }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return (try? decoder.decode([Action].self, from: data)) ?? []
  }

  private static func write(_ queue: [Action], to url: URL) {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    if let data = try? encoder.encode(queue) { try? data.write(to: url, options: .atomic) }
  }
}
