import KitbagCore
import SwiftUI
import WidgetKit

struct DeadlinesProvider: TimelineProvider {
  func placeholder(in context: Context) -> KitbagEntry {
    KitbagEntry(date: Date(), snapshot: .sample)
  }

  func getSnapshot(in context: Context, completion: @escaping (KitbagEntry) -> Void) {
    let snapshot = context.isPreview ? KitbagSnapshot.sample : KitbagSnapshot.load()
    completion(KitbagEntry(date: Date(), snapshot: snapshot))
  }

  /// One entry now and one at each coming due time, so that a deadline drops off the list when it passes.
  func getTimeline(in context: Context, completion: @escaping (Timeline<KitbagEntry>) -> Void) {
    let snapshot = KitbagSnapshot.load()
    let calendar = Calendar.current
    let now = Date()
    var dates: Set<Date> = [now]
    for deadline in snapshot.deadlines.deadlines where !deadline.isDone {
      let due = deadline.dueInstant(calendar: calendar)
      if due > now { dates.insert(due) }
    }
    if let midnight = calendar.nextDate(
      after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime)
    {
      dates.insert(midnight)
    }
    let sorted = Array(dates.sorted().prefix(30))
    let reload = max(sorted.last ?? now, now.addingTimeInterval(3600))
    completion(
      Timeline(entries: sorted.map { KitbagEntry(date: $0, snapshot: snapshot) }, policy: .after(reload)))
  }
}

struct DeadlinesWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "dev.kosuke.kitbag.deadlines", provider: DeadlinesProvider()) { entry in
      DeadlinesWidgetView(entry: entry)
    }
    .configurationDisplayName(Text("Deadlines"))
    .description(Text("What is due next: assignments, quizzes and exams."))
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
  }
}

struct DeadlinesWidgetView: View {
  @Environment(\.widgetFamily) private var family
  @Environment(\.palette) private var palette
  let entry: KitbagEntry

  var body: some View {
    let open = entry.openDeadlines
    Group {
      switch family {
      case .accessoryRectangular:
        lockScreen(open)
          .containerBackground(for: .widget) { Color.clear }
      case .systemSmall:
        small(open).themedWidget(entry.snapshot.theme)
      default:
        list(open, limit: 3).themedWidget(entry.snapshot.theme)
      }
    }
    .widgetURL(URL(string: "kitbag://calendar"))
  }

  @ViewBuilder private func small(_ open: [Deadline]) -> some View {
    if let first = open.first {
      VStack(alignment: .leading, spacing: 4) {
        SectionLabel()
        Image(systemName: first.kind.symbol).font(.title3).foregroundStyle(first.kind.color)
        Text(first.title).font(.subheadline.weight(.semibold)).lineLimit(3)
        if let code = entry.courseCode(first.courseID) {
          Text(code).font(.caption).foregroundStyle(.secondary)
        }
        Spacer(minLength: 2)
        DueText(deadline: first, calendar: entry.calendar).font(.caption.weight(.medium))
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    } else {
      Nothing()
    }
  }

  @ViewBuilder private func list(_ open: [Deadline], limit: Int) -> some View {
    if open.isEmpty {
      Nothing()
    } else {
      VStack(alignment: .leading, spacing: 7) {
        SectionLabel()
        ForEach(Array(open.prefix(limit))) { deadline in
          HStack(spacing: 8) {
            Image(systemName: deadline.kind.symbol).foregroundStyle(deadline.kind.color).frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
              Text(deadline.title).font(.subheadline.weight(.medium)).lineLimit(1)
              if let code = entry.courseCode(deadline.courseID) {
                Text(code).font(.caption2).foregroundStyle(.secondary)
              }
            }
            Spacer(minLength: 4)
            DueText(deadline: deadline, calendar: entry.calendar).font(.caption).foregroundStyle(.secondary)
          }
        }
        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  @ViewBuilder private func lockScreen(_ open: [Deadline]) -> some View {
    if open.isEmpty {
      Text("Nothing due").font(.caption)
    } else {
      VStack(alignment: .leading, spacing: 1) {
        ForEach(Array(open.prefix(2))) { deadline in
          HStack(spacing: 4) {
            Text(deadline.title).font(.caption.weight(.semibold)).lineLimit(1)
            Spacer(minLength: 2)
            DueText(deadline: deadline, calendar: entry.calendar).font(.caption2)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

private struct SectionLabel: View {
  @Environment(\.palette) private var palette

  var body: some View {
    Text("Due soon")
      .font(.caption2.weight(.bold))
      .textCase(.uppercase)
      .tracking(1.2)
      .foregroundStyle(palette.heading)
  }
}

private struct Nothing: View {
  var body: some View {
    VStack(spacing: 6) {
      Image(systemName: "checkmark.circle").font(.title2).foregroundStyle(.secondary)
      Text("Nothing due").font(.subheadline.weight(.medium))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

/// "Tue 1:00 PM", or just the day when it has no time.
private struct DueText: View {
  let deadline: Deadline
  let calendar: Calendar

  var body: some View {
    let due = deadline.dueInstant(calendar: calendar)
    if deadline.time == nil {
      Text(due, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
    } else {
      Text(due, format: .dateTime.weekday(.abbreviated).hour().minute())
    }
  }
}
