import Foundation
import Testing

@testable import KitbagCore

// A shortened answer in the shape the Open-Meteo forecast service returns. The numbers are invented.
private let forecastJSON = """
  {
    "latitude": 43.07, "longitude": -89.4, "timezone": "America/Chicago", "utc_offset_seconds": -18000,
    "current": {
      "time": "2026-10-18T14:15", "interval": 900, "temperature_2m": 12.5, "relative_humidity_2m": 61,
      "apparent_temperature": 10.2, "is_day": 1, "weather_code": 2, "pressure_msl": 1016.4,
      "wind_speed_10m": 14.4, "wind_direction_10m": 250, "wind_gusts_10m": 30.2
    },
    "hourly": {
      "time": ["2026-10-18T13:00", "2026-10-18T14:00", "2026-10-18T15:00", "2026-10-18T16:00"],
      "temperature_2m": [12.0, 12.5, 12.9, null],
      "apparent_temperature": [9.8, 10.2, 10.6, 10.0],
      "weather_code": [2, 2, 3, 61],
      "precipitation_probability": [5, 10, 40, null],
      "is_day": [1, 1, 1, 0],
      "uv_index": [2.1, 1.8, 1.2, 0.0],
      "visibility": [24140.0, 24140.0, 20000.0, 9000.0],
      "wind_speed_10m": [13.0, 14.4, 15.0, 16.0],
      "relative_humidity_2m": [60, 61, 62, 63],
      "precipitation": [0.0, 0.0, 0.2, null],
      "cloud_cover": [20, 30, 80, 100],
      "pressure_msl": [1016.5, 1016.4, 1015.2, 1014.0],
      "wind_gusts_10m": [25.0, 30.2, 32.0, 35.0],
      "wind_direction_10m": [240, 250, 255, 260]
    },
    "daily": {
      "time": ["2026-10-18", "2026-10-19"],
      "weather_code": [2, 61],
      "temperature_2m_max": [13.4, 9.0],
      "temperature_2m_min": [4.1, 3.0],
      "precipitation_probability_max": [10, 80],
      "precipitation_sum": [0.0, 6.5],
      "uv_index_max": [3.4, 1.9],
      "sunrise": ["2026-10-18T07:12", "2026-10-19T07:13"],
      "sunset": ["2026-10-18T18:03", "2026-10-19T18:01"],
      "wind_speed_10m_max": [20.0, 28.0],
      "wind_gusts_10m_max": [30.2, 40.0]
    }
  }
  """

private func moment(_ text: String, zone: String = "America/Chicago") -> Date {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = TimeZone(identifier: zone)
  formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
  return formatter.date(from: text)!
}

@Suite("Weather")
struct WeatherTests {
  @Test func groupsWMOCodes() {
    #expect(WeatherKind(code: 0) == .clear)
    #expect(WeatherKind(code: 3) == .overcast)
    #expect(WeatherKind(code: 45) == .fog)
    #expect(WeatherKind(code: 65) == .heavyRain)
    #expect(WeatherKind(code: 73) == .snow)
    #expect(WeatherKind(code: 95) == .thunderstorm)
    #expect(WeatherKind(code: 99) == .thunderstormWithHail)
    #expect(WeatherKind(code: 4) == .unknown)
  }

  @Test func picksASymbolForDayOrNight() {
    #expect(WeatherKind.clear.symbolName(isDay: true) == "sun.max.fill")
    #expect(WeatherKind.clear.symbolName(isDay: false) == "moon.stars.fill")
    #expect(WeatherKind.rain.symbolName(isDay: false) == "cloud.rain.fill")
  }

  @Test func buildsTheForecastRequest() throws {
    let url = OpenMeteo.forecastURL(for: .sample)
    let items = Dictionary(
      uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map {
        ($0.name, $0.value ?? "")
      })
    #expect(url.host == "api.open-meteo.com")
    #expect(items["latitude"] == "39.7817")
    #expect(items["longitude"] == "-89.6501")
    #expect(items["timezone"] == "auto")
    #expect(items["current"]?.contains("temperature_2m") == true)
    #expect(items["hourly"]?.contains("precipitation_probability") == true)
    #expect(items["daily"]?.contains("sunrise") == true)
    #expect(items["past_days"] == "7")
    #expect(items["forecast_days"] == "10")
    #expect(items["hourly"]?.contains("cloud_cover") == true)
    #expect(items["hourly"]?.contains("wind_gusts_10m") == true)
  }

