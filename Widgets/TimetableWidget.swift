import KitbagCore
import SwiftUI
import WidgetKit

struct TimetableProvider: TimelineProvider {
  func placeholder(in context: Context) -> KitbagEntry {
    KitbagEntry(date: Date(), snapshot: .sample)
  }

  func getSnapshot(in context: Context, completion: @escaping (KitbagEntry) -> Void) {
    let snapshot = context.isPreview ? KitbagSnapshot.sample : KitbagSnapshot.load()
    completion(KitbagEntry(date: Date(), snapshot: snapshot))
  }

  /// One entry now, and one at every moment the picture changes: when a class starts, when it ends, and at midnight. The
  /// views work out what is on from the entry's date, so nothing has to be fetched later.
  func getTimeline(in context: Context, completion: @escaping (Timeline<KitbagEntry>) -> Void) {
    let snapshot = KitbagSnapshot.load()
    let calendar = Calendar.current
    let now = Date()
    var dates: Set<Date> = [now]
    if let term = snapshot.library.active(on: now, calendar: calendar) {
      var cursor = now
      for _ in 0..<14 {
        guard let next = term.upcoming(after: cursor, calendar: calendar, days: 3) else { break }
        if next.start > now { dates.insert(next.start) }
        dates.insert(next.end)
        cursor = next.end
      }
    }
    if let midnight = calendar.nextDate(
      after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime)
    {
      dates.insert(midnight)
    }
    let sorted = dates.sorted()
    let reload = max(sorted.last ?? now, now.addingTimeInterval(3600))
    completion(
      Timeline(entries: sorted.map { KitbagEntry(date: $0, snapshot: snapshot) }, policy: .after(reload)))
  }
}

struct TimetableWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "dev.kosuke.kitbag.timetable", provider: TimetableProvider()) { entry in
      TimetableWidgetView(entry: entry)
    }
    .configurationDisplayName(Text("Timetable"))
    .description(Text("The class that is on now or comes next, and the rest of today."))
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
  }
}

