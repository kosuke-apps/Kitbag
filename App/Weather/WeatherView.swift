import Charts
import KitbagCore
import SwiftUI

/// The weather tool, built to be read on one screen: now at the top, a strip of days (a week back and ten ahead), a chart
/// of the chosen day, a table of its hours with many measures, and the day's totals.
struct WeatherView: View {
  @Environment(WeatherStore.self) private var store
  @Environment(\.palette) private var palette
  @Environment(\.titleDesign) private var design
  @AppStorage("weather.units") private var unitsRaw = UnitPreference.automatic.rawValue

  @State private var selectedDay: LocalDate?
  @State private var showingPlaces = false
  @State private var metric: WeatherMetric?

  private var units: UnitPreference { UnitPreference(rawValue: unitsRaw) ?? .automatic }
  private var format: WeatherFormat { WeatherFormat(usesUSUnits: units.usesUSUnits) }

  var body: some View {
    NavigationStack {
      Group {
        if let forecast = store.forecast {
          content(forecast)
        } else if store.place == nil && !store.followsLocation {
          ContentUnavailableView {
            Label {
              Text("Choose a place for the weather", tableName: "Weather")
            } icon: {
              Image(systemName: "mappin.and.ellipse")
            }
          } description: {
            Text(
              "Search for a city, or use where your phone is. Kitbag keeps only the place you choose.",
              tableName: "Weather"
            )
          } actions: {
            Button {
              showingPlaces = true
            } label: {
              Text("Choose a place", tableName: "Weather")
            }
            .buttonStyle(.borderedProminent)
          }
        } else if store.phase == .failed {
          ContentUnavailableView {
            Label {
              Text("Could not load the weather", tableName: "Weather")
            } icon: {
              Image(systemName: "cloud.slash")
            }
          } description: {
            Text("Check your connection and try again.", tableName: "Weather")
          } actions: {
            Button {
              Task { await store.refresh(force: true) }
            } label: {
              Text("Try again", tableName: "Weather")
            }
          }
        } else {
          ProgressView().controlSize(.large)
        }
      }
      .themedScreen()
      .navigationTitle(Text("Weather", tableName: "Weather"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) { optionsMenu }
      }
    }
    .sheet(isPresented: $showingPlaces) { PlacePicker() }
    .sheet(item: $metric) { metric in
      if let forecast = store.forecast {
        let calendar = forecast.calendar
        WeatherMetricDetail(
          metric: metric, forecast: forecast, format: format, today: LocalDate(Date(), calendar: calendar),
          day: selectedDay ?? LocalDate(Date(), calendar: calendar))
      }
    }
    .task { await store.refresh() }
  }

  // MARK: Layout

  private func content(_ forecast: Forecast) -> some View {
    let calendar = forecast.calendar
    let now = Date()
    let today = LocalDate(now, calendar: calendar)
    let day = selectedDay ?? today
    let hours = forecast.hours(on: day)
    return ScrollView {
      VStack(spacing: 8) {
        banners
        header(forecast, today: forecast.day(today))
        nowStats(forecast, today: forecast.day(today))
        DayStrip(forecast: forecast, selected: day, today: today, format: format) { selectedDay = $0 }
        VStack(alignment: .leading, spacing: 4) {
          dayHeading(day, today: today, calendar: calendar, isToday: day == today)
          HourChart(hours: hours, forecast: forecast, now: now, isToday: day == today, format: format)
        }
        .themedCard(padding: 10, radius: 16)
        HourlyTable(hours: hours, forecast: forecast, now: now, isToday: day == today, format: format)
          .themedCard(padding: 8, radius: 16)
        daySummary(day, forecast: forecast, today: today)
        footer(forecast)
      }
      .padding(.horizontal, 12)
      .padding(.bottom, 12)
    }
    .refreshable { await store.refresh(force: true) }
  }

  @ViewBuilder private var banners: some View {
    if let reason = store.blocked {
      banner(Text(SubscriptionStore.describe(reason)))
    }
    if store.phase == .failed {
      banner(Text("Could not refresh. Showing the last forecast.", tableName: "Weather"))
    }
    if store.locationFailed {
      banner(
        Text(
          "Your location is not available. Turn on location access in Settings, or choose a place.",
          tableName: "Weather"))
    }
  }

