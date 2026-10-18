import KitbagCore
import SwiftUI

/// Which units to show. Automatic follows the phone's region.
enum UnitPreference: String, CaseIterable {
  case automatic
  case metric
  case us

  var title: LocalizedStringResource {
    switch self {
    case .automatic: LocalizedStringResource("Automatic", table: "Weather")
    case .metric: LocalizedStringResource("Metric (°C, km/h)", table: "Weather")
    case .us: LocalizedStringResource("US (°F, mph)", table: "Weather")
    }
  }

  var usesUSUnits: Bool {
    switch self {
    case .automatic: Locale.current.measurementSystem == .us
    case .metric: false
    case .us: true
    }
  }
}

/// Turns the forecast's metric numbers into the text a person reads.
struct WeatherFormat {
  let usesUSUnits: Bool

  /// `52°`, rounded.
  func temperature(_ celsius: Double) -> String {
    let value = usesUSUnits ? celsius * 9 / 5 + 32 : celsius
    return "\(Int(value.rounded()))°"
  }

  func wind(_ kmh: Double) -> String {
    usesUSUnits ? "\(Int((kmh * 0.621371).rounded())) mph" : "\(Int(kmh.rounded())) km/h"
  }

  func pressure(_ hectopascals: Double) -> String {
    usesUSUnits ? String(format: "%.2f inHg", hectopascals * 0.02953) : "\(Int(hectopascals.rounded())) hPa"
  }

  func distance(metres: Double) -> String {
    usesUSUnits
      ? String(format: "%.0f mi", metres / 1609.344) : String(format: "%.0f km", metres / 1000)
  }

  func rainfall(millimetres: Double) -> String {
    usesUSUnits ? String(format: "%.2f in", millimetres / 25.4) : String(format: "%.1f mm", millimetres)
  }

  func percent(_ value: Double) -> String { "\(Int(value.rounded()))%" }

  /// `WSW`: the compass point the wind blows from.
  static func compass(_ degrees: Double) -> String {
    let points = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
    let index = Int((degrees / 22.5).rounded()) % 16
    return points[(index + 16) % 16]
  }
}

extension WeatherKind {
  var title: LocalizedStringResource {
    switch self {
    case .clear: LocalizedStringResource("Clear", table: "Weather")
    case .mainlyClear: LocalizedStringResource("Mainly clear", table: "Weather")
    case .partlyCloudy: LocalizedStringResource("Partly cloudy", table: "Weather")
    case .overcast: LocalizedStringResource("Overcast", table: "Weather")
    case .fog: LocalizedStringResource("Fog", table: "Weather")
    case .drizzle: LocalizedStringResource("Drizzle", table: "Weather")
    case .freezingDrizzle: LocalizedStringResource("Freezing drizzle", table: "Weather")
    case .rain: LocalizedStringResource("Rain", table: "Weather")
    case .heavyRain: LocalizedStringResource("Heavy rain", table: "Weather")
    case .freezingRain: LocalizedStringResource("Freezing rain", table: "Weather")
    case .snow: LocalizedStringResource("Snow", table: "Weather")
    case .heavySnow: LocalizedStringResource("Heavy snow", table: "Weather")
    case .snowGrains: LocalizedStringResource("Snow grains", table: "Weather")
    case .rainShowers: LocalizedStringResource("Rain showers", table: "Weather")
    case .heavyRainShowers: LocalizedStringResource("Heavy rain showers", table: "Weather")
    case .snowShowers: LocalizedStringResource("Snow showers", table: "Weather")
    case .thunderstorm: LocalizedStringResource("Thunderstorm", table: "Weather")
    case .thunderstormWithHail: LocalizedStringResource("Thunderstorm with hail", table: "Weather")
    case .unknown: LocalizedStringResource("Unknown", table: "Weather")
    }
  }
}

/// A weather symbol drawn in its own colours: clouds in grey, the sun in orange and yellow, rain and snow in cyan.
/// (The system's multicolour clouds are white, which disappear on a light card.)
struct WeatherSymbol: View {
  let kind: WeatherKind
  let isDay: Bool
  var size: CGFloat = 24

  var body: some View {
    let colors = kind.symbolColors(isDay: isDay)
    Image(systemName: kind.symbolName(isDay: isDay))
      .symbolRenderingMode(.palette)
      .foregroundStyle(colors.primary, colors.secondary)
      .font(.system(size: size))
      .accessibilityHidden(true)
  }
}

extension WeatherKind {
  func symbolColors(isDay: Bool) -> (primary: Color, secondary: Color) {
    let cloud = Color(red: 0.60, green: 0.65, blue: 0.72)
    switch self {
    case .clear, .mainlyClear: return isDay ? (.yellow, .orange) : (.indigo, .yellow)
    case .partlyCloudy: return (cloud, isDay ? .orange : .indigo)
    case .overcast: return (cloud, cloud)
    case .fog: return (cloud, cloud.opacity(0.7))
    case .drizzle, .rain, .heavyRain, .rainShowers, .heavyRainShowers: return (cloud, .cyan)
    case .freezingDrizzle, .freezingRain, .snow, .snowGrains, .snowShowers: return (cloud, .cyan)
    case .heavySnow: return (.cyan, .cyan)
    case .thunderstorm, .thunderstormWithHail: return (cloud, .yellow)
    case .unknown: return (.secondary, .secondary)
    }
  }
}
