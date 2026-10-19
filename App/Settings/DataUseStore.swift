import KitbagCore
import Observation
import SwiftUI

/// The person's choices about data (`DataUseSettings`), what Kitbag has downloaded (`DataUsage`), and the one way Kitbag
/// downloads anything: `fetch`, which counts what a request cost on the wire. What to fetch and when is decided here
/// (`decide`), from the connection, the choices and what this month has used.
///
/// The choices are in UserDefaults like the other settings, so a backup carries them. The count belongs to this phone:
/// a backup leaves it out (`BackupManager`).
@MainActor
@Observable
final class DataUseStore {
  var settings: DataUseSettings {
    didSet { saveSettings() }
  }
  private(set) var usage: DataUsage

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let network: NetworkCondition
  static let settingsKey = "kitbag.dataUse.settings"
  static let usageKey = "kitbag.dataUse.usage"

  init(defaults: UserDefaults = .standard, network: NetworkCondition = .shared) {
    self.defaults = defaults
    self.network = network
    settings = Self.loadSettings(from: defaults)
    usage = Self.loadUsage(from: defaults)
    network.start()
  }

  /// Reads the choices again, after a backup was restored.
  func reload() {
    settings = Self.loadSettings(from: defaults)
  }

  private static func loadSettings(from defaults: UserDefaults) -> DataUseSettings {
    defaults.data(forKey: settingsKey).flatMap { try? JSONDecoder().decode(DataUseSettings.self, from: $0) }
      ?? DataUseSettings()
  }

  private static func loadUsage(from defaults: UserDefaults) -> DataUsage {
    defaults.data(forKey: usageKey).flatMap { try? JSONDecoder().decode(DataUsage.self, from: $0) } ?? DataUsage()
  }

  private func saveSettings() {
    if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: Self.settingsKey) }
  }

  private func saveUsage() {
    if let data = try? JSONEncoder().encode(usage) { defaults.set(data, forKey: Self.usageKey) }
  }

  // MARK: Deciding

  var connection: Connection { network.connection }

  /// Whether to fetch `source` now, by the choices for the connection the phone is on. `byRequest` is for what the person
  /// asked for.
  func decide(_ source: DataSource, byRequest: Bool, lastFetched: Date?, now: Date = Date()) -> FetchDecision {
    DataUsePolicy.decide(
      source, byRequest: byRequest, lastFetched: lastFetched, now: now, connection: connection, settings: settings,
      mobileBytesThisMonth: usage.mobileBytes(inMonthOf: now, calendar: .current))
  }

  /// How long a source is left alone between automatic updates on the connection now, or nil when they are not automatic.
  func interval(_ source: DataSource) -> TimeInterval? {
    let connection = connection
    return settings.choice(for: source, on: connection).interval(
      usual: DataUsePolicy.usualInterval(for: source), connection: connection,
      saveMobileData: settings.saveMobileData)
  }

  // MARK: Counting

  func record(_ source: DataSource, bytes: Int, metered: Bool, at date: Date = Date()) {
    usage.add(source, bytes: bytes, metered: metered, at: date, calendar: .current)
    saveUsage()
  }

  func reset() {
    usage.reset(at: Date())
    saveUsage()
  }

  /// Downloads a request and counts what it cost: the headers and the body as they crossed the network (compressed, as
  /// they were sent), not the size after they were unpacked. On "not on mobile data" the request also carries iOS's own
  /// refusal to use mobile data or Low Data Mode, so that it cannot slip out if the phone changes connection meanwhile.
  func fetch(_ request: URLRequest, source: DataSource, session: URLSession) async throws -> (Data, URLResponse) {
    var request = request
    let connection = connection
    let gate = settings.choice(for: source == .places ? .weather : source, on: .mobile)
    if gate == .notOnMobile {
      request.allowsCellularAccess = false
      request.allowsConstrainedNetworkAccess = false
      request.allowsExpensiveNetworkAccess = false
    }
    let meter = MeteringDelegate()
    do {
      let result = try await session.data(for: request, delegate: meter)
      record(source, bytes: meter.bytes ?? result.0.count, metered: connection.isMetered)
      return result
    } catch {
      // A request that failed half way still used what it used.
      if let bytes = meter.bytes, bytes > 0 { record(source, bytes: bytes, metered: connection.isMetered) }
      throw error
    }
  }
}

/// Adds up what a request cost on the wire, from the metrics the system collects for it.
final class MeteringDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  private let lock = NSLock()
  private var total: Int?

  var bytes: Int? { lock.withLock { total } }

  func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
    let sum = metrics.transactionMetrics.reduce(0) { partial, transaction in
      partial
        + Int(
          transaction.countOfRequestHeaderBytesSent + transaction.countOfRequestBodyBytesSent
            + transaction.countOfResponseHeaderBytesReceived + transaction.countOfResponseBodyBytesReceived)
    }
    lock.withLock { total = (total ?? 0) + sum }
  }
}
