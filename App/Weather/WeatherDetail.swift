import Charts
import KitbagCore
import SwiftUI

/// A measure the weather screen summarises for a day, and that can be opened for a closer look across all the days.
enum WeatherMetric: String, CaseIterable, Identifiable {
  case temperature
  case sun
  case uv
  case rain
  case wind
  case humidity
  case pressure
  case cloud

  var id: String { rawValue }

  var title: LocalizedStringResource {
    switch self {
    case .temperature: LocalizedStringResource("Temperature", table: "Weather")
    case .sun: LocalizedStringResource("Sun", table: "Weather")
    case .uv: LocalizedStringResource("UV index", table: "Weather")
    case .rain: LocalizedStringResource("Rain and snow", table: "Weather")
    case .wind: LocalizedStringResource("Wind", table: "Weather")
    case .humidity: LocalizedStringResource("Humidity", table: "Weather")
    case .pressure: LocalizedStringResource("Pressure", table: "Weather")
    case .cloud: LocalizedStringResource("Cloud and visibility", table: "Weather")
    }
  }

  var symbol: String {
    switch self {
    case .temperature: "thermometer.medium"
    case .sun: "sunrise"
    case .uv: "sun.max"
    case .rain: "drop"
    case .wind: "wind"
    case .humidity: "humidity"
    case .pressure: "gauge.with.dots.needle.bottom.50percent"
    case .cloud: "cloud"
    }
  }

  var tint: Color {
    switch self {
    case .temperature: .orange
    case .sun: .yellow
    case .uv: .orange
    case .rain: .cyan
    case .wind: .teal
    case .humidity: .blue
    case .pressure: .indigo
    case .cloud: .gray
    }
  }
}

/// What a day is for one measure: the number the chart and the calendar are drawn from, the text shown for it, and the
/// other figures of the day.
struct MetricReading {
  /// The number to draw, in the unit the person reads.
  var value: Double?
  var text: String
  /// A second, smaller line for a cell or a heading.
  var detail: String?

  static let none = MetricReading(value: nil, text: "–", detail: nil)
}

/// How a measure reads from a forecast: one function so that the summary chips, the chart, the calendar and the list all agree.
struct MetricReader {
  let forecast: Forecast
  let format: WeatherFormat

  private var zone: TimeZone { TimeZone(identifier: forecast.timeZoneID) ?? .current }

  func time(_ date: Date?) -> String {
    date.map { $0.formatted(Date.FormatStyle(timeZone: zone).hour().minute().locale(LanguageStore.shared.locale)) }
      ?? "–"
  }

  func duration(_ seconds: Double?) -> String {
    guard let seconds else { return "–" }
    let minutes = Int((seconds / 60).rounded())
    return "\(minutes / 60)h \(minutes % 60)m"
  }

  func reading(_ metric: WeatherMetric, on date: LocalDate) -> MetricReading {
    guard let day = forecast.day(date) else { return .none }
    let averages = forecast.averages(on: date)
    switch metric {
    case .temperature:
      return MetricReading(
        value: format.temperatureValue(day.maxTemperature), text: format.temperature(day.maxTemperature),
        detail: format.temperature(day.minTemperature))
    case .sun:
      return MetricReading(
        value: day.daylightDuration.map { $0 / 3600 }, text: duration(day.daylightDuration),
        detail: "\(time(day.sunrise)) – \(time(day.sunset))")
    case .uv:
      return MetricReading(
        value: day.uvIndexMax, text: day.uvIndexMax.map { "\(Int($0.rounded()))" } ?? "–",
        detail: day.uvIndexMax.map { Self.uvLevel($0) })
    case .rain:
      return MetricReading(
        value: day.precipitationSum.map { format.rainValue($0) },
        text: day.precipitationSum.map { String(format: "%.1f", format.rainValue($0)) } ?? "–",
        detail: day.precipitationProbability.map { format.percent($0) })
    case .wind:
      return MetricReading(
        value: day.windSpeedMax.map { format.windValue($0) },
        text: day.windSpeedMax.map { "\(Int(format.windValue($0).rounded()))" } ?? "–",
        detail: day.windDirectionDominant.map { WeatherFormat.compass($0) })
    case .humidity:
      return MetricReading(
        value: averages.humidity, text: averages.humidity.map { format.percent($0) } ?? "–",
        detail: averages.dewPoint.map { format.temperature($0) })
    case .pressure:
      return MetricReading(
        value: averages.pressure.map { format.pressureValue($0) },
        text: averages.pressure.map {
          format.usesUSUnits
            ? String(format: "%.2f", format.pressureValue($0)) : "\(Int(format.pressureValue($0).rounded()))"
        } ?? "–", detail: nil)
    case .cloud:
      return MetricReading(
        value: averages.cloudCover, text: averages.cloudCover.map { format.percent($0) } ?? "–",
        detail: averages.minVisibility.map { format.distance(metres: $0) })
    }
  }

