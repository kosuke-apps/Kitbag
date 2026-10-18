import KitbagCore
import Observation
import SwiftUI

/// A calendar the person subscribes to by its address (a Canvas calendar feed, a Google Calendar "secret address").
/// The address is a secret, so it lives in the keychain, not in the file.
struct CalendarSubscription: Codable, Identifiable, Hashable {
  var id = UUID()
  var name: String
  /// Whether its coming events are listed on the Today screen.
  var showsOnToday = true
  var lastFetched: Date?
  var lastError: String?
  var eventCount = 0
}

enum SubscriptionError: Error {
  case notACalendarAddress
  case server(Int)
  case network(String)
  case noEvents
  /// The address could not be stored in, or found in, the keychain.
  case keychain
}

/// The subscriptions and the events fetched from them, kept in files in Application Support.
@MainActor
@Observable
final class SubscriptionStore {
  private(set) var subscriptions: [CalendarSubscription]
  private(set) var events: [UUID: [CalendarEvent]]
  private(set) var refreshing: Set<UUID> = []

  private let metaURL = AppFiles.url("subscriptions.json")
  private let eventsURL = AppFiles.url("subscription-events.json")
  private let session: URLSession

  /// How old a calendar may be before it is fetched again.
  private let freshFor: TimeInterval = 60 * 60