struct TimetableWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: KitbagEntry

  var body: some View {
    switch family {
    case .systemSmall: small.widgetURL(URL(string: "kitbag://timetable"))
    case .accessoryRectangular: rectangular.widgetURL(URL(string: "kitbag://timetable"))
    case .accessoryInline: inline.widgetURL(URL(string: "kitbag://timetable"))
    default: medium.widgetURL(URL(string: "kitbag://timetable"))
    }
  }

  // MARK: Home screen

  @ViewBuilder private var small: some View {
    if let upcoming = entry.upcoming {
      NextClassBlock(upcoming: upcoming, now: entry.date, compact: true)
        .themedWidget(
          entry.snapshot.theme,
          background: AnyShapeStyle(
            LinearGradient(
              colors: [upcoming.slot.course.color.blockColor, upcoming.slot.course.color.blockColor.opacity(0.75)],
              startPoint: .topLeading, endPoint: .bottomTrailing)))
    } else {
      EmptyClasses().themedWidget(entry.snapshot.theme)
    }
  }

  @ViewBuilder private var medium: some View {
    Group {
      if entry.upcoming == nil {
        EmptyClasses()
      } else {
        TodayList(classes: entry.classes(onDayOf: entry.listDay), day: entry.listDay, now: entry.date)
      }
    }
    .themedWidget(entry.snapshot.theme)
  }

  // MARK: Lock screen

  @ViewBuilder private var rectangular: some View {
    if let upcoming = entry.upcoming {
      VStack(alignment: .leading, spacing: 1) {
        Text(upcoming.slot.course.code).font(.headline).lineLimit(1)
        Text(
          "\(upcoming.start.formatted(date: .omitted, time: .shortened))–\(upcoming.end.formatted(date: .omitted, time: .shortened))"
        )
        .font(.caption)
        if !upcoming.slot.meeting.location.isEmpty {
          Text(upcoming.slot.meeting.location).font(.caption2).lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .containerBackground(for: .widget) { Color.clear }
    } else {
      Text("No more classes").font(.caption).containerBackground(for: .widget) { Color.clear }
    }
  }

  @ViewBuilder private var inline: some View {
    if let upcoming = entry.upcoming {
      Text("\(upcoming.slot.course.code) \(upcoming.start.formatted(date: .omitted, time: .shortened))")
    } else {
      Text("No more classes")
    }
  }
}

/// The class that is on now or comes next: its code, title, time and place, with a bar while it is on.
private struct NextClassBlock: View {
  @Environment(\.titleDesign) private var design
  let upcoming: Timetable.Upcoming
  let now: Date
  let compact: Bool

  var body: some View {
    let slot = upcoming.slot
    let inProgress = upcoming.isInProgress(at: now)
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline) {
        (inProgress ? Text("Now") : Text("Next"))
          .font(.caption2.weight(.bold))
          .textCase(.uppercase)
          .tracking(1.2)
          .foregroundStyle(.primary.opacity(0.6))
        Spacer(minLength: 4)
        timing.font(.caption2.weight(.medium)).foregroundStyle(.primary.opacity(0.7)).lineLimit(1)
      }
      Text(slot.course.code)
        .font(.system(size: compact ? 24 : 30, weight: .semibold, design: design))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      if !slot.course.title.isEmpty {
        Text(slot.course.title).font(compact ? .caption : .subheadline).lineLimit(compact ? 2 : 1)
      }
      Spacer(minLength: 2)
      Label(
        "\(upcoming.start.formatted(date: .omitted, time: .shortened))–\(upcoming.end.formatted(date: .omitted, time: .shortened))",
        systemImage: "clock"
      )
      .font(.caption)
      .lineLimit(1)
      if !slot.meeting.location.isEmpty {
        Label(slot.meeting.location, systemImage: "mappin.and.ellipse").font(.caption).lineLimit(1)
      }
    }
    .foregroundStyle(.primary.opacity(0.85))
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
  }

  @ViewBuilder private var timing: some View {
    if upcoming.isInProgress(at: now) {
      Text("until \(upcoming.end.formatted(date: .omitted, time: .shortened))")
    } else if Calendar.current.isDate(upcoming.start, inSameDayAs: now) {
      Text("in \(Text(upcoming.start, style: .relative))")
    } else {
      Text(upcoming.start, format: .dateTime.weekday(.wide))
    }
  }
}

/// Today's classes in a list; the one that is on is marked, and the ones that are over are dimmed.
private struct TodayList: View {
  @Environment(\.palette) private var palette
  @Environment(\.titleDesign) private var design
  let classes: [(slot: Timetable.Slot, start: Date, end: Date)]
  /// The day the list is for (today, or the day of the next class when today is over).
  let day: Date
  let now: Date

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(day, format: .dateTime.weekday(.wide).month(.abbreviated).day())
          .font(.system(.footnote, design: design).weight(.semibold))
          .textCase(.uppercase)
          .tracking(1)
          .foregroundStyle(palette.heading)
        Spacer()
      }
      ForEach(Array(classes.prefix(4).enumerated()), id: \.offset) { _, item in
        let over = item.end <= now
        let on = item.start <= now && now < item.end
        HStack(spacing: 8) {
          Circle().fill(item.slot.course.color.strongColor).frame(width: 9, height: 9)
          Text(item.start.formatted(date: .omitted, time: .shortened))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 62, alignment: .leading)
          Text(item.slot.course.code).font(.subheadline.weight(on ? .bold : .medium)).lineLimit(1)
          Spacer(minLength: 4)
          Text(item.slot.meeting.location).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .opacity(over ? 0.4 : 1)
      }
      if classes.count > 4 {
        Text("+\(classes.count - 4)").font(.caption2).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

private struct EmptyClasses: View {
  var body: some View {
    VStack(spacing: 6) {
      Image(systemName: "checkmark.circle").font(.title2).foregroundStyle(.secondary)
      Text("No more classes").font(.subheadline.weight(.medium))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