  /// The unit that goes with a measure's number.
  func unit(_ metric: WeatherMetric) -> String {
    switch metric {
    case .temperature: format.usesUSUnits ? "°F" : "°C"
    case .sun: ""
    case .uv: ""
    case .rain: format.rainUnit
    case .wind: format.windUnit
    case .humidity, .cloud: "%"
    case .pressure: format.pressureUnit
    }
  }

  static func uvLevel(_ value: Double) -> String {
    switch value {
    case ..<3: L10n.string("Low", table: "Weather")
    case ..<6: L10n.string("Moderate", table: "Weather")
    case ..<8: L10n.string("High", table: "Weather")
    case ..<11: L10n.string("Very high", table: "Weather")
    default: L10n.string("Extreme", table: "Weather")
    }
  }

  /// All the figures of a day for a measure, as label and value, for the list under the chart.
  func details(_ metric: WeatherMetric, on date: LocalDate) -> [(label: LocalizedStringResource, value: String)] {
    guard let day = forecast.day(date) else { return [] }
    let averages = forecast.averages(on: date)
    switch metric {
    case .temperature:
      return [
        (LocalizedStringResource("Daily high", table: "Weather"), format.temperature(day.maxTemperature)),
        (LocalizedStringResource("Daily low", table: "Weather"), format.temperature(day.minTemperature)),
        (
          LocalizedStringResource("Feels like, high", table: "Weather"),
          day.apparentMax.map { format.temperature($0) } ?? "–"
        ),
        (
          LocalizedStringResource("Feels like, low", table: "Weather"),
          day.apparentMin.map { format.temperature($0) } ?? "–"
        ),
      ]
    case .sun:
      return [
        (LocalizedStringResource("Sunrise", table: "Weather"), time(day.sunrise)),
        (LocalizedStringResource("Sunset", table: "Weather"), time(day.sunset)),
        (LocalizedStringResource("Daylight", table: "Weather"), duration(day.daylightDuration)),
        (LocalizedStringResource("Direct sunshine", table: "Weather"), duration(day.sunshineDuration)),
      ]
    case .uv:
      return [
        (
          LocalizedStringResource("Highest UV index", table: "Weather"),
          day.uvIndexMax.map { String(format: "%.1f", $0) } ?? "–"
        ),
        (LocalizedStringResource("Level", table: "Weather"), day.uvIndexMax.map { Self.uvLevel($0) } ?? "–"),
      ]
    case .rain:
      return [
        (
          LocalizedStringResource("Total", table: "Weather"),
          day.precipitationSum.map { "\(String(format: "%.1f", format.rainValue($0))) \(format.rainUnit)" } ?? "–"
        ),
        (
          LocalizedStringResource("Chance", table: "Weather"),
          day.precipitationProbability.map { format.percent($0) } ?? "–"
        ),
        (
          LocalizedStringResource("Hours with rain or snow", table: "Weather"),
          day.precipitationHours.map { "\(Int($0.rounded()))" } ?? "–"
        ),
        (
          LocalizedStringResource("Snowfall", table: "Weather"),
          day.snowfallSum.map {
            format.usesUSUnits ? String(format: "%.1f in", $0 / 2.54) : String(format: "%.1f cm", $0)
          } ?? "–"
        ),
      ]
    case .wind:
      return [
        (LocalizedStringResource("Strongest wind", table: "Weather"), day.windSpeedMax.map { format.wind($0) } ?? "–"),
        (LocalizedStringResource("Strongest gust", table: "Weather"), day.windGustsMax.map { format.wind($0) } ?? "–"),
        (
          LocalizedStringResource("Mostly from", table: "Weather"),
          day.windDirectionDominant.map { "\(WeatherFormat.compass($0)) (\(Int($0.rounded()))°)" } ?? "–"
        ),
      ]
    case .humidity:
      return [
        (
          LocalizedStringResource("Average humidity", table: "Weather"),
          averages.humidity.map { format.percent($0) } ?? "–"
        ),
        (
          LocalizedStringResource("Dew point", table: "Weather"),
          averages.dewPoint.map { format.temperature($0) } ?? "–"
        ),
      ]
    case .pressure:
      return [
        (
          LocalizedStringResource("Average pressure", table: "Weather"),
          averages.pressure.map { format.pressure($0) } ?? "–"
        )
      ]
    case .cloud:
      return [
        (
          LocalizedStringResource("Average cloud cover", table: "Weather"),
          averages.cloudCover.map { format.percent($0) } ?? "–"
        ),
        (
          LocalizedStringResource("Shortest visibility", table: "Weather"),
          averages.minVisibility.map { format.distance(metres: $0) } ?? "–"
        ),
      ]
    }
  }
}