  private func banner(_ message: Text) -> some View {
    message
      .font(.footnote)
      .padding(8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.yellow.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
  }

  // MARK: Now

  /// The place, and the weather now: small, because the rest of the screen needs the room.
  private func header(_ forecast: Forecast, today: Forecast.Day?) -> some View {
    let current = forecast.current
    return HStack(alignment: .center, spacing: 10) {
      WeatherSymbol(kind: current.kind, isDay: current.isDay, size: 34)
      VStack(alignment: .leading, spacing: 0) {
        Text(format.temperature(current.temperature)).font(.system(size: 34, weight: .semibold, design: design))
        Text(current.kind.title).font(.footnote.weight(.medium))
      }
      VStack(alignment: .leading, spacing: 1) {
        if let today {
          Text(
            "H \(format.temperature(today.maxTemperature))  L \(format.temperature(today.minTemperature))",
            tableName: "Weather")
        }
        Text("Feels like \(format.temperature(current.apparentTemperature))", tableName: "Weather")
          .foregroundStyle(.secondary)
      }
      .font(.footnote)
      Spacer(minLength: 4)
      Button {
        showingPlaces = true
      } label: {
        VStack(alignment: .trailing, spacing: 1) {
          HStack(spacing: 4) {
            if store.followsLocation { Image(systemName: "location.fill").font(.caption2) }
            Text(forecast.place.name).font(.subheadline.weight(.semibold)).lineLimit(1)
            Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
          }
          if !forecast.place.detail.isEmpty {
            Text(forecast.place.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
          }
        }
        .foregroundStyle(.primary)
      }
      .buttonStyle(.plain)
    }
    .padding(.top, 2)
    .accessibilityElement(children: .combine)
  }

  /// Now, in small figures: wind, gusts, humidity, pressure, visibility, UV.
  private func nowStats(_ forecast: Forecast, today: Forecast.Day?) -> some View {
    let current = forecast.current
    let hour = forecast.hours(from: Date(), count: 1).first
    let columns = Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .leading), count: 3)
    return LazyVGrid(columns: columns, spacing: 4) {
      stat("wind", "\(format.wind(current.windSpeed)) \(WeatherFormat.compass(current.windDirection))")
      stat("gauge.with.dots.needle.bottom.50percent", format.pressure(current.pressure))
      stat("humidity", format.percent(current.humidity))
      stat("wind.snow", current.windGusts.map { format.wind($0) } ?? "–")
      stat("eye", hour?.visibility.map { format.distance(metres: $0) } ?? "–")
      stat("sun.max", (hour?.uvIndex ?? today?.uvIndexMax).map { "UV \(Int($0.rounded()))" } ?? "–")
    }
    .font(.caption)
    .padding(.horizontal, 2)
  }

  private func stat(_ symbol: String, _ value: String) -> some View {
    HStack(spacing: 4) {
      Image(systemName: symbol).foregroundStyle(palette.heading).frame(width: 14)
      Text(value).lineLimit(1).minimumScaleFactor(0.8)
    }
  }

  // MARK: Day

  private func dayHeading(_ day: LocalDate, today: LocalDate, calendar: Calendar, isToday: Bool) -> some View {
    HStack {
      Text(day.date(calendar: .current), format: .dateTime.weekday(.wide).month(.abbreviated).day())
        .font(.footnote.weight(.semibold))
      if day < today {
        Text("Past", tableName: "Weather")
          .font(.caption2.weight(.bold))
          .padding(.horizontal, 6)
          .padding(.vertical, 1)
          .background(Color.secondary.opacity(0.2), in: Capsule())
      }
      Spacer()
      HStack(spacing: 8) {
        Label {
          Text("Temp", tableName: "Weather")
        } icon: {
          Capsule().fill(palette.accent).frame(width: 12, height: 3)
        }
        Label {
          Text("Feels like", tableName: "Weather")
        } icon: {
          Capsule().fill(Color.secondary).frame(width: 12, height: 1.5).mask(
            HStack(spacing: 2) { ForEach(0..<3, id: \.self) { _ in Rectangle().frame(width: 3) } })
        }
        Label {
          Text("Rain %", tableName: "Weather")
        } icon: {
          RoundedRectangle(cornerRadius: 1).fill(Color.cyan.opacity(0.5)).frame(width: 8, height: 8)
        }
        if isToday {
          Label {
            Text("Now", tableName: "Weather")
          } icon: {
            Circle().fill(palette.accent).frame(width: 7, height: 7)
          }
        }
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
  }

  /// The chosen day's figures, one tile for each measure; a tile opens that measure across all the days.
  private func daySummary(_ day: LocalDate, forecast: Forecast, today: LocalDate) -> some View {
    let reader = MetricReader(forecast: forecast, format: format)
    let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
    let name =
      day == today
      ? L10n.string("Today", table: "Weather")
      : day.date(calendar: forecast.calendar).formatted(
        .dateTime.weekday(.wide).month(.abbreviated).day().locale(LanguageStore.shared.locale))
    return VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        Text(name).font(.caption.weight(.semibold))
        Text("Tap a figure for every day", tableName: "Weather").font(.caption2).foregroundStyle(.secondary)
      }
      .padding(.horizontal, 2)
      LazyVGrid(columns: columns, spacing: 6) {
        ForEach(WeatherMetric.allCases) { metric in
          tile(metric, reader.reading(metric, on: day), unit: reader.unit(metric))
        }
      }
    }
  }

