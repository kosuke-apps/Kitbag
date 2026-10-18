import KitbagCore
import SwiftUI

/// The weather tool: everything on one screen. Now, the hours ahead, the days ahead, and the details.
struct WeatherView: View {
  @Environment(WeatherStore.self) private var store
  @AppStorage("weather.units") private var unitsRaw = UnitPreference.automatic.rawValue
  @State private var showingPlaces = false

  private var units: UnitPreference { UnitPreference(rawValue: unitsRaw) ?? .automatic }
  private var format: WeatherFormat { WeatherFormat(usesUSUnits: units.usesUSUnits) }

  var body: some View {
    NavigationStack {
      Group {
        if let forecast = store.forecast {
          content(forecast)
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
      .navigationTitle(Text("Weather", tableName: "Weather"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) { optionsMenu }
      }
    }
    .sheet(isPresented: $showingPlaces) { PlacePicker() }
    .task { await store.refresh() }
  }

  // MARK: Sections

  private func content(_ forecast: Forecast) -> some View {
    let now = Date()
    let today = forecast.today(at: now) ?? forecast.daily.first
    let hours = forecast.hours(from: now, count: 24)
    return ScrollView {
      VStack(spacing: 14) {
        banners
        header(forecast, today: today)
        card(Text("Hourly forecast", tableName: "Weather")) { hourly(hours, forecast: forecast) }
        card(Text("Daily forecast", tableName: "Weather")) { daily(forecast) }
        details(forecast, today: today, hours: hours)
        footer(forecast)
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 24)
    }
    .refreshable { await store.refresh(force: true) }
  }

  @ViewBuilder private var banners: some View {
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
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.yellow.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
  }

  private func header(_ forecast: Forecast, today: Forecast.Day?) -> some View {
    let current = forecast.current
    return VStack(spacing: 4) {
      Button {
        showingPlaces = true
      } label: {
        HStack(spacing: 6) {
          if store.followsLocation { Image(systemName: "location.fill").font(.footnote) }
          Text(forecast.place.name).font(.title2.weight(.semibold))
          Image(systemName: "chevron.down").font(.footnote.weight(.semibold))
        }
      }
      .buttonStyle(.plain)
      if !forecast.place.detail.isEmpty {
        Text(forecast.place.detail).font(.footnote).foregroundStyle(.secondary)
      }
      HStack(spacing: 14) {
        WeatherSymbol(kind: current.kind, isDay: current.isDay, size: 54)
        Text(format.temperature(current.temperature)).font(.system(size: 76, weight: .thin))
      }
      .padding(.top, 6)
      Text(current.kind.title).font(.title3)
      HStack(spacing: 14) {
        if let today {
          Text("H \(format.temperature(today.maxTemperature))", tableName: "Weather")
          Text("L \(format.temperature(today.minTemperature))", tableName: "Weather")
        }
        Text("Feels like \(format.temperature(current.apparentTemperature))", tableName: "Weather")
      }
      .font(.subheadline)
      .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 4)
    .accessibilityElement(children: .combine)
  }

  private func hourly(_ hours: [Forecast.Hour], forecast: Forecast) -> some View {
    let zone = TimeZone(identifier: forecast.timeZoneID) ?? .current
    return ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 18) {
        ForEach(Array(hours.enumerated()), id: \.element.id) { index, hour in
          VStack(spacing: 6) {
            if index == 0 {
              Text("Now", tableName: "Weather").font(.footnote.weight(.semibold))
            } else {
              Text(hour.time, format: Date.FormatStyle(timeZone: zone).hour()).font(.footnote)
            }
            WeatherSymbol(kind: hour.kind, isDay: hour.isDay, size: 22).frame(height: 26)
            Text(format.temperature(hour.temperature)).font(.subheadline.weight(.medium))
            if let chance = hour.precipitationProbability, chance >= 10 {
              Text(format.percent(chance)).font(.caption2).foregroundStyle(Color.cyan)
            } else {
              Text(" ").font(.caption2)
            }
          }
          .frame(minWidth: 40)
          .accessibilityElement(children: .combine)
        }
      }
      .padding(.vertical, 4)
    }
  }

