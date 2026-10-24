import Foundation

/// A place to show the weather for.
public struct Place: Codable, Hashable, Sendable {
  public var name: String
  /// Region and country, for telling two places of one name apart: `"Illinois, United States"`.
  public var detail: String
  public var latitude: Double
  public var longitude: Double

  public init(name: String, detail: String = "", latitude: Double, longitude: Double) {
    self.name = name
    self.detail = detail
    self.latitude = latitude
    self.longitude = longitude
  }
}

/// What the sky is doing, grouped from the WMO weather codes that forecast services use.
public enum WeatherKind: String, Codable, Hashable, Sendable {
  case clear
  case mainlyClear
  case partlyCloudy
  case overcast
  case fog
  case drizzle
  case freezingDrizzle
  case rain
  case heavyRain
  case freezingRain
  case snow
  case heavySnow
  case snowGrains
  case rainShowers
  case heavyRainShowers
  case snowShowers
  case thunderstorm
  case thunderstormWithHail
  case unknown

  /// Groups a WMO weather interpretation code (0 to 99).
  public init(code: Int) {
    switch code {
    case 0: self = .clear
    case 1: self = .mainlyClear
    case 2: self = .partlyCloudy
    case 3: self = .overcast
    case 45, 48: self = .fog
    case 51, 53, 55: self = .drizzle
    case 56, 57: self = .freezingDrizzle
    case 61, 63: self = .rain
    case 65: self = .heavyRain
    case 66, 67: self = .freezingRain
    case 71, 73: self = .snow
    case 75: self = .heavySnow
    case 77: self = .snowGrains
    case 80, 81: self = .rainShowers
    case 82: self = .heavyRainShowers
    case 85, 86: self = .snowShowers
    case 95: self = .thunderstorm
    case 96, 99: self = .thunderstormWithHail
    default: self = .unknown
    }
  }

  /// The SF Symbol for this weather by day or night.
  public func symbolName(isDay: Bool) -> String {
    switch self {
    case .clear: isDay ? "sun.max.fill" : "moon.stars.fill"
    case .mainlyClear: isDay ? "sun.max.fill" : "moon.fill"
    case .partlyCloudy: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
    case .overcast: "cloud.fill"
    case .fog: "cloud.fog.fill"
    case .drizzle: "cloud.drizzle.fill"
    case .freezingDrizzle, .freezingRain: "cloud.sleet.fill"
    case .rain: "cloud.rain.fill"
    case .heavyRain: "cloud.heavyrain.fill"
    case .snow, .snowGrains: "cloud.snow.fill"
    case .heavySnow: "wind.snow"
    case .rainShowers: isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
    case .heavyRainShowers: "cloud.heavyrain.fill"
    case .snowShowers: "cloud.snow.fill"
    case .thunderstorm: "cloud.bolt.rain.fill"
    case .thunderstormWithHail: "cloud.bolt.fill"
    case .unknown: "questionmark.circle"
    }
  }
}

/// A forecast for one place. Temperatures are in °C, speeds in km/h, lengths in metres and pressure in hPa; the app
/// converts them to the units a person chose.
public struct Forecast: Codable, Hashable, Sendable {
  public struct Current: Codable, Hashable, Sendable {
    public var time: Date
    public var temperature: Double
    public var apparentTemperature: Double
    public var humidity: Double
    public var windSpeed: Double
    public var windGusts: Double?
    /// Degrees the wind comes from, 0 = north.
    public var windDirection: Double
    public var pressure: Double
    public var isDay: Bool
    public var code: Int

    public var kind: WeatherKind { WeatherKind(code: code) }
  }