  private func tile(_ metric: WeatherMetric, _ reading: MetricReading, unit: String) -> some View {
    Button {
      self.metric = metric
    } label: {
      VStack(spacing: 1) {
        Image(systemName: metric.symbol).font(.caption).foregroundStyle(metric.tint)
        HStack(alignment: .firstTextBaseline, spacing: 1) {
          Text(reading.text).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.6)
          if !unit.isEmpty, reading.value != nil { Text(unit).font(.system(size: 8)).foregroundStyle(.secondary) }
        }
        Text(reading.detail ?? " ").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(
          0.6)
      }
      .frame(maxWidth: .infinity)
      .themedCard(padding: 6, radius: 12)
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityHint(Text("Shows this figure for every day", tableName: "Weather"))
  }

  private func footer(_ forecast: Forecast) -> some View {
    HStack(spacing: 4) {
      Text("Updated \(forecast.fetchedAt.formattedInLanguage(date: .omitted, time: .shortened))", tableName: "Weather")
      Text("·")
      Link(destination: URL(string: "https://open-meteo.com/")!) {
        Text("Weather data by Open-Meteo.com", tableName: "Weather")
      }
      Text("·")
      Link(destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!) { Text("CC BY 4.0") }
    }
    .font(.caption2)
    .foregroundStyle(.secondary)
    .lineLimit(1)
    .minimumScaleFactor(0.7)
  }

  private var optionsMenu: some View {
    Menu {
      Button {
        showingPlaces = true
      } label: {
        Label {
          Text("Change location…", tableName: "Weather")
        } icon: {
          Image(systemName: "mappin.and.ellipse")
        }
      }
      Button {
        Task { await store.followLocation() }
      } label: {
        Label {
          Text("Use my location", tableName: "Weather")
        } icon: {
          Image(systemName: "location")
        }
      }
      Picker(selection: $unitsRaw) {
        ForEach(UnitPreference.allCases, id: \.rawValue) { unit in
          Text(unit.title).tag(unit.rawValue)
        }
      } label: {
        Text("Units", tableName: "Weather")
      }
    } label: {
      Image(systemName: "ellipsis.circle")
    }
    .accessibilityLabel(Text("Weather options", tableName: "Weather"))
  }
}

// MARK: - Days

