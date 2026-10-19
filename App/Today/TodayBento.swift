import KitbagCore
import SwiftUI

/// Tiles of different sizes: the weather and the next class side by side, the rest across the width, pinned notes two to a
/// row. The parts keep the order the person chose; two neighbours that are tiles share a row, and one on its own spreads out.
struct TodayBento: View {
  @Environment(LayoutStore.self) private var layout
  @Environment(\.kitbagStyle) private var style
  let model: TodayModel
  let open: (ModuleRoute) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: style.sectionSpacing) {
      ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
        if row.count == 2 {
          HStack(alignment: .top, spacing: style.sectionSpacing) {
            ForEach(row) { tile($0) }
          }
          .fixedSize(horizontal: false, vertical: true)
        } else if let only = row.first {
          wide(only)
        }
      }
    }
  }

  /// The parts to show, in rows of one or two.
  private var rows: [[TodaySection]] {
    var rows: [[TodaySection]] = []
    for section in layout.visibleSections.filter(model.hasContent) {
      if Self.isTile(section), var last = rows.last, last.count == 1, Self.isTile(last[0]) {
        last.append(section)
        rows[rows.count - 1] = last
      } else {
        rows.append([section])
      }
    }
    return rows
  }

  private static func isTile(_ section: TodaySection) -> Bool { section == .weather || section == .nextClass }

  @ViewBuilder private func tile(_ section: TodaySection) -> some View {
    switch section {
    case .weather:
      if let forecast = model.forecast {
        Button {
          open(ModuleRoute(.weather))
        } label: {
          BentoWeatherTile(forecast: forecast)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    case .nextClass:
      NextClassButton(model: model, open: open, shape: .tile)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    default: EmptyView()
    }
  }

  @ViewBuilder private func wide(_ section: TodaySection) -> some View {
    switch section {
    case .weather: WeatherButton(model: model, open: open)
    case .nextClass: NextClassButton(model: model, open: open, shape: .wide)
    case .todaysClasses:
      VStack(alignment: .leading, spacing: 10) {
        SectionHeading(Text("Today", tableName: "Today"))
        TodaysClassesLines(model: model)
      }
      .themedCard()
    case .dueSoon:
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          SectionHeading(Text("Due soon", tableName: "Today"))
          Spacer()
          if !model.overdue.isEmpty { CountBadge(count: model.overdue.count) }
        }
        DueSoonLines(model: model, open: open)
      }
      .themedCard()
    case .pinnedNotes:
      LazyVGrid(
        columns: [GridItem(.flexible(), spacing: style.sectionSpacing), GridItem(.flexible())],
        spacing: style.sectionSpacing
      ) {
        ForEach(model.pinned) { note in
          Button {
            open(ModuleRoute(.notes, noteID: note.id))
          } label: {
            PinnedNoteCard(note: note, lines: 3, fillsHeight: true)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }
}

/// A small red number for what is overdue.
private struct CountBadge: View {
  let count: Int

  var body: some View {
    Text("\(count)")
      .font(.caption.weight(.bold))
      .foregroundStyle(.white)
      .padding(.horizontal, 8)
      .padding(.vertical, 2)
      .background(Color.red, in: Capsule())
      .accessibilityLabel(Text("\(count) overdue", tableName: "Today"))
  }
}

/// The weather as a tile: the symbol, a large temperature, today's range and the place.
private struct BentoWeatherTile: View {
  @Environment(\.titleDesign) private var design
  @Environment(\.kitbagStyle) private var style
  let forecast: Forecast
  @AppStorage("weather.units") private var unitsRaw = UnitPreference.automatic.rawValue

  var body: some View {
    let format = WeatherFormat(usesUSUnits: (UnitPreference(rawValue: unitsRaw) ?? .automatic).usesUSUnits)
    let today = forecast.today(at: Date()) ?? forecast.daily.first
    let radius = 22 * style.radiusScale
    VStack(alignment: .leading, spacing: 4) {
      WeatherSymbol(kind: forecast.current.kind, isDay: forecast.current.isDay, size: 30)
      Spacer(minLength: 6)
      Text(format.temperature(forecast.current.temperature))
        .font(.system(size: 38, weight: .semibold, design: design))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      Text(forecast.current.kind.title).font(.footnote).foregroundStyle(.secondary)
      if let today {
        Text(
          "H \(format.temperature(today.maxTemperature))  L \(format.temperature(today.minTemperature))",
          tableName: "Weather"
        )
        .font(.caption.weight(.medium))
        if let chance = today.precipitationProbability, chance >= 10 {
          Label(format.percent(chance), systemImage: "drop.fill")
            .font(.caption)
            .foregroundStyle(Color.cyan)
        }
      }
      Text(forecast.place.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
    }
    .frame(maxHeight: .infinity, alignment: .topLeading)
    .themedCard(padding: 16, radius: 22)
    .background {
      let tint = forecast.current.kind.cardTint(isDay: forecast.current.isDay)
      LinearGradient(
        colors: [tint.opacity(0.32), tint.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing
      )
      .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
    .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    .accessibilityElement(children: .combine)
  }
}
