import KitbagCore
import SwiftUI

/// Chooses the place to show the weather for: the phone's location, or a place found by name.
struct PlacePicker: View {
  @Environment(WeatherStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  @State private var query = ""
  @State private var results: [Place] = []
  @State private var searched = false
  @State private var searching = false

  var body: some View {
    NavigationStack {
      List {
        Section {
          Button {
            Task {
              await store.followLocation()
              dismiss()
            }
          } label: {
            Label {
              Text("Use my location", tableName: "Weather")
            } icon: {
              Image(systemName: "location.fill")
            }
          }
          Button {
            Task {
              await store.choose(.madison)
              dismiss()
            }
          } label: {
            Label {
              Text("Madison, Wisconsin", tableName: "Weather")
            } icon: {
              Image(systemName: "mappin")
            }
          }
        }
        if searching {
          ProgressView().frame(maxWidth: .infinity)
        } else if searched && results.isEmpty {
          Text("No places found.", tableName: "Weather").foregroundStyle(.secondary)
        }
        Section {
          ForEach(Array(results.enumerated()), id: \.offset) { _, place in
            Button {
              Task {
                await store.choose(place)
                dismiss()
              }
            } label: {
              VStack(alignment: .leading, spacing: 2) {
                Text(place.name).foregroundStyle(.primary)
                if !place.detail.isEmpty { Text(place.detail).font(.footnote).foregroundStyle(.secondary) }
              }
            }
          }
        }
      }
      .searchable(text: $query, prompt: Text("Search for a city", tableName: "Weather"))
      .onSubmit(of: .search) {
        Task {
          searching = true
          results = await store.search(query)
          searched = true
          searching = false
        }
      }
      .navigationTitle(Text("Location", tableName: "Weather"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button {
            dismiss()
          } label: {
            Text("Done", tableName: "Weather")
          }
        }
      }
    }
  }
}

/// The weather on the Today screen: now, today's range, and the place.
struct WeatherCard: View {
  let forecast: Forecast
  @AppStorage("weather.units") private var unitsRaw = UnitPreference.automatic.rawValue

  var body: some View {
    let format = WeatherFormat(usesUSUnits: (UnitPreference(rawValue: unitsRaw) ?? .automatic).usesUSUnits)
    let today = forecast.today(at: Date()) ?? forecast.daily.first
    HStack(spacing: 12) {
      WeatherSymbol(kind: forecast.current.kind, isDay: forecast.current.isDay, size: 34)
      VStack(alignment: .leading, spacing: 1) {
        Text(format.temperature(forecast.current.temperature)).font(.title2.weight(.semibold))
        Text(forecast.current.kind.title).font(.footnote).foregroundStyle(.secondary)
      }
      Spacer(minLength: 8)
      VStack(alignment: .trailing, spacing: 1) {
        if let today {
          Text(
            "H \(format.temperature(today.maxTemperature))  L \(format.temperature(today.minTemperature))",
            tableName: "Weather"
          )
          .font(.subheadline)
          if let chance = today.precipitationProbability, chance >= 10 {
            Label(format.percent(chance), systemImage: "drop.fill")
              .font(.footnote)
              .foregroundStyle(Color.cyan)
          }
        }
        Text(forecast.place.name).font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .accessibilityElement(children: .combine)
  }
}