  private func daily(_ forecast: Forecast) -> some View {
    let low = forecast.daily.map(\.minTemperature).min() ?? 0
    let high = forecast.daily.map(\.maxTemperature).max() ?? 1
    return VStack(spacing: 10) {
      ForEach(Array(forecast.daily.enumerated()), id: \.element.id) { index, day in
        HStack(spacing: 8) {
          Group {
            if index == 0 {
              Text("Today", tableName: "Weather")
            } else {
              Text(day.date.date(calendar: .current), format: .dateTime.weekday(.abbreviated))
            }
          }
          .font(.subheadline)
          .frame(width: 54, alignment: .leading)
          WeatherSymbol(kind: day.kind, isDay: true, size: 20).frame(width: 28)
          Group {
            if let chance = day.precipitationProbability, chance >= 10 {
              Text(format.percent(chance)).foregroundStyle(Color.cyan)
            } else {
              Text("")
            }
          }
          .font(.caption2)
          .frame(width: 34, alignment: .leading)
          Text(format.temperature(day.minTemperature)).foregroundStyle(.secondary).frame(
            width: 36, alignment: .trailing)
          TemperatureBar(
            minimum: day.minTemperature, maximum: day.maxTemperature, weekMinimum: low, weekMaximum: high)
          Text(format.temperature(day.maxTemperature)).frame(width: 36, alignment: .leading)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
      }
    }
  }

  private func details(_ forecast: Forecast, today: Forecast.Day?, hours: [Forecast.Hour]) -> some View {
    let current = forecast.current
    let zone = TimeZone(identifier: forecast.timeZoneID) ?? .current
    let timeStyle = Date.FormatStyle(timeZone: zone).hour().minute()
    return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
      tile(Text("Wind", tableName: "Weather"), systemImage: "wind") {
        Text("\(format.wind(current.windSpeed)) \(WeatherFormat.compass(current.windDirection))")
        if let gusts = current.windGusts { Text("Gusts \(format.wind(gusts))", tableName: "Weather").detail() }
      }
      tile(Text("Humidity", tableName: "Weather"), systemImage: "humidity") {
        Text(format.percent(current.humidity))
      }
      if let uv = today?.uvIndexMax {
        tile(Text("UV index", tableName: "Weather"), systemImage: "sun.max") {
          Text("\(Int(uv.rounded()))")
          Text(uvLevel(uv)).detail()
        }
      }
      tile(Text("Pressure", tableName: "Weather"), systemImage: "gauge.with.dots.needle.bottom.50percent") {
        Text(format.pressure(current.pressure))
      }
      if let visibility = hours.first?.visibility {
        tile(Text("Visibility", tableName: "Weather"), systemImage: "eye") {
          Text(format.distance(metres: visibility))
        }
      }
      if let today {
        tile(Text("Precipitation", tableName: "Weather"), systemImage: "drop") {
          Text(today.precipitationProbability.map { format.percent($0) } ?? "–")
          if let sum = today.precipitationSum {
            Text("Today \(format.rainfall(millimetres: sum))", tableName: "Weather").detail()
          }
        }
        if let sunrise = today.sunrise, let sunset = today.sunset {
          tile(Text("Sun", tableName: "Weather"), systemImage: "sunrise") {
            Text(sunrise, format: timeStyle)
            Text("Sunset \(sunset.formatted(timeStyle))", tableName: "Weather").detail()
          }
        }
      }
    }
  }

  private func uvLevel(_ index: Double) -> LocalizedStringResource {
    switch index {
    case ..<3: LocalizedStringResource("Low", table: "Weather")
    case ..<6: LocalizedStringResource("Moderate", table: "Weather")
    case ..<8: LocalizedStringResource("High", table: "Weather")
    case ..<11: LocalizedStringResource("Very high", table: "Weather")
    default: LocalizedStringResource("Extreme", table: "Weather")
    }
  }

  private func footer(_ forecast: Forecast) -> some View {
    VStack(spacing: 4) {
      Text("Updated \(forecast.fetchedAt.formatted(date: .omitted, time: .shortened))", tableName: "Weather")
      HStack(spacing: 4) {
        Link(destination: URL(string: "https://open-meteo.com/")!) {
          Text("Weather data by Open-Meteo.com", tableName: "Weather")
        }
        Text("·")
        Link(destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!) { Text("CC BY 4.0") }
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .padding(.top, 4)
  }

  // MARK: Pieces

  private func card<Content: View>(_ title: Text, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      title.font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
      content()
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }

  private func tile<Content: View>(
    _ title: Text, systemImage: String, @ViewBuilder content: () -> Content
  )
    -> some View
  {
    VStack(alignment: .leading, spacing: 6) {
      Label {
        title
      } icon: {
        Image(systemName: systemImage)
      }
      .font(.footnote.weight(.semibold))
      .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 2) {
        content()
      }
      .font(.title3.weight(.medium))
    }
    .padding(14)
    .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .accessibilityElement(children: .combine)
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

extension Text {
  fileprivate func detail() -> some View {
    font(.footnote).foregroundStyle(.secondary)
  }
}

/// A bar from the day's low to its high, placed within the week's range.
private struct TemperatureBar: View {
  let minimum: Double
  let maximum: Double
  let weekMinimum: Double
  let weekMaximum: Double

  var body: some View {
    GeometryReader { proxy in
      let span = max(weekMaximum - weekMinimum, 1)
      let start = (minimum - weekMinimum) / span
      let end = (maximum - weekMinimum) / span
      ZStack(alignment: .leading) {
        Capsule().fill(Color.secondary.opacity(0.25))
        Capsule()
          .fill(LinearGradient(colors: [.cyan, .yellow, .orange], startPoint: .leading, endPoint: .trailing))
          .frame(width: max(proxy.size.width * (end - start), 6))
          .offset(x: proxy.size.width * start)
      }
    }
    .frame(height: 5)
  }
}