  public struct Hour: Codable, Hashable, Sendable, Identifiable {
    public var time: Date
    public var temperature: Double
    public var apparentTemperature: Double
    /// Chance of rain or snow, 0 to 100.
    public var precipitationProbability: Double?
    public var code: Int
    public var isDay: Bool
    public var windSpeed: Double
    public var uvIndex: Double?
    public var visibility: Double?
    public var humidity: Double?
    /// Rain and snowfall in the hour, in mm of water.
    public var precipitation: Double?
    /// Share of the sky covered by cloud, 0 to 100.
    public var cloudCover: Double?
    public var windGusts: Double?
    /// Degrees the wind comes from, 0 = north.
    public var windDirection: Double?
    public var pressure: Double?
    /// The temperature at which the air would be saturated, in °C.
    public var dewPoint: Double?

    public var id: Date { time }
    public var kind: WeatherKind { WeatherKind(code: code) }
  }

  public struct Day: Codable, Hashable, Sendable, Identifiable {
    public var date: LocalDate
    public var code: Int
    public var maxTemperature: Double
    public var minTemperature: Double
    public var precipitationProbability: Double?
    /// Rain and snowfall together, in mm of water.
    public var precipitationSum: Double?
    public var uvIndexMax: Double?
    public var sunrise: Date?
    public var sunset: Date?
    public var windSpeedMax: Double?
    public var windGustsMax: Double?
    /// The highest and lowest "feels like" temperature of the day, in °C.
    public var apparentMax: Double?
    public var apparentMin: Double?
    /// Seconds between sunrise and sunset, and seconds of direct sunshine.
    public var daylightDuration: Double?
    public var sunshineDuration: Double?
    /// Hours of the day with rain or snow.
    public var precipitationHours: Double?
    /// Snowfall in cm.
    public var snowfallSum: Double?
    /// Degrees the wind mostly comes from, 0 = north.
    public var windDirectionDominant: Double?

    public var id: LocalDate { date }
    public var kind: WeatherKind { WeatherKind(code: code) }
  }

  public var place: Place
  public var fetchedAt: Date
  /// The place's time zone, such as `"America/Chicago"`.
  public var timeZoneID: String
  public var current: Current
  public var hourly: [Hour]
  public var daily: [Day]

  /// A calendar in the place's time zone, for asking which day or hour a moment is there.
  public var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: timeZoneID) ?? .current
    return calendar
  }

  /// The hour that contains `now`, and the hours after it, up to `count` in all.
  public func hours(from now: Date, count: Int) -> [Hour] {
    let upcoming = hourly.filter { $0.time.addingTimeInterval(3600) > now }
    return Array(upcoming.prefix(count))
  }

  /// The hours of a day at the place, earliest first. Past days hold what happened, the rest what is expected.
  public func hours(on day: LocalDate) -> [Hour] {
    let calendar = self.calendar
    return hourly.filter { LocalDate($0.time, calendar: calendar) == day }
  }

  /// What the hours of a day come to on average (or at worst, for visibility): the figures a day's summary lacks.
  public struct DayAverages: Hashable, Sendable {
    public var humidity: Double?
    public var pressure: Double?
    public var cloudCover: Double?
    public var dewPoint: Double?
    /// The shortest visibility of the day, in metres.
    public var minVisibility: Double?
  }

  public func averages(on day: LocalDate) -> DayAverages {
    let hours = hours(on: day)
    func mean(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
    return DayAverages(
      humidity: mean(hours.compactMap(\.humidity)), pressure: mean(hours.compactMap(\.pressure)),
      cloudCover: mean(hours.compactMap(\.cloudCover)), dewPoint: mean(hours.compactMap(\.dewPoint)),
      minVisibility: hours.compactMap(\.visibility).min())
  }

  /// The summary of a day at the place.
  public func day(_ day: LocalDate) -> Day? {
    daily.first { $0.date == day }
  }

  /// The forecast for the day that contains `now` at the place.
  public func today(at now: Date) -> Day? {
    let day = LocalDate(now, calendar: calendar)
    return daily.first { $0.date == day }
  }
}

public enum OpenMeteoError: Error, Equatable {
  /// The service answered with an error message.
  case service(String)
  /// The answer did not hold what was asked for.
  case missingData
}

