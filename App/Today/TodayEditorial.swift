import KitbagCore
import SwiftUI

/// Today as a printed page: no boxes, thin rules between the parts, serif headings, the weather as one line of text and
/// the next class as a large title with a bar in the colour of its course.
struct TodayEditorial: View {
  @Environment(LayoutStore.self) private var layout
  @Environment(\.palette) private var palette
  let model: TodayModel
  let open: (ModuleRoute) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(layout.visibleSections.filter(model.hasContent)) { section in
        VStack(alignment: .leading, spacing: 12) {
          content(section)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.cardStroke).frame(height: 1) }
      }
    }
  }

  @ViewBuilder private func content(_ section: TodaySection) -> some View {
    switch section {
    case .weather:
      if let forecast = model.forecast {
        Button {
          open(ModuleRoute(.weather))
        } label: {
          EditorialWeatherLine(forecast: forecast)
        }
        .buttonStyle(.plain)
      }
    case .nextClass:
      if model.hasCourses {
        if let upcoming = model.upcoming {
          Button {
            open(ModuleRoute(.timetable))
          } label: {
            EditorialNextClass(upcoming: upcoming, now: model.now, calendar: model.calendar)
          }
          .buttonStyle(.plain)
        } else {
          Text("No classes in the next week.", tableName: "Today")
            .font(.system(.subheadline, design: .serif).italic())
            .foregroundStyle(.secondary)
        }
      }
    case .todaysClasses:
      EditorialHeading(Text("Today", tableName: "Today"))
      TodaysClassesLines(model: model, spacing: 8)
    case .dueSoon:
      EditorialHeading(Text("Due soon", tableName: "Today"))
      DueSoonLines(model: model, open: open, spacing: 10)
    case .pinnedNotes:
      EditorialHeading(Text("Pinned", tableName: "Today"))
      ForEach(model.pinned.prefix(3)) { note in
        Button {
          open(ModuleRoute(.notes, noteID: note.id))
        } label: {
          HStack(alignment: .top, spacing: 12) {
            Rectangle().fill(Color.stickyNote).frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
              Text(note.title.isEmpty ? L10n.string("New note", table: "Notes") : note.title)
                .font(.system(.subheadline, design: .serif).weight(.semibold))
                .lineLimit(1)
              if !note.preview.isEmpty {
                Text(note.preview).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
              }
            }
            Spacer(minLength: 0)
          }
          .multilineTextAlignment(.leading)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
  }
}

/// A small heading in capitals, spaced out, in serif.
struct EditorialHeading: View {
  @Environment(\.palette) private var palette
  let text: Text

  init(_ text: Text) { self.text = text }

  var body: some View {
    text
      .font(.system(.caption, design: .serif).weight(.bold))
      .textCase(.uppercase)
      .tracking(2.2)
      .foregroundStyle(palette.accent)
      .accessibilityAddTraits(.isHeader)
  }
}

/// "17° · Clear · H 18° L 4° · Madison", as a line of italic text.
private struct EditorialWeatherLine: View {
  @Environment(\.palette) private var palette
  let forecast: Forecast
  @AppStorage("weather.units") private var unitsRaw = UnitPreference.automatic.rawValue

  var body: some View {
    let format = WeatherFormat(usesUSUnits: (UnitPreference(rawValue: unitsRaw) ?? .automatic).usesUSUnits)
    let today = forecast.today(at: Date()) ?? forecast.daily.first
    HStack(spacing: 10) {
      WeatherSymbol(kind: forecast.current.kind, isDay: forecast.current.isDay, size: 24)
      VStack(alignment: .leading, spacing: 2) {
        Text("\(format.temperature(forecast.current.temperature)) · \(L10n.string(forecast.current.kind.title))")
          .font(.system(.body, design: .serif).weight(.semibold))
        HStack(spacing: 6) {
          if let today {
            Text(
              "H \(format.temperature(today.maxTemperature))  L \(format.temperature(today.minTemperature))",
              tableName: "Weather")
          }
          Text(verbatim: "·")
          Text(forecast.place.name)
        }
        .font(.system(.footnote, design: .serif).italic())
        .foregroundStyle(palette.heading)
      }
      Spacer(minLength: 0)
    }
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}

/// The class on now or next: a large serif title and a bar in the course's colour.
private struct EditorialNextClass: View {
  @Environment(\.palette) private var palette
  let upcoming: Timetable.Upcoming
  let now: Date
  let calendar: Calendar

  var body: some View {
    let slot = upcoming.slot
    let color = slot.course.color.blockColor
    let inProgress = upcoming.isInProgress(at: now)
    HStack(alignment: .top, spacing: 14) {
      Rectangle().fill(color).frame(width: 4)
      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline) {
          EditorialHeading(inProgress ? Text("Now", tableName: "Today") : Text("Next", tableName: "Today"))
          Spacer()
          timing.font(.system(.footnote, design: .serif).italic()).foregroundStyle(palette.heading)
        }
        Text(slot.course.code)
          .font(.system(size: 36, weight: .regular, design: .serif))
          .lineLimit(1)
          .minimumScaleFactor(0.7)
        if !slot.course.title.isEmpty {
          Text(slot.course.title).font(.system(.subheadline, design: .serif))
        }
        Text(details)
          .font(.footnote)
          .foregroundStyle(.secondary)
        if inProgress {
          ProgressBar(
            fraction: now.timeIntervalSince(upcoming.start) / max(upcoming.end.timeIntervalSince(upcoming.start), 1),
            color: color)
        }
      }
    }
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }

  private var details: String {
    let time =
      "\(upcoming.start.formattedInLanguage(date: .omitted, time: .shortened))–\(upcoming.end.formattedInLanguage(date: .omitted, time: .shortened))"
    return [time, upcoming.slot.meeting.location].filter { !$0.isEmpty }.joined(separator: " · ")
  }

  @ViewBuilder private var timing: some View {
    if upcoming.isInProgress(at: now) {
      Text("until \(upcoming.end.formattedInLanguage(date: .omitted, time: .shortened))", tableName: "Today")
    } else if calendar.isDate(upcoming.start, inSameDayAs: now) {
      Text("in \(Text(upcoming.start, style: .relative))", tableName: "Today")
    } else {
      Text(upcoming.start, format: .dateTime.weekday(.wide))
    }
  }
}