/// A scrolling strip of days, a week back to ten ahead: pick one to see its hours below.
private struct DayStrip: View {
  @Environment(\.palette) private var palette
  let forecast: Forecast
  let selected: LocalDate
  let today: LocalDate
  let format: WeatherFormat
  let select: (LocalDate) -> Void

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 6) {
          ForEach(forecast.daily) { day in
            Button {
              select(day.date)
            } label: {
              chip(day)
            }
            .buttonStyle(.plain)
            .id(day.date)
          }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
      }
      .onAppear { proxy.scrollTo(selected, anchor: .center) }
    }
  }

  private func chip(_ day: Forecast.Day) -> some View {
    let isSelected = day.date == selected
    let isPast = day.date < today
    return VStack(spacing: 1) {
      Text(
        day.date == today
          ? L10n.string("Today", table: "Weather")
          : day.date.date(calendar: .current).formatted(
            .dateTime.weekday(.abbreviated).locale(LanguageStore.shared.locale))
      )
      .font(.system(size: 10, weight: day == forecast.day(today) ? .bold : .medium))
      .lineLimit(1)
      .minimumScaleFactor(0.7)
      Text(day.date.date(calendar: .current), format: .dateTime.day())
        .font(.system(size: 13, weight: .semibold))
      WeatherSymbol(kind: day.kind, isDay: true, size: 15).frame(height: 18)
      Text(format.temperature(day.maxTemperature)).font(.system(size: 11, weight: .semibold))
      Text(format.temperature(day.minTemperature)).font(.system(size: 10)).foregroundStyle(.secondary)
    }
    .frame(width: 44)
    .padding(.vertical, 5)
    .background(
      isSelected ? palette.accent.opacity(0.22) : palette.card,
      in: RoundedRectangle(cornerRadius: 12, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(isSelected ? palette.accent : palette.cardStroke, lineWidth: isSelected ? 1.5 : 0.75)
    )
    .opacity(isPast && !isSelected ? 0.65 : 1)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

extension Forecast.Day {
  fileprivate static func == (lhs: Forecast.Day?, rhs: Forecast.Day) -> Bool { lhs?.date == rhs.date }
}

// MARK: - Chart

/// The day's temperature and feels-like lines over bars for the chance of rain. Touch and drag across it to read the hour under
/// the finger; the present time is a dot on the temperature line and a faint dashed line.
private struct HourChart: View {
  @Environment(\.palette) private var palette
  let hours: [Forecast.Hour]
  let forecast: Forecast
  let now: Date
  let isToday: Bool
  let format: WeatherFormat

  @State private var picked: Date?
  /// The last moment that was touched. It stays after the finger lifts, so that the figures can be read; tap them to clear.
  @State private var held: Date?

  private var zone: TimeZone { TimeZone(identifier: forecast.timeZoneID) ?? .current }

  /// The hour nearest to where the finger is.
  private var selected: Forecast.Hour? {
    guard let held else { return nil }
    return hours.min { abs($0.time.timeIntervalSince(held)) < abs($1.time.timeIntervalSince(held)) }
  }

  var body: some View {
    let temps =
      hours.map { format.temperatureValue($0.temperature) }
      + hours.map { format.temperatureValue($0.apparentTemperature) }
    let low = (temps.min() ?? 0).rounded(.down) - 1
    let high = (temps.max() ?? 1).rounded(.up) + 1
    let rainTop = low + (high - low) * 0.38
    let current = isToday ? hours.first { $0.time <= now && now < $0.time.addingTimeInterval(3600) } : nil
    VStack(alignment: .leading, spacing: 2) {
      readout
      Chart {
        ForEach(hours) { hour in
          if let chance = hour.precipitationProbability {
            BarMark(
              x: .value("Hour", hour.time, unit: .hour), yStart: .value("Base", low),
              yEnd: .value("Rain", low + (rainTop - low) * chance / 100), width: .ratio(0.8)
            )
            .foregroundStyle(Color.cyan.opacity(0.4))
          }
          LineMark(
            x: .value("Hour", hour.time), y: .value("Feels like", format.temperatureValue(hour.apparentTemperature)),
            series: .value("Series", "feels")
          )
          .foregroundStyle(Color.secondary)
          .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
          .interpolationMethod(.catmullRom)
          LineMark(
            x: .value("Hour", hour.time), y: .value("Temperature", format.temperatureValue(hour.temperature)),
            series: .value("Series", "temp")
          )
          .foregroundStyle(palette.accent)
          .lineStyle(StrokeStyle(lineWidth: 2))
          .interpolationMethod(.catmullRom)
        }
        if let current {
          RuleMark(x: .value("Now", current.time))
            .foregroundStyle(palette.accent.opacity(0.35))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
          PointMark(
            x: .value("Now", current.time), y: .value("Temperature", format.temperatureValue(current.temperature))
          )
          .symbolSize(46)
          .foregroundStyle(palette.accent)
        }
        if let selected {
          RuleMark(x: .value("Selected", selected.time))
            .foregroundStyle(Color.primary.opacity(0.5))
            .lineStyle(StrokeStyle(lineWidth: 1))
          PointMark(
            x: .value("Selected", selected.time),
            y: .value("Temperature", format.temperatureValue(selected.temperature))
          )
          .symbolSize(60)
          .foregroundStyle(Color.primary)
        }
      }
      .chartYScale(domain: low...high)
      .chartXSelection(value: $picked)
      .onChange(of: picked) { _, new in if let new { held = new } }
      .onChange(of: hours.first?.time) { _, _ in held = nil }
      .chartXAxis {
        AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
          AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
          AxisValueLabel(format: Date.FormatStyle(timeZone: zone).hour(), centered: false)
        }
      }
      .chartYAxis {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
          AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
          AxisValueLabel()
        }
      }
      .font(.caption2)
      .frame(height: 104)
      .accessibilityLabel(Text("Chart of the day's temperature and chance of rain", tableName: "Weather"))
    }
  }

  /// What the hour under the finger says, or a hint to touch the chart.
  @ViewBuilder private var readout: some View {
    if let hour = selected {
      HStack(spacing: 8) {
        Text(hour.time, format: Date.FormatStyle(timeZone: zone).hour().minute().locale(LanguageStore.shared.locale))
          .font(.caption.weight(.bold))
        Text(format.temperature(hour.temperature)).font(.caption.weight(.semibold))
        Text("Feels \(format.temperature(hour.apparentTemperature))", tableName: "Weather").font(.caption2)
          .foregroundStyle(
            .secondary)
        if let chance = hour.precipitationProbability {
          Text("Rain \(format.percent(chance))", tableName: "Weather").font(.caption2).foregroundStyle(.secondary)
        }
        Text(format.wind(hour.windSpeed)).font(.caption2).foregroundStyle(.secondary)
        Spacer(minLength: 0)
        Image(systemName: "xmark.circle.fill").font(.caption2).foregroundStyle(.tertiary)
      }
      .lineLimit(1)
      .minimumScaleFactor(0.7)
      .frame(height: 16)
      .contentShape(Rectangle())
      .onTapGesture { held = nil }
    } else {
      Text("Touch the chart to read an hour", tableName: "Weather")
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .frame(height: 16, alignment: .leading)
    }
  }
}

