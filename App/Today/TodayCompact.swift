import KitbagCore
import SwiftUI

/// Today in as little room as possible: the weather and the next class each on one line, the day's lists in small type.
struct TodayCompact: View {
  @Environment(LayoutStore.self) private var layout
  @Environment(\.kitbagStyle) private var style
  let model: TodayModel
  let open: (ModuleRoute) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: style.sectionSpacing) {
      ForEach(layout.visibleSections.filter(model.hasContent)) { section in
        switch section {
        case .weather:
          if let forecast = model.forecast {
            Button {
              open(ModuleRoute(.weather))
            } label: {
              CompactWeatherRow(forecast: forecast)
            }
            .buttonStyle(.plain)
          }
        case .nextClass:
          if model.hasCourses {
            if let upcoming = model.upcoming {
              Button {
                open(ModuleRoute(.timetable))
              } label: {
                CompactNextClassRow(upcoming: upcoming, now: model.now, calendar: model.calendar)
              }
              .buttonStyle(.plain)
            } else {
              Text("No classes in the next week.", tableName: "Today").font(.footnote).foregroundStyle(.secondary)
            }
          }
        case .todaysClasses:
          VStack(alignment: .leading, spacing: 6) {
            SectionHeading(Text("Today", tableName: "Today"))
            TodaysClassesLines(model: model, spacing: 6)
          }
          .themedCard(padding: 12, radius: 16)
        case .dueSoon:
          VStack(alignment: .leading, spacing: 6) {
            SectionHeading(Text("Due soon", tableName: "Today"))
            DueSoonLines(model: model, open: open, spacing: 6)
          }
          .themedCard(padding: 12, radius: 16)
        case .pinnedNotes:
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
              ForEach(model.pinned) { note in
                Button {
                  open(ModuleRoute(.notes, noteID: note.id))
                } label: {
                  Label {
                    Text(note.title.isEmpty ? L10n.string("New note", table: "Notes") : note.title).lineLimit(1)
                  } icon: {
                    Image(systemName: "pin.fill").foregroundStyle(Color.stickyNote)
                  }
                  .font(.footnote.weight(.medium))
                  .padding(.horizontal, 12)
                  .padding(.vertical, 7)
                  .background(.thinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
              }
            }
          }
        }
      }
    }
  }
}

/// "☀ 17° Clear   H 18° L 4°   Madison" on one line.
private struct CompactWeatherRow: View {
  let forecast: Forecast
  @AppStorage("weather.units") private var unitsRaw = UnitPreference.automatic.rawValue

  var body: some View {
    let format = WeatherFormat(usesUSUnits: (UnitPreference(rawValue: unitsRaw) ?? .automatic).usesUSUnits)
    let today = forecast.today(at: Date()) ?? forecast.daily.first
    HStack(spacing: 8) {
      WeatherSymbol(kind: forecast.current.kind, isDay: forecast.current.isDay, size: 22)
      Text(format.temperature(forecast.current.temperature)).font(.headline)
      Text(forecast.current.kind.title).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
      Spacer(minLength: 6)
      if let today {
        Text("H \(format.temperature(today.maxTemperature))  L \(format.temperature(today.minTemperature))", tableName: "Weather")
          .font(.caption)
      }
      Text(forecast.place.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
    }
    .themedCard(padding: 10, radius: 14)
    .accessibilityElement(children: .combine)
  }
}

/// The class on now or next as a single row with a bar in the course's colour.
private struct CompactNextClassRow: View {
  @Environment(\.kitbagStyle) private var style
  let upcoming: Timetable.Upcoming
  let now: Date
  let calendar: Calendar

  var body: some View {
    let slot = upcoming.slot
    let color = slot.course.color.blockColor
    let inProgress = upcoming.isInProgress(at: now)
    VStack(alignment: .leading, spacing: 5) {
      HStack(spacing: 8) {
        RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4, height: 22)
        (inProgress ? Text("Now", tableName: "Today") : Text("Next", tableName: "Today"))
          .font(.caption2.weight(.bold))
          .textCase(.uppercase)
          .foregroundStyle(.secondary)
        Text(slot.course.code).font(.headline).lineLimit(1)
        Text(timeRange).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
        Spacer(minLength: 6)
        timing.font(.caption.weight(.medium)).foregroundStyle(.secondary)
      }
      if !slot.meeting.location.isEmpty {
        Label(slot.meeting.location, systemImage: "mappin.and.ellipse")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .padding(.leading, 12)
      }
      if inProgress {
        ProgressBar(
          fraction: now.timeIntervalSince(upcoming.start) / max(upcoming.end.timeIntervalSince(upcoming.start), 1),
          color: color)
      }
    }
    .themedCard(padding: 10, radius: 14)
    .accessibilityElement(children: .combine)
  }

  private var timeRange: String {
    "\(upcoming.start.formattedInLanguage(date: .omitted, time: .shortened))–\(upcoming.end.formattedInLanguage(date: .omitted, time: .shortened))"
  }

  @ViewBuilder private var timing: some View {
    if upcoming.isInProgress(at: now) {
      Text("until \(upcoming.end.formattedInLanguage(date: .omitted, time: .shortened))", tableName: "Today")
    } else if calendar.isDate(upcoming.start, inSameDayAs: now) {
      Text("in \(Text(upcoming.start, style: .relative))", tableName: "Today")
    } else {
      Text(upcoming.start, format: .dateTime.weekday(.abbreviated))
    }
  }
}
