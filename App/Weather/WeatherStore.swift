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
  private(set) var place: Place
  /// True when the place follows the phone's location rather than a place that was chosen.
  private(set) var followsLocation: Bool
  /// Set when the phone's location could not be used (access off, or no fix).
  private(set) var locationFailed = false

  private let cacheURL = AppFiles.url("weather-v3.json")
  private let defaults: UserDefaults
  private let location = LocationProvider()
  private let session: URLSession

  /// How long a forecast counts as fresh.
  private let freshFor: TimeInterval = 15 * 60

  init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
    self.defaults = defaults
    self.session = session
    if let data = defaults.data(forKey: "weather.place"), let saved = try? JSONDecoder().decode(Place.self, from: data)
    {
      place = saved
    } else {
      place = .madison
    }
    followsLocation = defaults.bool(forKey: "weather.followsLocation")
    if let data = try? Data(contentsOf: cacheURL), let cached = try? JSONDecoder().decode(Forecast.self, from: data),
      cached.place == place
    {
      forecast = cached
    }
  }

  // MARK: Fetching

  /// Fetches the forecast unless the one we have is fresh (or `force`). A failure keeps the old forecast.
  func refresh(force: Bool = false) async {
    if followsLocation && (force || forecast == nil) { await updateLocation() }
    if !force, let forecast, forecast.place == place, Date().timeIntervalSince(forecast.fetchedAt) < freshFor { return }
    guard phase != .loading else { return }
    phase = .loading
    do {
      let (data, _) = try await session.data(from: OpenMeteo.forecastURL(for: place))
      let fetched = try OpenMeteo.decodeForecast(data, place: place, fetchedAt: Date())
      forecast = fetched
      phase = .idle
      if let encoded = try? JSONEncoder().encode(fetched) { try? AppFiles.write(encoded, to: cacheURL) }
    } catch {
      phase = .failed
    }
  }

  /// The age of the forecast, for "Updated" text.
  var isStale: Bool {
    guard let forecast else { return true }
    return Date().timeIntervalSince(forecast.fetchedAt) > freshFor
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
    guard let url = OpenMeteo.searchURL(query: query, language: language),
      let (data, _) = try? await session.data(from: url)
    else { return [] }
    return (try? OpenMeteo.decodePlaces(data)) ?? []
  }

  private func persist() {
    if let data = try? JSONEncoder().encode(place) { defaults.set(data, forKey: "weather.place") }
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