/// The requests and answers of the Open-Meteo forecast and place-search services (https://open-meteo.com).
/// Their data is licensed CC BY 4.0, and the free service is for non-commercial use: see THIRD_PARTY.md.
public enum OpenMeteo {
  public static func forecastURL(for place: Place) -> URL {
    var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
    components.queryItems = [
      URLQueryItem(name: "latitude", value: String(place.latitude)),
      URLQueryItem(name: "longitude", value: String(place.longitude)),
      URLQueryItem(
        name: "current",
        value:
          "temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,pressure_msl,wind_speed_10m,wind_direction_10m,wind_gusts_10m"
      ),
      URLQueryItem(
        name: "hourly",
        value:
          "temperature_2m,apparent_temperature,relative_humidity_2m,precipitation_probability,precipitation,weather_code,cloud_cover,pressure_msl,visibility,wind_speed_10m,wind_gusts_10m,wind_direction_10m,uv_index,is_day,dew_point_2m"
      ),
      URLQueryItem(
        name: "daily",
        value:
          "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum,uv_index_max,sunrise,sunset,wind_speed_10m_max,wind_gusts_10m_max,apparent_temperature_max,apparent_temperature_min,daylight_duration,sunshine_duration,precipitation_hours,snowfall_sum,wind_direction_10m_dominant"
      ),
      URLQueryItem(name: "timezone", value: "auto"),
      URLQueryItem(name: "past_days", value: "7"),
      URLQueryItem(name: "forecast_days", value: "10"),
    ]
    return components.url!
  }

  public static func searchURL(query: String, language: String, count: Int = 6) -> URL? {
    var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
    components?.queryItems = [
      URLQueryItem(name: "name", value: query),
      URLQueryItem(name: "count", value: String(count)),
      URLQueryItem(name: "language", value: language),
      URLQueryItem(name: "format", value: "json"),
    ]
    return components?.url
  }

  // MARK: Answers

  private struct ErrorAnswer: Decodable {
    let error: Bool?
    let reason: String?
  }

  private struct ForecastAnswer: Decodable {
    struct Current: Decodable {
      let time: String
      let temperature2m: Double
      let apparentTemperature: Double?
      let relativeHumidity2m: Double?
      let isDay: Int?
      let weatherCode: Int
      let pressureMsl: Double?
      let windSpeed10m: Double?
      let windDirection10m: Double?
      let windGusts10m: Double?

      enum CodingKeys: String, CodingKey {
        case time
        case temperature2m = "temperature_2m"
        case apparentTemperature = "apparent_temperature"
        case relativeHumidity2m = "relative_humidity_2m"
        case isDay = "is_day"
        case weatherCode = "weather_code"
        case pressureMsl = "pressure_msl"
        case windSpeed10m = "wind_speed_10m"
        case windDirection10m = "wind_direction_10m"
        case windGusts10m = "wind_gusts_10m"
      }
    }
    struct Hourly: Decodable {
      let time: [String]
      let temperature2m: [Double?]
      let apparentTemperature: [Double?]?
      let weatherCode: [Int?]
      let precipitationProbability: [Double?]?
      let isDay: [Int?]?
      let uvIndex: [Double?]?
      let visibility: [Double?]?
      let windSpeed10m: [Double?]?
      let relativeHumidity2m: [Double?]?
      let precipitation: [Double?]?
      let cloudCover: [Double?]?
      let pressureMsl: [Double?]?
      let windGusts10m: [Double?]?
      let windDirection10m: [Double?]?
      let dewPoint2m: [Double?]?