  /// A session that keeps nothing on disk: a feed's address is a secret and so are its events, and a refresh must ask
  /// the server rather than reuse an answer it was given earlier.
  nonisolated static func makeSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    configuration.timeoutIntervalForRequest = 30
    return URLSession(configuration: configuration)
  }

  init(session: URLSession = SubscriptionStore.makeSession()) {
    self.session = session
    subscriptions =
      (try? Data(contentsOf: AppFiles.url("subscriptions.json")))
      .flatMap { try? JSONDecoder().decode([CalendarSubscription].self, from: $0) } ?? []
    events =
      (try? Data(contentsOf: AppFiles.url("subscription-events.json")))
      .flatMap { try? JSONDecoder().decode([UUID: [CalendarEvent]].self, from: $0) } ?? [:]
  }

  // MARK: Subscriptions

  func name(of id: UUID) -> String { subscriptions.first { $0.id == id }?.name ?? "" }

  /// Adds a calendar and fetches it at once, so that a wrong address is reported now.
  func add(name: String, address: String) async throws {
    guard let url = Self.url(from: address) else { throw SubscriptionError.notACalendarAddress }
    let fetched = try await fetch(url)
    guard !fetched.isEmpty else { throw SubscriptionError.noEvents }
    var subscription = CalendarSubscription(name: name.trimmingCharacters(in: .whitespaces))
    if subscription.name.isEmpty { subscription.name = url.host ?? "Calendar" }
    subscription.lastFetched = Date()
    subscription.eventCount = fetched.count
    guard Keychain.set(url.absoluteString, for: subscription.id.uuidString) else { throw SubscriptionError.keychain }
    subscriptions.append(subscription)
    events[subscription.id] = fetched
    save()
  }

  func remove(id: UUID) {
    Keychain.delete(id.uuidString)
    subscriptions.removeAll { $0.id == id }
    events[id] = nil
    save()
  }

  func setShowsOnToday(_ id: UUID, _ shows: Bool) {
    guard let index = subscriptions.firstIndex(where: { $0.id == id }) else { return }
    subscriptions[index].showsOnToday = shows
    save()
  }

  // MARK: Fetching

  func refresh(_ id: UUID) async {
    guard subscriptions.contains(where: { $0.id == id }) else { return }
    guard let address = Keychain.get(id.uuidString), let url = URL(string: address) else {
      markFailed(id, SubscriptionError.keychain)
      return
    }
    refreshing.insert(id)
    defer { refreshing.remove(id) }
    do {
      let fetched = try await fetch(url)
      events[id] = fetched
      if let current = subscriptions.firstIndex(where: { $0.id == id }) {
        subscriptions[current].lastFetched = Date()
        subscriptions[current].lastError = nil
        subscriptions[current].eventCount = fetched.count
      }
    } catch {
      markFailed(id, error)
      return
    }
    save()
  }

  private func markFailed(_ id: UUID, _ error: Error) {
    guard let index = subscriptions.firstIndex(where: { $0.id == id }) else { return }
    subscriptions[index].lastError = Self.describe(error)
    save()
  }

  /// Fetches the calendars that have not been fetched for a while.
  func refreshStale() async {
    for subscription in subscriptions
    where subscription.lastFetched.map({ Date().timeIntervalSince($0) > freshFor }) ?? true {
      await refresh(subscription.id)
    }
  }

  private func fetch(_ url: URL) async throws -> [CalendarEvent] {
    do {
      let (data, response) = try await session.data(from: url)
      if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
        throw SubscriptionError.server(http.statusCode)
      }
      let text = String(decoding: data, as: UTF8.self)
      guard text.contains("BEGIN:VCALENDAR") else { throw SubscriptionError.notACalendarAddress }
      return ICalendar.parse(text, defaultTimeZone: .current)
    } catch let error as SubscriptionError {
      throw error
    } catch {
      throw SubscriptionError.network(error.localizedDescription)
    }
  }

  /// `webcal://…` is `https://…` under another name.
  static func url(from address: String) -> URL? {
    var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.lowercased().hasPrefix("webcal://") { text = "https://" + text.dropFirst("webcal://".count) }
    guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
      url.host != nil
    else { return nil }
    return url
  }

  static func describe(_ error: Error) -> String {
    switch error as? SubscriptionError {
    case .notACalendarAddress: String(localized: "That is not a calendar address.", table: "Calendar")
    case .server(let code): String(localized: "The server answered \(code).", table: "Calendar")
    case .network(let message): message
    case .noEvents: String(localized: "There are no events in that calendar.", table: "Calendar")
    case .keychain: String(localized: "The address could not be read from the keychain.", table: "Calendar")
    case nil: error.localizedDescription
    }
  }

  // MARK: Reading

  /// The occurrences of every subscribed calendar that start within `window`, earliest first.
  func occurrences(
    in window: DateInterval, calendar: Calendar
  ) -> [(subscription: CalendarSubscription, event: CalendarEvent, occurrence: CalendarEvent.Occurrence)] {
    var result: [(CalendarSubscription, CalendarEvent, CalendarEvent.Occurrence)] = []
    for subscription in subscriptions {
      for event in events[subscription.id] ?? [] {
        for occurrence in event.occurrences(in: window, calendar: calendar) {
          result.append((subscription, event, occurrence))
        }
      }
    }
    return result.sorted { $0.2.start < $1.2.start }.map { (subscription: $0.0, event: $0.1, occurrence: $0.2) }
  }

  func occurrences(
    on day: LocalDate, calendar: Calendar
  ) -> [(subscription: CalendarSubscription, event: CalendarEvent, occurrence: CalendarEvent.Occurrence)] {
    let start = day.date(calendar: calendar)
    let end = day.adding(days: 1, calendar: calendar).date(calendar: calendar)
    // All-day events are stored at midnight UTC, so widen the window by a day on each side and filter by their own day.
    let wide = DateInterval(start: start.addingTimeInterval(-86400), end: end.addingTimeInterval(86400))
    return occurrences(in: wide, calendar: calendar).filter {
      $0.event.day(of: $0.occurrence.start, calendar: calendar) == day
    }
  }

  /// How many occurrences fall on each day of a stretch, for the dots on the month page.
  func counts(from first: LocalDate, to last: LocalDate, calendar: Calendar) -> [LocalDate: Int] {
    let window = DateInterval(
      start: first.date(calendar: calendar).addingTimeInterval(-86400),
      end: last.adding(days: 1, calendar: calendar).date(calendar: calendar).addingTimeInterval(86400))
    var counts: [LocalDate: Int] = [:]
    for item in occurrences(in: window, calendar: calendar) {
      let day = item.event.day(of: item.occurrence.start, calendar: calendar)
      if day >= first && day <= last { counts[day, default: 0] += 1 }
    }
    return counts
  }

  // MARK: Files

  private func save() {
    if let data = try? JSONEncoder().encode(subscriptions) { try? AppFiles.write(data, to: metaURL) }
    if let data = try? JSONEncoder().encode(events) { try? AppFiles.write(data, to: eventsURL) }
  }
}