// MARK: - Table

/// One row of the hourly table.
private enum HourlyRow: CaseIterable {
  case time
  case sky
  case temperature
  case feelsLike
  case rainChance
  case rain
  case wind
  case gusts
  case humidity
  case cloud
  case uv
  case pressure

  var height: CGFloat {
    switch self {
    case .sky: 24
    default: 19
    }
  }

  var title: LocalizedStringResource {
    switch self {
    case .time: LocalizedStringResource("Time", table: "Weather")
    case .sky: LocalizedStringResource("Sky", table: "Weather")
    case .temperature: LocalizedStringResource("Temp", table: "Weather")
    case .feelsLike: LocalizedStringResource("Feels", table: "Weather")
    case .rainChance: LocalizedStringResource("Rain %", table: "Weather")
    case .rain: LocalizedStringResource("Precip.", table: "Weather")
    case .wind: LocalizedStringResource("Wind", table: "Weather")
    case .gusts: LocalizedStringResource("Gusts", table: "Weather")
    case .humidity: LocalizedStringResource("Humidity", table: "Weather")
    case .cloud: LocalizedStringResource("Cloud", table: "Weather")
    case .uv: LocalizedStringResource("UV", table: "Weather")
    case .pressure: LocalizedStringResource("Pressure", table: "Weather")
    }
  }

  func unit(_ format: WeatherFormat) -> String? {
    switch self {
    case .rain: format.rainUnit
    case .wind, .gusts: format.windUnit
    case .pressure: format.pressureUnit
    case .temperature, .feelsLike: format.usesUSUnits ? "°F" : "°C"
    default: nil
    }
  }
}

/// The hours of a day as columns and the measures as rows (a spreadsheet you scroll sideways), with the rows named on the
/// left. The hour that is now is outlined; past hours are dimmed.
private struct HourlyTable: View {
  @Environment(\.palette) private var palette
  let hours: [Forecast.Hour]
  let forecast: Forecast
  let now: Date
  let isToday: Bool
  let format: WeatherFormat

  private let columnWidth: CGFloat = 46