      enum CodingKeys: String, CodingKey {
        case time
        case temperature2m = "temperature_2m"
        case apparentTemperature = "apparent_temperature"
        case weatherCode = "weather_code"
        case precipitationProbability = "precipitation_probability"
        case isDay = "is_day"
        case uvIndex = "uv_index"
        case visibility
        case windSpeed10m = "wind_speed_10m"
        case relativeHumidity2m = "relative_humidity_2m"
        case precipitation
        case cloudCover = "cloud_cover"
        case pressureMsl = "pressure_msl"
        case windGusts10m = "wind_gusts_10m"
        case windDirection10m = "wind_direction_10m"
        case dewPoint2m = "dew_point_2m"
      }
    }
    struct Daily: Decodable {
      let time: [String]
      let weatherCode: [Int?]
      let temperature2mMax: [Double?]
      let temperature2mMin: [Double?]
      let precipitationProbabilityMax: [Double?]?
      let precipitationSum: [Double?]?
      let uvIndexMax: [Double?]?
      let sunrise: [String?]?
      let sunset: [String?]?
      let windSpeed10mMax: [Double?]?
      let windGusts10mMax: [Double?]?
      let apparentTemperatureMax: [Double?]?
      let apparentTemperatureMin: [Double?]?
      let daylightDuration: [Double?]?
      let sunshineDuration: [Double?]?
      let precipitationHours: [Double?]?
      let snowfallSum: [Double?]?
      let windDirection10mDominant: [Double?]?

      enum CodingKeys: String, CodingKey {
        case time
        case weatherCode = "weather_code"
        case temperature2mMax = "temperature_2m_max"
        case temperature2mMin = "temperature_2m_min"
        case precipitationProbabilityMax = "precipitation_probability_max"
        case precipitationSum = "precipitation_sum"
        case uvIndexMax = "uv_index_max"
        case sunrise
        case sunset
        case windSpeed10mMax = "wind_speed_10m_max"
        case windGusts10mMax = "wind_gusts_10m_max"
        case apparentTemperatureMax = "apparent_temperature_max"
        case apparentTemperatureMin = "apparent_temperature_min"
        case daylightDuration = "daylight_duration"
        case sunshineDuration = "sunshine_duration"
        case precipitationHours = "precipitation_hours"
        case snowfallSum = "snowfall_sum"
        case windDirection10mDominant = "wind_direction_10m_dominant"
      }
    }
    let timezone: String
    let current: Current
    let hourly: Hourly
    let daily: Daily
  }

