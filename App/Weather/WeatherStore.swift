import CoreLocation
import KitbagCore
import Observation
import SwiftUI

/// The weather for one place, fetched from Open-Meteo and kept in a file so that the last forecast shows at once.
@MainActor
@Observable
final class WeatherStore {
  enum Phase: Equatable {
    case idle
    case loading
    case failed
  }

  private(set) var forecast: Forecast?
  private(set) var phase: Phase = .idle
  /// The place that was chosen (or found from the phone's location); nil until one is.
  private(set) var place: Place?
  /// True when the place follows the phone's location rather than a place that was chosen.
  private(set) var followsLocation: Bool
  /// Set when the phone's location could not be used (access off, or no fix).
  private(set) var locationFailed = false

  private let cacheURL = AppFiles.url("weather-v3.json")
  private let defaults: UserDefaults
  private let location = LocationProvider()
  private let session: URLSession
  private let dataUse: DataUseStore

  /// Why the forecast was not brought up to date by itself, when the choices about data kept it from being (shown on the
  /// weather screen, with how to update it anyway).
  private(set) var blocked: FetchBlock?
  /// The same for a search for a place.
  private(set) var searchBlocked: FetchBlock?

  /// The shortest a forecast is called fresh, whatever the rhythm.
  private let freshFor: TimeInterval = 15 * 60

  /// A session that keeps nothing on disk and always asks the server: a forecast must not come from an old answer.
  nonisolated static func makeSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    configuration.timeoutIntervalForRequest = 20
    return URLSession(configuration: configuration)
  }

  init(dataUse: DataUseStore, defaults: UserDefaults = .standard, session: URLSession = WeatherStore.makeSession()) {
    self.defaults = defaults
    self.session = session
    self.dataUse = dataUse
    let saved = defaults.data(forKey: "weather.place").flatMap { try? JSONDecoder().decode(Place.self, from: $0) }
    let cached = (try? Data(contentsOf: cacheURL)).flatMap { try? JSONDecoder().decode(Forecast.self, from: $0) }
    // The first versions started with a fixed place and kept the last forecast: a phone that never chose a place keeps showing
    // the place of that forecast, instead of asking.
    place = saved ?? cached?.place
    followsLocation = defaults.bool(forKey: "weather.followsLocation")
    if let cached, cached.place == place { forecast = cached }
  }

  // MARK: Fetching

  /// Fetches the forecast when the choices about data say it is time (see `DataUsePolicy`), or when asked (`force`: pulling
  /// the screen down, a button, a new place). A failure keeps the old forecast.
  func refresh(force: Bool = false) async {
    if followsLocation && (force || forecast == nil) { await updateLocation() }
    guard let place else { return }
    let last = forecast.flatMap { $0.place == place ? $0.fetchedAt : nil }
    switch dataUse.decide(.weather, byRequest: force, lastFetched: last) {
    case .tooSoon:
      return
    case .blocked(let reason):
      blocked = reason
      return
    case .fetch:
      blocked = nil
    }
    guard phase != .loading else { return }
    phase = .loading
    do {
      let (data, _) = try await dataUse.fetch(
        URLRequest(url: OpenMeteo.forecastURL(for: place)), source: .weather, session: session)
      let fetched = try OpenMeteo.decodeForecast(data, place: place, fetchedAt: Date())
      forecast = fetched
      phase = .idle
      if let encoded = try? JSONEncoder().encode(fetched) { try? AppFiles.write(encoded, to: cacheURL) }
    } catch {
      phase = .failed
    }
  }

  /// The age of the forecast, for "Updated" text: old by the rhythm of the connection now (never, when updates are manual).
  var isStale: Bool {
    guard let forecast else { return true }
    let limit = max(dataUse.interval(.weather) ?? .infinity, freshFor)
    return Date().timeIntervalSince(forecast.fetchedAt) > limit
  }

  // MARK: Places

  func choose(_ chosen: Place) async {
    place = chosen
    followsLocation = false
    locationFailed = false
    forecast = nil
    persist()
    await refresh(force: true)
  }

  func followLocation() async {
    followsLocation = true
    persist()
    await refresh(force: true)
  }

  private func updateLocation() async {
    do {
      let found = try await location.currentPlace()
      locationFailed = false
      if found != place {
        place = found
        forecast = nil
        persist()
      }
    } catch {
      locationFailed = true
    }
  }

  func search(_ query: String) async -> [Place] {
    let language = Locale.current.language.languageCode?.identifier ?? "en"
    if case .blocked(let reason) = dataUse.decide(.places, byRequest: true, lastFetched: nil) {
      searchBlocked = reason
      return []
    }
    searchBlocked = nil
    guard let url = OpenMeteo.searchURL(query: query, language: language),
      let (data, _) = try? await dataUse.fetch(URLRequest(url: url), source: .places, session: session)
    else { return [] }
    return (try? OpenMeteo.decodePlaces(data)) ?? []
  }

  private func persist() {
    if let place, let data = try? JSONEncoder().encode(place) { defaults.set(data, forKey: "weather.place") }
    defaults.set(followsLocation, forKey: "weather.followsLocation")
  }
}

enum LocationError: Error {
  case denied
  case noFix
}

/// The phone's location as a `Place`, asked for once, with the place's name from reverse geocoding.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
  private let manager = CLLocationManager()
  private var authorization: CheckedContinuation<Void, Never>?
  private var fix: CheckedContinuation<CLLocation, Error>?

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyKilometer
  }

  func currentPlace() async throws -> Place {
    if manager.authorizationStatus == .notDetermined {
      manager.requestWhenInUseAuthorization()
      await withCheckedContinuation { authorization = $0 }
    }
    guard manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways else {
      throw LocationError.denied
    }
    let location = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CLLocation, Error>) in
      fix = continuation
      manager.requestLocation()
    }
    let marks = try? await CLGeocoder().reverseGeocodeLocation(location)
    let mark = marks?.first
    let name = mark?.locality ?? mark?.name ?? L10n.string("Current location", table: "Weather")
    let detail = [mark?.administrativeArea, mark?.country].compactMap { $0 }.joined(separator: ", ")
    return Place(
      name: name, detail: detail, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
  }

  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    Task { @MainActor in
      if manager.authorizationStatus != .notDetermined {
        authorization?.resume()
        authorization = nil
      }
    }
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    Task { @MainActor in
      guard let last = locations.last else { return }
      fix?.resume(returning: last)
      fix = nil
    }
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    Task { @MainActor in
      fix?.resume(throwing: LocationError.noFix)
      fix = nil
    }
  }
}
