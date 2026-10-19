import Foundation

/// What Kitbag downloads for itself, by purpose. (The apps inside Kitbag keep their own counts.)
public enum DataSource: String, CaseIterable, Codable, Sendable {
  /// The weather forecast.
  case weather
  /// Searching for a place by name.
  case places
  /// The calendars subscribed to by their address.
  case calendars
}

/// The kind of connection the phone is on, as far as the cost of data goes.
public enum Connection: String, Codable, Sendable {
  /// Wi-Fi or a wire: data is free.
  case wifi
  /// Mobile data, or a personal hotspot (what iOS calls an "expensive" path).
  case mobile
  /// Low Data Mode is on, on any connection ("constrained"): the person asked apps to use less.
  case lowData

  /// Whether the data counts against a plan.
  public var isMetered: Bool { self != .wifi }
}

/// How often something is brought up to date on one kind of connection.
public enum RefreshChoice: String, CaseIterable, Codable, Sendable {
  /// The usual rhythm, which is slower on mobile data (see `DataUseSettings.saveMobileData`).
  case automatic
  case every15Minutes
  case every30Minutes
  case everyHour
  case every3Hours
  case every6Hours
  /// Only when the person asks (pulling a screen down, a refresh button).
  case manual
  /// Never on this kind of connection, not even when asked. Only offered for mobile data.
  case notOnMobile

  /// The seconds to wait between automatic updates, or nil when they are not automatic. `usual` is the rhythm of
  /// `automatic` on Wi-Fi. On mobile data and in Low Data Mode `automatic` waits twice and four times as long when
  /// the person chose to save mobile data.
  public func interval(usual: TimeInterval, connection: Connection, saveMobileData: Bool) -> TimeInterval? {
    switch self {
    case .automatic:
      guard saveMobileData else { return usual }
      switch connection {
      case .wifi: return usual
      case .mobile: return usual * 2
      case .lowData: return usual * 4
      }
    case .every15Minutes: return 15 * 60
    case .every30Minutes: return 30 * 60
    case .everyHour: return 60 * 60
    case .every3Hours: return 3 * 3600
    case .every6Hours: return 6 * 3600
    case .manual, .notOnMobile: return nil
    }
  }
}

/// The person's choices about data.
public struct DataUseSettings: Codable, Equatable, Sendable {
  /// Update less often on mobile data (twice as slowly) and in Low Data Mode (four times), where a rhythm is Automatic.
  public var saveMobileData = true
  public var weatherOnWiFi = RefreshChoice.automatic
  public var weatherOnMobile = RefreshChoice.automatic
  public var calendarsOnWiFi = RefreshChoice.automatic
  public var calendarsOnMobile = RefreshChoice.automatic
  /// Bytes of mobile data Kitbag may use in a month before it stops updating by itself; nil for no limit.
  public var monthlyMobileLimit: Int?

  public init() {}

  /// The limits offered, in bytes.
  public static let limitChoices = [5, 10, 25, 50, 100].map { $0 * 1_000_000 }

  /// The rhythm chosen for a source on a kind of connection. A search for a place is only ever asked for, so it is manual.
  public func choice(for source: DataSource, on connection: Connection) -> RefreshChoice {
    switch (source, connection.isMetered) {
    case (.weather, false): weatherOnWiFi
    case (.weather, true): weatherOnMobile
    case (.calendars, false): calendarsOnWiFi
    case (.calendars, true): calendarsOnMobile
    case (.places, _): .manual
    }
  }

  private enum CodingKeys: String, CodingKey {
    case saveMobileData, weatherOnWiFi, weatherOnMobile, calendarsOnWiFi, calendarsOnMobile, monthlyMobileLimit
  }

  /// A settings file from an earlier version lacks the newer choices; each falls back to its default.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = DataUseSettings()
    saveMobileData = try container.decodeIfPresent(Bool.self, forKey: .saveMobileData) ?? defaults.saveMobileData
    weatherOnWiFi = try container.decodeIfPresent(RefreshChoice.self, forKey: .weatherOnWiFi) ?? defaults.weatherOnWiFi
    weatherOnMobile =
      try container.decodeIfPresent(RefreshChoice.self, forKey: .weatherOnMobile) ?? defaults.weatherOnMobile
    calendarsOnWiFi =
      try container.decodeIfPresent(RefreshChoice.self, forKey: .calendarsOnWiFi) ?? defaults.calendarsOnWiFi
    calendarsOnMobile =
      try container.decodeIfPresent(RefreshChoice.self, forKey: .calendarsOnMobile) ?? defaults.calendarsOnMobile
    monthlyMobileLimit = try container.decodeIfPresent(Int.self, forKey: .monthlyMobileLimit)
  }
}

/// Why something was not fetched.
public enum FetchBlock: Equatable, Sendable {
  /// The rhythm for this connection is "only when I ask" and nobody asked.
  case manualOnly
  /// This connection is mobile data and the choice is "not on mobile data".
  case notOnMobile
  /// Mobile data used this month has reached the limit.
  case monthlyLimit
}