  var body: some View {
    HStack(alignment: .top, spacing: 4) {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(HourlyRow.allCases, id: \.self) { row in
          HStack(spacing: 2) {
            Text(row.title).font(.system(size: 10, weight: .medium))
            if let unit = row.unit(format) { Text(unit).font(.system(size: 8)).foregroundStyle(.tertiary) }
          }
          .lineLimit(1)
          .minimumScaleFactor(0.7)
          .frame(width: 58, height: row.height, alignment: .leading)
        }
      }
      ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 0) {
            ForEach(hours) { hour in
              column(hour).id(hour.time)
            }
          }
        }
        .onAppear { scrollToStart(proxy) }
        .onChange(of: hours.first?.time) { _, _ in scrollToStart(proxy) }
      }
    }
  }

  private func scrollToStart(_ proxy: ScrollViewProxy) {
    let calendar = forecast.calendar
    let target =
      isToday
      ? hours.first { $0.time.addingTimeInterval(3600) > now }
      : hours.first { calendar.component(.hour, from: $0.time) == 6 }
    if let target { proxy.scrollTo(target.time, anchor: isToday ? .center : .leading) }
  }

  private func column(_ hour: Forecast.Hour) -> some View {
    let zone = TimeZone(identifier: forecast.timeZoneID) ?? .current
    let isNow = isToday && hour.time <= now && now < hour.time.addingTimeInterval(3600)
    let isPast = hour.time.addingTimeInterval(3600) <= now
    return VStack(spacing: 0) {
      ForEach(HourlyRow.allCases, id: \.self) { row in
        cell(row, hour, zone: zone)
          .frame(width: columnWidth, height: row.height)
          .background(tint(row, hour))
      }
    }
    .opacity(isPast ? 0.6 : 1)
    .background {
      if isNow { RoundedRectangle(cornerRadius: 5).fill(palette.accent.opacity(0.16)) }
    }
    .overlay {
      if isNow { RoundedRectangle(cornerRadius: 5).strokeBorder(palette.accent.opacity(0.55), lineWidth: 1) }
    }
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder private func cell(_ row: HourlyRow, _ hour: Forecast.Hour, zone: TimeZone) -> some View {
    switch row {
    case .time:
      Text(hour.time, format: Date.FormatStyle(timeZone: zone).hour()).font(.system(size: 11, weight: .semibold))
    case .sky:
      WeatherSymbol(kind: hour.kind, isDay: hour.isDay, size: 15)
    case .temperature:
      Text("\(Int(format.temperatureValue(hour.temperature).rounded()))°").font(.system(size: 12, weight: .semibold))
    case .feelsLike:
      Text("\(Int(format.temperatureValue(hour.apparentTemperature).rounded()))°").font(.system(size: 11))
        .foregroundStyle(.secondary)
    case .rainChance:
      text(hour.precipitationProbability.map { "\(Int($0.rounded()))" })
    case .rain:
      text(hour.precipitation.map { $0 < 0.05 ? "–" : String(format: "%.1f", format.rainValue($0)) })
    case .wind:
      HStack(spacing: 1) {
        if let direction = hour.windDirection {
          Image(systemName: "location.north.fill").font(.system(size: 7)).rotationEffect(.degrees(direction + 180))
        }
        Text("\(Int(format.windValue(hour.windSpeed).rounded()))").font(.system(size: 11))
      }
    case .gusts:
      text(hour.windGusts.map { "\(Int(format.windValue($0).rounded()))" })
    case .humidity:
      text(hour.humidity.map { "\(Int($0.rounded()))" })
    case .cloud:
      text(hour.cloudCover.map { "\(Int($0.rounded()))" })
    case .uv:
      text(hour.uvIndex.map { $0 < 0.5 ? "–" : "\(Int($0.rounded()))" })
    case .pressure:
      text(
        hour.pressure.map {
          format.usesUSUnits
            ? String(format: "%.2f", format.pressureValue($0)) : "\(Int(format.pressureValue($0).rounded()))"
        })
    }
  }

  private func text(_ value: String?) -> some View {
    Text(value ?? "–").font(.system(size: 11)).foregroundStyle(
      value == nil || value == "–" ? Color.secondary.opacity(0.5) : Color.primary)
  }

  /// A faint colour behind a cell that grows with the value, so that the table can be read at a glance.
  private func tint(_ row: HourlyRow, _ hour: Forecast.Hour) -> Color {
    func level(_ value: Double?, max: Double) -> Double { min(Swift.max((value ?? 0) / max, 0), 1) }
    switch row {
    case .temperature:
      let t = min(max((hour.temperature + 10) / 45, 0), 1)
      return Color(hue: 0.62 - 0.62 * t, saturation: 0.55, brightness: 0.95).opacity(0.28)
    case .rainChance: return Color.cyan.opacity(0.06 + 0.4 * level(hour.precipitationProbability, max: 100))
    case .rain: return Color.cyan.opacity(0.4 * level(hour.precipitation, max: 3))
    case .wind: return Color.teal.opacity(0.05 + 0.3 * level(hour.windSpeed, max: 50))
    case .gusts: return Color.teal.opacity(0.05 + 0.3 * level(hour.windGusts, max: 70))
    case .humidity: return Color.blue.opacity(0.03 + 0.18 * level(hour.humidity, max: 100))
    case .cloud: return Color.gray.opacity(0.03 + 0.25 * level(hour.cloudCover, max: 100))
    case .uv: return Color.orange.opacity(0.4 * level(hour.uvIndex, max: 11))
    default: return Color.clear
    }
  }
}