  @Test func buildsThePlaceSearchRequest() throws {
    let url = try #require(OpenMeteo.searchURL(query: "São Paulo", language: "ja"))
    #expect(url.host == "geocoding-api.open-meteo.com")
    #expect(url.absoluteString.contains("name=S%C3%A3o%20Paulo") || url.absoluteString.contains("name=S%C3%A3o+Paulo"))
    #expect(url.absoluteString.contains("language=ja"))
  }

  @Test func decodesAForecast() throws {
    let fetched = moment("2026-10-18T14:16")
    let forecast = try OpenMeteo.decodeForecast(Data(forecastJSON.utf8), place: .sample, fetchedAt: fetched)
    #expect(forecast.timeZoneID == "America/Chicago")
    #expect(forecast.current.temperature == 12.5)
    #expect(forecast.current.time == moment("2026-10-18T14:15"))
    #expect(forecast.current.kind == .partlyCloudy)
    #expect(forecast.current.isDay)
    #expect(forecast.current.windGusts == 30.2)
    // The hour with no temperature is dropped, not guessed.
    #expect(forecast.hourly.count == 3)
    #expect(forecast.hourly[2].precipitationProbability == 40)
    #expect(forecast.hourly[2].cloudCover == 80)
    #expect(forecast.hourly[2].humidity == 62)
    #expect(forecast.hourly[2].precipitation == 0.2)
    #expect(forecast.hourly[2].pressure == 1015.2)
    #expect(forecast.hourly[2].windGusts == 32.0)
    #expect(forecast.hourly[2].windDirection == 255)
    #expect(forecast.daily[1].windGustsMax == 40.0)
    #expect(forecast.daily.count == 2)
    #expect(forecast.daily[0].date == LocalDate(year: 2026, month: 10, day: 18))
    #expect(forecast.daily[0].maxTemperature == 13.4)
    #expect(forecast.daily[1].kind == .rain)
    #expect(forecast.daily[0].sunrise == moment("2026-10-18T07:12"))
    #expect(forecast.daily[0].sunset == moment("2026-10-18T18:03"))
  }