public enum FetchDecision: Equatable, Sendable {
  case fetch
  /// Fetched recently enough for the rhythm.
  case tooSoon
  case blocked(FetchBlock)
}

public enum DataUsePolicy {
  /// How long a source is left alone between automatic updates on Wi-Fi.
  public static func usualInterval(for source: DataSource) -> TimeInterval {
    switch source {
    case .weather: 15 * 60
    case .calendars: 60 * 60
    case .places: 0
    }
  }

  /// Whether to fetch now. `byRequest` is true when the person asked (a pull to refresh, a button, a new place or calendar),
  /// which skips the rhythm and the monthly limit but not "not on mobile data".
  public static func decide(
    _ source: DataSource, byRequest: Bool, lastFetched: Date?, now: Date, connection: Connection,
    settings: DataUseSettings, mobileBytesThisMonth: Int
  ) -> FetchDecision {
    let choice = settings.choice(for: source, on: connection)
    // "Not on mobile data" applies to a search for a place as it does to the weather itself.
    let gate = source == .places ? settings.choice(for: .weather, on: connection) : choice
    if connection.isMetered, gate == .notOnMobile { return .blocked(.notOnMobile) }
    if byRequest { return .fetch }
    if connection.isMetered, let limit = settings.monthlyMobileLimit, mobileBytesThisMonth >= limit {
      return .blocked(.monthlyLimit)
    }
    guard
      choice != .notOnMobile,
      let interval = choice.interval(
        usual: usualInterval(for: source), connection: connection, saveMobileData: settings.saveMobileData)
    else { return .blocked(.manualOnly) }
    guard let lastFetched else { return .fetch }
    return now.timeIntervalSince(lastFetched) >= interval ? .fetch : .tooSoon
  }
}

/// Bytes downloaded and requests made, split by connection, kept by month so that "this month" and a monthly limit mean
/// something. Counted by the app from what the network reports, so iOS Settings (Cellular) may show a little more.
public struct DataUsage: Codable, Equatable, Sendable {
  public struct Tally: Codable, Equatable, Sendable {
    public var wifi = 0
    public var mobile = 0
    public var requests = 0
    public init() {}

    public var total: Int { wifi + mobile }

    mutating func add(bytes: Int, metered: Bool) {
      if metered { mobile += bytes } else { wifi += bytes }
      requests += 1
    }

    static func + (lhs: Tally, rhs: Tally) -> Tally {
      var sum = Tally()
      sum.wifi = lhs.wifi + rhs.wifi
      sum.mobile = lhs.mobile + rhs.mobile
      sum.requests = lhs.requests + rhs.requests
      return sum
    }
  }

  /// When counting began (or began again after a reset).
  public var since: Date
  /// Month (`2026-10`) to source to what it used. Only the last `monthsKept` months are kept.
  private var months: [String: [String: Tally]] = [:]
  public static let monthsKept = 13

  public init(since: Date = Date()) { self.since = since }

  public static func monthKey(_ date: Date, calendar: Calendar) -> String {
    let parts = calendar.dateComponents([.year, .month], from: date)
    return String(format: "%04d-%02d", parts.year ?? 1970, parts.month ?? 1)
  }

  public mutating func add(_ source: DataSource, bytes: Int, metered: Bool, at date: Date, calendar: Calendar) {
    guard bytes >= 0 else { return }
    let key = Self.monthKey(date, calendar: calendar)
    months[key, default: [:]][source.rawValue, default: Tally()].add(bytes: bytes, metered: metered)
    if months.count > Self.monthsKept {
      for old in months.keys.sorted().dropLast(Self.monthsKept) { months[old] = nil }
    }
  }

  /// What one source used in the month `date` falls in.
  public func tally(_ source: DataSource, inMonthOf date: Date, calendar: Calendar) -> Tally {
    months[Self.monthKey(date, calendar: calendar)]?[source.rawValue] ?? Tally()
  }

  /// What every source used in that month.
  public func tally(inMonthOf date: Date, calendar: Calendar) -> Tally {
    (months[Self.monthKey(date, calendar: calendar)] ?? [:]).values.reduce(Tally(), +)
  }

  /// Everything since counting began.
  public func tally(_ source: DataSource) -> Tally {
    months.values.compactMap { $0[source.rawValue] }.reduce(Tally(), +)
  }

  public func tally() -> Tally { DataSource.allCases.map { tally($0) }.reduce(Tally(), +) }

  /// The mobile data used in the month `date` falls in, which a monthly limit is measured against.
  public func mobileBytes(inMonthOf date: Date, calendar: Calendar) -> Int {
    tally(inMonthOf: date, calendar: calendar).mobile
  }

  /// The average size of one request of a source, or nil before any.
  public func averageRequest(_ source: DataSource) -> Int? {
    let all = tally(source)
    return all.requests == 0 ? nil : all.total / all.requests
  }

  public mutating func reset(at date: Date) {
    self = DataUsage(since: date)
  }
}