  public static func decodeForecast(_ data: Data, place: Place, fetchedAt: Date) throws -> Forecast {
    let decoder = JSONDecoder()
    if let failure = try? decoder.decode(ErrorAnswer.self, from: data), failure.error == true {
      throw OpenMeteoError.service(failure.reason ?? "")
    }
    let answer = try decoder.decode(ForecastAnswer.self, from: data)
    guard let zone = TimeZone(identifier: answer.timezone) else { throw OpenMeteoError.missingData }
    let parse = LocalTimeParser(timeZone: zone)

    guard let currentTime = parse(answer.current.time) else { throw OpenMeteoError.missingData }
    let current = Forecast.Current(
      time: currentTime, temperature: answer.current.temperature2m,
      apparentTemperature: answer.current.apparentTemperature ?? answer.current.temperature2m,
      humidity: answer.current.relativeHumidity2m ?? 0, windSpeed: answer.current.windSpeed10m ?? 0,
      windGusts: answer.current.windGusts10m, windDirection: answer.current.windDirection10m ?? 0,
      pressure: answer.current.pressureMsl ?? 0, isDay: (answer.current.isDay ?? 1) == 1,
      code: answer.current.weatherCode)

    let hourly = answer.hourly
    let hours: [Forecast.Hour] = hourly.time.enumerated().compactMap { index, text in
      guard let time = parse(text), let temperature = hourly.temperature2m[safe: index] ?? nil,
        let code = hourly.weatherCode[safe: index] ?? nil
      else { return nil }
      return Forecast.Hour(
        time: time, temperature: temperature,
        apparentTemperature: (hourly.apparentTemperature?[safe: index] ?? nil) ?? temperature,
        precipitationProbability: hourly.precipitationProbability?[safe: index] ?? nil, code: code,
        isDay: ((hourly.isDay?[safe: index] ?? nil) ?? 1) == 1,
        windSpeed: (hourly.windSpeed10m?[safe: index] ?? nil) ?? 0,
        uvIndex: hourly.uvIndex?[safe: index] ?? nil, visibility: hourly.visibility?[safe: index] ?? nil,
        humidity: hourly.relativeHumidity2m?[safe: index] ?? nil,
        precipitation: hourly.precipitation?[safe: index] ?? nil,
        cloudCover: hourly.cloudCover?[safe: index] ?? nil, windGusts: hourly.windGusts10m?[safe: index] ?? nil,
        windDirection: hourly.windDirection10m?[safe: index] ?? nil, pressure: hourly.pressureMsl?[safe: index] ?? nil,
        dewPoint: hourly.dewPoint2m?[safe: index] ?? nil)
    }

    let daily = answer.daily
    let days: [Forecast.Day] = daily.time.enumerated().compactMap { index, text in
      guard let date = LocalDate(text), let code = daily.weatherCode[safe: index] ?? nil,
        let high = daily.temperature2mMax[safe: index] ?? nil, let low = daily.temperature2mMin[safe: index] ?? nil
      else { return nil }
      return Forecast.Day(
        date: date, code: code, maxTemperature: high, minTemperature: low,
        precipitationProbability: daily.precipitationProbabilityMax?[safe: index] ?? nil,
        precipitationSum: daily.precipitationSum?[safe: index] ?? nil,
        uvIndexMax: daily.uvIndexMax?[safe: index] ?? nil,
        sunrise: (daily.sunrise?[safe: index] ?? nil).flatMap { parse($0) },
        sunset: (daily.sunset?[safe: index] ?? nil).flatMap { parse($0) },
        windSpeedMax: daily.windSpeed10mMax?[safe: index] ?? nil,
        windGustsMax: daily.windGusts10mMax?[safe: index] ?? nil,
        apparentMax: daily.apparentTemperatureMax?[safe: index] ?? nil,
        apparentMin: daily.apparentTemperatureMin?[safe: index] ?? nil,
        daylightDuration: daily.daylightDuration?[safe: index] ?? nil,
        sunshineDuration: daily.sunshineDuration?[safe: index] ?? nil,
        precipitationHours: daily.precipitationHours?[safe: index] ?? nil,
        snowfallSum: daily.snowfallSum?[safe: index] ?? nil,
        windDirectionDominant: daily.windDirection10mDominant?[safe: index] ?? nil)
    }
    guard !hours.isEmpty, !days.isEmpty else { throw OpenMeteoError.missingData }
    return Forecast(
      place: place, fetchedAt: fetchedAt, timeZoneID: answer.timezone, current: current, hourly: hours, daily: days)
  }

  private struct PlacesAnswer: Decodable {
    struct Result: Decodable {
      let name: String
      let latitude: Double
      let longitude: Double
      let admin1: String?
      let country: String?
    }
    let results: [Result]?
  }

  /// The places that a search found, best match first. No match gives an empty list.
  public static func decodePlaces(_ data: Data) throws -> [Place] {
    let answer = try JSONDecoder().decode(PlacesAnswer.self, from: data)
    return (answer.results ?? []).map {
      Place(
        name: $0.name, detail: [$0.admin1, $0.country].compactMap { $0 }.joined(separator: ", "), latitude: $0.latitude,
        longitude: $0.longitude)
    }
  }

  /// Reads the service's local times (`2026-10-18T14:00`) in the place's time zone.
  private struct LocalTimeParser {
    let formatter: DateFormatter

    init(timeZone: TimeZone) {
      formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.calendar = Calendar(identifier: .gregorian)
      formatter.timeZone = timeZone
      formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
    }

    func callAsFunction(_ text: String) -> Date? { formatter.date(from: text) }
  }
}

extension Array {
  fileprivate subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