  @Test func findsTheHoursAheadAndToday() throws {
    let forecast = try OpenMeteo.decodeForecast(Data(forecastJSON.utf8), place: .sample, fetchedAt: .now)
    let now = moment("2026-10-18T14:20")
    #expect(
      forecast.hours(from: now, count: 2).map(\.time) == [moment("2026-10-18T14:00"), moment("2026-10-18T15:00")])
    #expect(forecast.today(at: now)?.maxTemperature == 13.4)
    #expect(forecast.today(at: moment("2026-10-30T10:00")) == nil)
  }

  @Test func findsTheHoursAndTheSummaryOfADay() throws {
    let forecast = try OpenMeteo.decodeForecast(Data(forecastJSON.utf8), place: .sample, fetchedAt: .now)
    let today = LocalDate(year: 2026, month: 10, day: 18)
    #expect(forecast.hours(on: today).count == 3)
    #expect(forecast.hours(on: LocalDate(year: 2026, month: 10, day: 19)).isEmpty)
    #expect(forecast.day(today)?.maxTemperature == 13.4)
    #expect(forecast.day(LocalDate(year: 2026, month: 10, day: 30)) == nil)
  }

  @Test func readsAnOldCachedForecastWithoutTheNewFields() throws {
    let forecast = try OpenMeteo.decodeForecast(Data(forecastJSON.utf8), place: .sample, fetchedAt: .now)
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(forecast)) as? [String: Any])
    var hours = try #require(object["hourly"] as? [[String: Any]])
    for index in hours.indices {
      for key in ["humidity", "precipitation", "cloudCover", "windGusts", "windDirection", "pressure"] {
        hours[index][key] = nil
      }
    }
    object["hourly"] = hours
    let old = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(Forecast.self, from: old)
    #expect(decoded.hourly[0].cloudCover == nil)
    #expect(decoded.hourly[0].temperature == forecast.hourly[0].temperature)
  }

  @Test func readsTheTimesInThePlacesZoneNotThePhones() throws {
    // 14:15 in Chicago (UTC-5 in October) is 19:15 UTC.
    let forecast = try OpenMeteo.decodeForecast(Data(forecastJSON.utf8), place: .sample, fetchedAt: .now)
    #expect(
      forecast.current.time
        == Date(timeIntervalSince1970: moment("2026-10-18T19:15", zone: "UTC").timeIntervalSince1970))
  }

  @Test func reportsAServiceError() {
    let json = #"{"error": true, "reason": "Latitude must be in range of -90 to 90°."}"#
    #expect(throws: OpenMeteoError.service("Latitude must be in range of -90 to 90°.")) {
      try OpenMeteo.decodeForecast(Data(json.utf8), place: .sample, fetchedAt: .now)
    }
  }

  @Test func rejectsAnAnswerWithoutHours() {
    let json = forecastJSON.replacingOccurrences(
      of: "\"2026-10-18T13:00\", \"2026-10-18T14:00\", \"2026-10-18T15:00\", \"2026-10-18T16:00\"", with: ""
    )
    .replacingOccurrences(of: "[12.0, 12.5, 12.9, null]", with: "[]")
    .replacingOccurrences(of: "[2, 2, 3, 61]", with: "[]")
    #expect(throws: OpenMeteoError.missingData) {
      try OpenMeteo.decodeForecast(Data(json.utf8), place: .sample, fetchedAt: .now)
    }
  }

  @Test func decodesPlaces() throws {
    let json = """
      { "results": [
        { "id": 1, "name": "Springfield", "latitude": 39.78, "longitude": -89.65, "country": "United States", "admin1": "Illinois", "timezone": "America/Chicago" },
        { "id": 2, "name": "Springfield", "latitude": 37.2, "longitude": -93.3, "country": "United States" }
      ], "generationtime_ms": 0.5 }
      """
    let places = try OpenMeteo.decodePlaces(Data(json.utf8))
    #expect(places.map(\.name) == ["Springfield", "Springfield"])
    #expect(places[0].detail == "Illinois, United States")
    #expect(places[1].detail == "United States")
    #expect(try OpenMeteo.decodePlaces(Data(#"{"generationtime_ms": 0.2}"#.utf8)).isEmpty)
  }

  @Test func roundTripsAForecastThroughJSON() throws {
    let forecast = try OpenMeteo.decodeForecast(
      Data(forecastJSON.utf8), place: .sample, fetchedAt: moment("2026-10-18T14:16"))
    let data = try JSONEncoder().encode(forecast)
    #expect(try JSONDecoder().decode(Forecast.self, from: data) == forecast)
  }

  @Test func averagesTheHoursOfADay() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18)) ?? Date()
    func hour(_ offset: Int, humidity: Double?, pressure: Double?, visibility: Double?) -> Forecast.Hour {
      Forecast.Hour(
        time: start.addingTimeInterval(Double(offset) * 3600), temperature: 10, apparentTemperature: 10,
        precipitationProbability: nil, code: 0, isDay: true, windSpeed: 5, uvIndex: nil, visibility: visibility,
        humidity: humidity, precipitation: nil, cloudCover: nil, windGusts: nil, windDirection: nil, pressure: pressure)
    }
    let forecast = Forecast(
      place: Place(name: "X", latitude: 0, longitude: 0), fetchedAt: start, timeZoneID: "UTC",
      current: Forecast.Current(
        time: start, temperature: 10, apparentTemperature: 10, humidity: 50, windSpeed: 5, windGusts: nil,
        windDirection: 0, pressure: 1000, isDay: true, code: 0),
      hourly: [
        hour(0, humidity: 40, pressure: 1000, visibility: 20000),
        hour(1, humidity: 60, pressure: 1010, visibility: 8000),
        hour(2, humidity: nil, pressure: nil, visibility: nil),
        hour(30, humidity: 99, pressure: 900, visibility: 1),  // the next day
      ], daily: [])
    let averages = forecast.averages(on: LocalDate(year: 2026, month: 10, day: 18))
    #expect(averages.humidity == 50)
    #expect(averages.pressure == 1005)
    #expect(averages.minVisibility == 8000)
    #expect(averages.cloudCover == nil)
    #expect(forecast.averages(on: LocalDate(year: 2026, month: 1, day: 1)).humidity == nil)
  }
}

extension Place {
  /// A place for the tests to ask about.
  static let sample = Place(
    name: "Springfield", detail: "Illinois, United States", latitude: 39.7817, longitude: -89.6501)
}
