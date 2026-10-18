import KitbagCore
import SwiftUI

/// The top of the home screen: today's date (it opens the calendar) and the parts the person chose to show, in the
/// order they chose: the weather, the class that is on or comes next, today's classes, what is due soon, pinned notes.
struct TodayView: View {
  @Environment(TimetableStore.self) private var timetable
  @Environment(DeadlineStore.self) private var deadlines
  @Environment(NoteStore.self) private var notes
  @Environment(WeatherStore.self) private var weather
  @Environment(SubscriptionStore.self) private var subscriptions
  @Environment(LayoutStore.self) private var layout
  @Environment(\.palette) private var palette
  @Environment(\.titleDesign) private var design

  let open: (ModuleRoute) -> Void

  var body: some View {
    TimelineView(.everyMinute) { context in
      VStack(alignment: .leading, spacing: 18) {
        header(now: context.date)
        ForEach(layout.visibleSections) { section in
          sectionView(section, now: context.date)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func header(now: Date) -> some View {
    Button {
      open(ModuleRoute(.calendar, day: LocalDate(now, calendar: .current)))
    } label: {
      VStack(alignment: .leading, spacing: 2) {
        Text(now, format: .dateTime.weekday(.wide))
          .font(.subheadline.weight(.semibold))
          .textCase(.uppercase)
          .tracking(1.6)
          .foregroundStyle(palette.heading)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(now, format: .dateTime.month(.wide).day())
            .font(.system(size: 40, weight: .semibold, design: design))
            .minimumScaleFactor(0.7)
            .lineLimit(1)
          Image(systemName: "chevron.right")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(palette.heading)
        }
      }
    }
    .buttonStyle(.plain)
    .accessibilityHint(Text("Opens the calendar", tableName: "Today"))
  }

  @ViewBuilder private func sectionView(_ section: TodaySection, now: Date) -> some View {
    switch section {
    case .weather: weatherCard
    case .nextClass: nextClass(now: now)
    case .todaysClasses: todaysClasses(now: now)
    case .dueSoon: dueSoon(now: now)
    case .pinnedNotes: pinnedNotes
    }
  }

  // MARK: Weather

  @ViewBuilder private var weatherCard: some View {
    if let forecast = weather.forecast {
      Button {
        open(ModuleRoute(.weather))
      } label: {
        WeatherCard(forecast: forecast)
      }
      .buttonStyle(.plain)
    }
  }

  // MARK: Classes

  @ViewBuilder private func nextClass(now: Date) -> some View {
    if !timetable.timetable.courses.isEmpty {
      let calendar = Calendar.current
      if let upcoming = timetable.timetable.upcoming(after: now, calendar: calendar) {
        Button {
          open(ModuleRoute(.timetable))
        } label: {
          NextClassCard(upcoming: upcoming, now: now, calendar: calendar)
        }
        .buttonStyle(.plain)
      } else {
        Text("No classes in the next week.", tableName: "Today")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder private func todaysClasses(now: Date) -> some View {
    let calendar = Calendar.current
    let today = timetable.timetable.slots(on: LocalDate(now, calendar: calendar), calendar: calendar)
    if !today.isEmpty {
      VStack(alignment: .leading, spacing: 10) {
        SectionHeading(Text("Today", tableName: "Today"))
        ForEach(today) { slot in
          ClassLine(slot: slot, isOver: endOf(slot, now: now, calendar: calendar) <= now)
        }
      }
      .themedCard()
    }
  }

  private func endOf(_ slot: Timetable.Slot, now: Date, calendar: Calendar) -> Date {
    let start = calendar.startOfDay(for: now)
    return calendar.date(byAdding: .minute, value: slot.meeting.end.minutes, to: start) ?? start
  }

  // MARK: Deadlines

  @ViewBuilder private func dueSoon(now: Date) -> some View {
    let calendar = Calendar.current
    let today = LocalDate(now, calendar: calendar)
    let overdue = deadlines.book.overdue(at: now, calendar: calendar)
    let own: [DueEntry] = deadlines.book.upcoming(after: now, calendar: calendar)
      .filter { $0.date.days(since: today, calendar: calendar) <= 14 }
      .prefix(3)
      .map { DueEntry.deadline($0, $0.dueInstant(calendar: calendar)) }
    // Events of subscribed calendars that are switched on for Today, within two weeks.
    let window = DateInterval(start: now, end: now.addingTimeInterval(14 * 86400))
    let external: [DueEntry] = subscriptions.occurrences(in: window, calendar: calendar)
      .filter { $0.subscription.showsOnToday && !$0.event.isCompleted }
      .prefix(3)
      .map {
        DueEntry.external(
          name: $0.subscription.name, occurrence: $0.occurrence,
          day: $0.event.day(of: $0.occurrence.start, calendar: calendar))
      }
    let soon = Array((own + external).sorted { $0.sortDate < $1.sortDate }.prefix(4))
    if !overdue.isEmpty || !soon.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        SectionHeading(Text("Due soon", tableName: "Today"))
        if !overdue.isEmpty {
          Button {
            open(ModuleRoute(.calendar, day: today))
          } label: {
            Label {
              Text("\(overdue.count) overdue", tableName: "Today")
            } icon: {
              Image(systemName: "exclamationmark.circle.fill")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.red)
          }
          .buttonStyle(.plain)
        }
        ForEach(soon) { entry in
          Button {
            open(ModuleRoute(.calendar, day: entry.day))
          } label: {
            switch entry {
            case .deadline(let item, _): DueSoonRow(deadline: item)
            case .external(let name, let occurrence, _): ExternalDueRow(name: name, occurrence: occurrence)
            }
          }
          .buttonStyle(.plain)
        }
      }
      .themedCard()
    }
  }

  // MARK: Notes

  @ViewBuilder private var pinnedNotes: some View {
    let pinned = Array(notes.book.pinned.prefix(3))
    if !pinned.isEmpty {
      VStack(alignment: .leading, spacing: 10) {
        SectionHeading(Text("Pinned", tableName: "Today"))
        ForEach(pinned) { note in
          Button {
            open(ModuleRoute(.notes, noteID: note.id))
          } label: {
            PinnedNoteCard(note: note)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }
}

/// The class on now or next: when, where, and how long until it starts (or, if it has begun, how far along it is).
private struct NextClassCard: View {
  @Environment(\.titleDesign) private var design
  let upcoming: Timetable.Upcoming
  let now: Date
  let calendar: Calendar

  var body: some View {
    let slot = upcoming.slot
    let color = slot.course.color.blockColor
    let inProgress = upcoming.isInProgress(at: now)
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        (inProgress ? Text("Now", tableName: "Today") : Text("Next", tableName: "Today"))
          .font(.caption.weight(.bold))
          .textCase(.uppercase)
          .tracking(1.4)
          .foregroundStyle(.primary.opacity(0.6))
        Spacer()
        timing
          .font(.footnote.weight(.medium))
          .foregroundStyle(.primary.opacity(0.7))
      }
      Text(slot.course.code)
        .font(.system(size: 30, weight: .semibold, design: design))
      if !slot.course.title.isEmpty { Text(slot.course.title).font(.subheadline) }
      HStack(spacing: 14) {
        Label(
          "\(upcoming.start.formattedInLanguage(date: .omitted, time: .shortened))–\(upcoming.end.formattedInLanguage(date: .omitted, time: .shortened))",
          systemImage: "clock")
        if !slot.meeting.location.isEmpty {
          Label(slot.meeting.location, systemImage: "mappin.and.ellipse").lineLimit(1)
        }
      }
      .font(.footnote)
      .foregroundStyle(.primary.opacity(0.75))
      if inProgress {
        ProgressBar(
          fraction: now.timeIntervalSince(upcoming.start) / max(upcoming.end.timeIntervalSince(upcoming.start), 1))
      }
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      LinearGradient(colors: [color, color.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing),
      in: RoundedRectangle(cornerRadius: 22, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.75)
    )
    .shadow(color: color.opacity(0.35), radius: 14, y: 6)
    .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    .accessibilityElement(children: .combine)
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

private struct ProgressBar: View {
  let fraction: Double

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule().fill(Color.primary.opacity(0.15))
        Capsule().fill(Color.primary.opacity(0.55)).frame(width: proxy.size.width * min(max(fraction, 0), 1))
      }
    }
    .frame(height: 4)
    .accessibilityHidden(true)
  }
}

/// A deadline on the Today screen: its kind, title and when it is due.
private struct DueSoonRow: View {
  @Environment(TimetableStore.self) private var timetable
  let deadline: Deadline

  var body: some View {
    let course = deadline.courseID.flatMap { timetable.course(id: $0) }
    HStack(spacing: 10) {
      Image(systemName: deadline.kind.symbol)
        .foregroundStyle(deadline.kind.color)
        .frame(width: 20)
      Text(deadline.title).font(.subheadline.weight(.medium)).lineLimit(1)
      if let course { Text(course.code).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
      Spacer(minLength: 8)
      dueText.font(.footnote).foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder private var dueText: some View {
    let due = deadline.dueInstant(calendar: .current)
    if deadline.time != nil {
      Text(due, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
    } else {
      Text(due, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
  }
}

/// A pinned note on the Today screen, like a sticky note.
private struct PinnedNoteCard: View {
  let note: Note

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(note.title.isEmpty ? L10n.string("New note", table: "Notes") : note.title)
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
      if !note.preview.isEmpty {
        Text(note.preview).font(.footnote).foregroundStyle(.primary.opacity(0.7)).lineLimit(2)
      }
    }
    .multilineTextAlignment(.leading)
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.stickyNote, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .accessibilityElement(children: .combine)
  }
}

/// A line in the Due soon list: one of the person's own deadlines, or an event of a subscribed calendar.
private enum DueEntry: Identifiable {
  case deadline(Deadline, Date)
  case external(name: String, occurrence: CalendarEvent.Occurrence, day: LocalDate)

  var id: String {
    switch self {
    case .deadline(let item, _): "d-\(item.id)"
    case .external(_, let occurrence, _): "e-\(occurrence.id)"
    }
  }

  var sortDate: Date {
    switch self {
    case .deadline(_, let date): date
    case .external(_, let occurrence, let day): occurrence.isAllDay ? day.date(calendar: .current) : occurrence.start
    }
  }

  var day: LocalDate {
    switch self {
    case .deadline(let item, _): item.date
    case .external(_, _, let day): day
    }
  }
}

private struct ExternalDueRow: View {
  let name: String
  let occurrence: CalendarEvent.Occurrence

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "calendar.badge.clock").foregroundStyle(.secondary).frame(width: 20)
      VStack(alignment: .leading, spacing: 1) {
        Text(occurrence.title).font(.subheadline.weight(.medium)).lineLimit(2)
        Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
      }
      Spacer(minLength: 8)
      if occurrence.isAllDay {
        Text(occurrence.start, format: Date.FormatStyle(timeZone: .gmt).weekday(.abbreviated).month(.abbreviated).day())
          .font(.footnote).foregroundStyle(.secondary)
      } else {
        Text(occurrence.start, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
          .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
      }
    }
    .accessibilityElement(children: .combine)
  }
}