/// One measure across every day the forecast has (a week back and ten ahead): a bar for each day that can be dragged over, a
/// calendar tinted by the value, and, for the chosen day, its hours and all its figures.
struct WeatherMetricDetail: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.palette) private var palette

  let metric: WeatherMetric
  let forecast: Forecast
  let format: WeatherFormat
  let today: LocalDate
  @State var day: LocalDate

  private var reader: MetricReader { MetricReader(forecast: forecast, format: format) }
  private var calendar: Calendar { forecast.calendar }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 12) {
          header
          dayChart.themedCard(padding: 10, radius: 16)
          calendarGrid.themedCard(padding: 10, radius: 16)
          hourSection.themedCard(padding: 10, radius: 16)
          figures.themedCard(padding: 12, radius: 16)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
      }
      .themedScreen()
      .navigationTitle(Text(metric.title))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button {
            dismiss()
          } label: {
            Text("Done", tableName: "Calendar")
          }
        }
      }
    }
  }

  // MARK: Header

  private var header: some View {
    let reading = reader.reading(metric, on: day)
    return HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 2) {
        Text(day.date(calendar: calendar), format: .dateTime.weekday(.wide).month(.wide).day())
          .font(.subheadline.weight(.semibold))
        if day == today {
          Text("Today", tableName: "Weather").font(.caption).foregroundStyle(palette.accent)
        } else if day < today {
          Text("Past", tableName: "Weather").font(.caption).foregroundStyle(.secondary)
        }
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 0) {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
          Text(reading.text).font(.system(size: 34, weight: .semibold))
          Text(reader.unit(metric)).font(.footnote).foregroundStyle(.secondary)
        }
        if let detail = reading.detail { Text(detail).font(.footnote).foregroundStyle(.secondary) }
      }
    }
    .padding(.horizontal, 4)
  }

  // MARK: The days

  /// A bar for each day; drag across them to move the chosen day.
  private var dayChart: some View {
    let days = forecast.daily
    return VStack(alignment: .leading, spacing: 4) {
      Text("Every day", tableName: "Weather").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
      Chart {
        ForEach(days) { entry in
          if let value = reader.reading(metric, on: entry.date).value {
            if usesBars {
              BarMark(x: .value("Day", noon(entry.date), unit: .day), y: .value("Value", value), width: .ratio(0.7))
                .foregroundStyle(
                  entry.date == day ? palette.accent : metric.tint.opacity(entry.date < today ? 0.35 : 0.7)
                )
                .cornerRadius(3)
            } else {
              LineMark(x: .value("Day", noon(entry.date)), y: .value("Value", value))
                .foregroundStyle(metric.tint.opacity(0.8))
                .interpolationMethod(.catmullRom)
              PointMark(x: .value("Day", noon(entry.date)), y: .value("Value", value))
                .symbolSize(entry.date == day ? 80 : 20)
                .foregroundStyle(entry.date == day ? palette.accent : metric.tint)
            }
          }
        }
        if let todayEntry = days.first(where: { $0.date == today }) {
          RuleMark(x: .value("Today", noon(todayEntry.date)))
            .foregroundStyle(palette.heading.opacity(0.6))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
        }
      }
      .chartYScale(domain: yDomain)
      .chartXSelection(
        value: Binding<Date?>(
          get: { nil },
          set: { picked in
            if let picked,
              let match = days.min(by: {
                abs(noon($0.date).timeIntervalSince(picked)) < abs(noon($1.date).timeIntervalSince(picked))
              })
            {
              day = match.date
            }
          })
      )
      .chartXAxis {
        AxisMarks(values: .stride(by: .day, count: 2)) { _ in
          AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
          AxisValueLabel(format: Date.FormatStyle(timeZone: calendar.timeZone).day(), centered: true)
        }
      }
      .chartYAxis {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
          AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
          AxisValueLabel()
        }
      }
      .font(.caption2)
      .frame(height: 130)
    }
  }

  /// A measure that starts from nothing is drawn as bars; one whose changes are small next to its size (the length of the
  /// day, the pressure, the temperature) as a line with a closer scale, so that the change shows.
  private var usesBars: Bool {
    switch metric {
    case .rain, .uv, .wind, .cloud, .humidity: true
    case .temperature, .sun, .pressure: false
    }
  }

  private var yDomain: ClosedRange<Double> {
    let values = forecast.daily.compactMap { reader.reading(metric, on: $0.date).value }
    guard let low = values.min(), let high = values.max() else { return 0...1 }
    if usesBars { return 0...max(high * 1.1, 1) }
    let pad = max((high - low) * 0.2, metric == .pressure ? 2 : 1)
    return (low - pad)...(high + pad)
  }

  private func noon(_ date: LocalDate) -> Date {
    calendar.date(byAdding: .hour, value: 12, to: date.date(calendar: calendar)) ?? date.date(calendar: calendar)
  }

  // MARK: The calendar

  private var calendarGrid: some View {
    let weekdays = (0..<7).map { offset -> String in
      let index = (calendar.firstWeekday - 1 + offset) % 7
      return calendar.shortStandaloneWeekdaySymbols[index]
    }
    let cells = gridCells()
    let values = forecast.daily.compactMap { reader.reading(metric, on: $0.date).value }
    let low = values.min() ?? 0
    let high = values.max() ?? 1
    return VStack(alignment: .leading, spacing: 6) {
      Text("Calendar", tableName: "Weather").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
        ForEach(weekdays, id: \.self) { name in
          Text(name).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
        }
        ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
          if let entry = cell {
            calendarCell(entry, low: low, high: high)
          } else {
            Color.clear.frame(height: 50)
          }
        }
      }
    }
  }

  /// The days as grid cells, with empty cells before the first so that every weekday lines up.
  private func gridCells() -> [LocalDate?] {
    guard let first = forecast.daily.first?.date else { return [] }
    let weekday = calendar.component(.weekday, from: first.date(calendar: calendar))
    let leading = (weekday - calendar.firstWeekday + 7) % 7
    return Array(repeating: nil, count: leading) + forecast.daily.map { Optional($0.date) }
  }

  private func calendarCell(_ date: LocalDate, low: Double, high: Double) -> some View {
    let reading = reader.reading(metric, on: date)
    let fraction = reading.value.map { high > low ? ($0 - low) / (high - low) : 0.5 } ?? 0
    let selected = date == day
    return Button {
      day = date
    } label: {
      VStack(spacing: 1) {
        Text("\(date.day)").font(.system(size: 9, weight: date == today ? .bold : .regular)).foregroundStyle(
          date == today ? palette.accent : .secondary)
        Text(reading.text).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
        Text(reading.detail ?? " ").font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(
          0.5)
      }
      .frame(maxWidth: .infinity, minHeight: 50)
      .background(
        metric.tint.opacity(reading.value == nil ? 0 : 0.08 + 0.4 * fraction), in: RoundedRectangle(cornerRadius: 8)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? palette.accent : Color.clear, lineWidth: 1.5)
      )
      .opacity(date < today && !selected ? 0.7 : 1)
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  // MARK: The hours of the chosen day

  @ViewBuilder private var hourSection: some View {
    let hours = forecast.hours(on: day)
    VStack(alignment: .leading, spacing: 4) {
      Text("Through the day", tableName: "Weather").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
      if metric == .sun {
        SunStrip(day: forecast.day(day), forecast: forecast, isToday: day == today)
      } else if hours.isEmpty {
        Text("No hourly figures for this day.", tableName: "Weather").font(.footnote).foregroundStyle(.secondary)
      } else {
        hourChart(hours)
      }
    }
  }

  private func hourChart(_ hours: [Forecast.Hour]) -> some View {
    Chart {
      ForEach(hours) { hour in
        hourMarks(hour)
      }
    }
    .chartXAxis {
      AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
        AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
        AxisValueLabel(format: Date.FormatStyle(timeZone: calendar.timeZone).hour(), centered: false)
      }
    }
    .chartYAxis {
      AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
        AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
        AxisValueLabel()
      }
    }
    .font(.caption2)
    .frame(height: 120)
  }

  /// The marks for one hour of the chosen measure. Each measure has its own small function so that the compiler can follow it.
  @ChartContentBuilder private func hourMarks(_ hour: Forecast.Hour) -> some ChartContent {
    switch metric {
    case .temperature: temperatureMarks(hour)
    case .wind: windMarks(hour)
    case .uv: uvMarks(hour)
    case .rain: rainMarks(hour)
    case .humidity: humidityMarks(hour)
    case .pressure: pressureMarks(hour)
    case .cloud: cloudMarks(hour)
    case .sun: PointMark(x: .value("Hour", hour.time), y: .value("Unused", 0)).opacity(0)
    }
  }

  @ChartContentBuilder private func temperatureMarks(_ hour: Forecast.Hour) -> some ChartContent {
    let temperature = format.temperatureValue(hour.temperature)
    let feels = format.temperatureValue(hour.apparentTemperature)
    LineMark(x: .value("Hour", hour.time), y: .value("Temperature", temperature), series: .value("S", "a"))
      .foregroundStyle(palette.accent)
      .interpolationMethod(.catmullRom)
    LineMark(x: .value("Hour", hour.time), y: .value("Feels", feels), series: .value("S", "b"))
      .foregroundStyle(Color.secondary)
      .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
      .interpolationMethod(.catmullRom)
  }

  @ChartContentBuilder private func windMarks(_ hour: Forecast.Hour) -> some ChartContent {
    let speed = format.windValue(hour.windSpeed)
    LineMark(x: .value("Hour", hour.time), y: .value("Wind", speed), series: .value("S", "a"))
      .foregroundStyle(palette.accent)
      .interpolationMethod(.catmullRom)
    if let gust = hour.windGusts {
      LineMark(x: .value("Hour", hour.time), y: .value("Gusts", format.windValue(gust)), series: .value("S", "b"))
        .foregroundStyle(Color.secondary)
        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
        .interpolationMethod(.catmullRom)
    }
  }

  @ChartContentBuilder private func uvMarks(_ hour: Forecast.Hour) -> some ChartContent {
    if let uv = hour.uvIndex {
      BarMark(x: .value("Hour", hour.time, unit: .hour), y: .value("UV", uv), width: .ratio(0.8))
        .foregroundStyle(metric.tint)
    }
  }

  @ChartContentBuilder private func rainMarks(_ hour: Forecast.Hour) -> some ChartContent {
    if let rain = hour.precipitation {
      BarMark(x: .value("Hour", hour.time, unit: .hour), y: .value("Rain", format.rainValue(rain)), width: .ratio(0.8))
        .foregroundStyle(metric.tint)
    }
  }

  @ChartContentBuilder private func humidityMarks(_ hour: Forecast.Hour) -> some ChartContent {
    if let value = hour.humidity {
      LineMark(x: .value("Hour", hour.time), y: .value("Humidity", value), series: .value("S", "a"))
        .foregroundStyle(palette.accent)
        .interpolationMethod(.catmullRom)
    }
  }

  @ChartContentBuilder private func pressureMarks(_ hour: Forecast.Hour) -> some ChartContent {
    if let value = hour.pressure {
      LineMark(
        x: .value("Hour", hour.time), y: .value("Pressure", format.pressureValue(value)), series: .value("S", "a")
      )
      .foregroundStyle(palette.accent)
      .interpolationMethod(.catmullRom)
    }
  }

  @ChartContentBuilder private func cloudMarks(_ hour: Forecast.Hour) -> some ChartContent {
    if let value = hour.cloudCover {
      AreaMark(x: .value("Hour", hour.time), y: .value("Cloud", value))
        .foregroundStyle(metric.tint.opacity(0.4))
        .interpolationMethod(.catmullRom)
    }
  }

  // MARK: All the figures

  private var figures: some View {
    VStack(spacing: 8) {
      ForEach(Array(reader.details(metric, on: day).enumerated()), id: \.offset) { _, row in
        HStack {
          Text(row.label).font(.subheadline)
          Spacer()
          Text(row.value).font(.subheadline.weight(.semibold))
        }
      }
    }
  }
}

/// The hours of daylight as a bar across the day: dark before sunrise and after sunset, light between, with the present time
/// marked when the day is today.
private struct SunStrip: View {
  @Environment(\.palette) private var palette
  let day: Forecast.Day?
  let forecast: Forecast
  let isToday: Bool

  var body: some View {
    let calendar = forecast.calendar
    if let day, let sunrise = day.sunrise, let sunset = day.sunset {
      let start = calendar.startOfDay(for: sunrise)
      let span = 24.0 * 3600
      let rise = sunrise.timeIntervalSince(start) / span
      let set = sunset.timeIntervalSince(start) / span
      let now = Date().timeIntervalSince(start) / span
      VStack(spacing: 4) {
        GeometryReader { proxy in
          let width = proxy.size.width
          ZStack(alignment: .leading) {
            Capsule().fill(Color.indigo.opacity(0.35))
            Capsule().fill(
              LinearGradient(colors: [.orange, .yellow, .orange], startPoint: .leading, endPoint: .trailing)
            )
            .frame(width: max(0, (set - rise) * width))
            .offset(x: rise * width)
            if isToday, now >= 0, now <= 1 {
              Circle().fill(Color.white).frame(width: 12, height: 12).overlay(
                Circle().stroke(palette.accent, lineWidth: 2)
              )
              .offset(x: now * width - 6)
            }
          }
        }
        .frame(height: 14)
        HStack {
          ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
            Text("\(hour)").font(.system(size: 9)).foregroundStyle(.secondary)
            if hour < 24 { Spacer() }
          }
        }
      }
    } else {
      Text("No sunrise or sunset on this day.", tableName: "Weather").font(.footnote).foregroundStyle(.secondary)
    }
  }
}
