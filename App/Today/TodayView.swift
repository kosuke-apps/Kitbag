import KitbagCore
import SwiftUI

/// The top of the home screen: the parts the person chose to show, in the order they chose: the weather, the class that
/// is on or comes next, today's classes, what is due soon, pinned notes. The date above them is `TodayHeader`, which stays
/// in place while this scrolls. How the parts are arranged depends on the style (`KitbagStyle.todayLayout`): the data
/// is worked out once here (`TodayModel`) and each layout only draws it.
struct TodayView: View {
  @Environment(TimetableStore.self) private var timetable
  @Environment(DeadlineStore.self) private var deadlines
  @Environment(NoteStore.self) private var notes
  @Environment(WeatherStore.self) private var weather
  @Environment(SubscriptionStore.self) private var subscriptions
  @Environment(\.kitbagStyle) private var style

  let open: (ModuleRoute) -> Void

  var body: some View {
    TimelineView(.everyMinute) { context in
      let model = TodayModel(
        now: context.date, timetable: timetable, deadlines: deadlines, notes: notes, weather: weather,
        subscriptions: subscriptions)
      Group {
        switch style.todayLayout {
        case .stack: TodayStack(model: model, open: open)
        case .bento: TodayBento(model: model, open: open)
        case .editorial: TodayEditorial(model: model, open: open)
        case .compact: TodayCompact(model: model, open: open)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

/// Everything Today shows at one moment, worked out once so that every layout draws the same facts.
struct TodayModel {
  let now: Date
  let calendar = Calendar.current
  let today: LocalDate
  let forecast: Forecast?
  /// Whether there is a timetable at all (without one, the next-class card is left out).
  let hasCourses: Bool
  let upcoming: Timetable.Upcoming?
  let slots: [Timetable.Slot]
  let overdue: [Deadline]
  let soon: [DueEntry]
  let pinned: [Note]

  @MainActor
  init(
    now: Date, timetable: TimetableStore, deadlines: DeadlineStore, notes: NoteStore, weather: WeatherStore,
    subscriptions: SubscriptionStore
  ) {
    let calendar = Calendar.current
    self.now = now
    today = LocalDate(now, calendar: calendar)
    forecast = weather.forecast
    hasCourses = !timetable.timetable.courses.isEmpty
    upcoming = timetable.timetable.upcoming(after: now, calendar: calendar)
    slots = timetable.timetable.slots(on: today, calendar: calendar)
    overdue = deadlines.book.overdue(at: now, calendar: calendar)
    let own: [DueEntry] = deadlines.book.upcoming(after: now, calendar: calendar)
      .filter { $0.date.days(since: LocalDate(now, calendar: calendar), calendar: calendar) <= 14 }
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
    soon = Array((own + external).sorted { $0.sortDate < $1.sortDate }.prefix(4))
    pinned = Array(notes.book.pinned.prefix(4))
  }

  /// Whether a part has anything to show; a part with nothing is left out, not drawn empty.
  func hasContent(_ section: TodaySection) -> Bool {
    switch section {
    case .weather: forecast != nil
    case .nextClass: hasCourses
    case .todaysClasses: !slots.isEmpty
    case .dueSoon: !overdue.isEmpty || !soon.isEmpty
    case .pinnedNotes: !pinned.isEmpty
    }
  }

  func isOver(_ slot: Timetable.Slot) -> Bool {
    let start = calendar.startOfDay(for: now)
    let end = calendar.date(byAdding: .minute, value: slot.meeting.end.minutes, to: start) ?? start
    return end <= now
  }
}

// MARK: The classic stack

/// One card under another: the layout Kitbag started with.
struct TodayStack: View {
  @Environment(LayoutStore.self) private var layout
  @Environment(\.kitbagStyle) private var style
  let model: TodayModel
  let open: (ModuleRoute) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: style.sectionSpacing) {
      ForEach(layout.visibleSections.filter(model.hasContent)) { section in
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
            SectionHeading(Text("Due soon", tableName: "Today"))
            DueSoonLines(model: model, open: open)
          }
          .themedCard()
        case .pinnedNotes:
          VStack(alignment: .leading, spacing: 10) {
            SectionHeading(Text("Pinned", tableName: "Today"))
            ForEach(model.pinned.prefix(3)) { note in
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
  }
}

// MARK: Parts shared by the layouts

/// The weather card, which opens the weather.
struct WeatherButton: View {
  let model: TodayModel
  let open: (ModuleRoute) -> Void

  var body: some View {
    if let forecast = model.forecast {
      Button {
        open(ModuleRoute(.weather))
      } label: {
        WeatherCard(forecast: forecast)
      }
      .buttonStyle(.plain)
    }
  }
}

/// The class on now or next, which opens the timetable; or a line saying there are none this week.
struct NextClassButton: View {
  let model: TodayModel
  let open: (ModuleRoute) -> Void
  let shape: NextClassCard.Shape

  var body: some View {
    if model.hasCourses {
      if let upcoming = model.upcoming {
        Button {
          open(ModuleRoute(.timetable))
        } label: {
          NextClassCard(upcoming: upcoming, now: model.now, calendar: model.calendar, shape: shape)
        }
        .buttonStyle(.plain)
      } else {
        Text("No classes in the next week.", tableName: "Today")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
  }
}

/// Today's classes, one line each, the ones that are over dimmed.
struct TodaysClassesLines: View {
  let model: TodayModel
  var spacing: CGFloat = 10

  var body: some View {
    VStack(alignment: .leading, spacing: spacing) {
      ForEach(model.slots) { slot in
        ClassLine(slot: slot, isOver: model.isOver(slot))
      }
    }
  }
}

/// What is overdue and what is due soon, as lines that open the calendar at that day.
struct DueSoonLines: View {
  let model: TodayModel
  let open: (ModuleRoute) -> Void
  var spacing: CGFloat = 12

  var body: some View {
    VStack(alignment: .leading, spacing: spacing) {
      if !model.overdue.isEmpty {
        Button {
          open(ModuleRoute(.calendar, day: model.today))
        } label: {
          Label {
            Text("\(model.overdue.count) overdue", tableName: "Today")
          } icon: {
            Image(systemName: "exclamationmark.circle.fill")
          }
          .font(.subheadline.weight(.medium))
          .foregroundStyle(Color.red)
        }
        .buttonStyle(.plain)
      }
      ForEach(model.soon) { entry in
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
  }
}

/// The class on now or next: when, where, and how long until it starts (or, if it has begun, how far along it is).
struct NextClassCard: View {
  /// A wide card across the screen, or a squarer tile that shares a row with another.
  enum Shape { case wide, tile }

  @Environment(\.titleDesign) private var design
  @Environment(\.kitbagStyle) private var style
  let upcoming: Timetable.Upcoming
  let now: Date
  let calendar: Calendar
  var shape: Shape = .wide

  var body: some View {
    let slot = upcoming.slot
    let color = slot.course.color.blockColor
    let inProgress = upcoming.isInProgress(at: now)
    let radius = 22 * style.radiusScale
    VStack(alignment: .leading, spacing: shape == .tile ? 6 : 10) {
      HStack(alignment: .firstTextBaseline) {
        (inProgress ? Text("Now", tableName: "Today") : Text("Next", tableName: "Today"))
          .font(.caption.weight(.bold))
          .textCase(.uppercase)
          .tracking(1.4)
          .foregroundStyle(.primary.opacity(0.6))
        Spacer()
        if shape == .wide {
          timing
            .font(.footnote.weight(.medium))
            .foregroundStyle(.primary.opacity(0.7))
        }
      }
      Text(slot.course.code)
        .font(.system(size: shape == .tile ? 26 : 30, weight: .semibold, design: design))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      if !slot.course.title.isEmpty {
        Text(slot.course.title).font(.subheadline).lineLimit(shape == .tile ? 2 : 3)
      }
      if shape == .tile { Spacer(minLength: 2) }
      Group {
        if shape == .tile {
          VStack(alignment: .leading, spacing: 3) {
            Label(timeRange, systemImage: "clock")
            if !slot.meeting.location.isEmpty {
              Label(slot.meeting.location, systemImage: "mappin.and.ellipse").lineLimit(1)
            }
            timing.font(.footnote.weight(.medium))
          }
        } else {
          HStack(spacing: 14) {
            Label(timeRange, systemImage: "clock")
            if !slot.meeting.location.isEmpty {
              Label(slot.meeting.location, systemImage: "mappin.and.ellipse").lineLimit(1)
            }
          }
        }
      }
      .font(.footnote)
      .foregroundStyle(.primary.opacity(0.75))
      if inProgress {
        ProgressBar(
          fraction: now.timeIntervalSince(upcoming.start) / max(upcoming.end.timeIntervalSince(upcoming.start), 1))
      }
    }
    .padding((shape == .tile ? 16 : 18) * style.paddingScale)
    .frame(maxWidth: .infinity, maxHeight: shape == .tile ? .infinity : nil, alignment: .topLeading)
    .background(
      LinearGradient(colors: [color, color.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing),
      in: RoundedRectangle(cornerRadius: radius, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.75)
    )
    .shadow(color: color.opacity(0.35 * min(style.shadowScale, 1)), radius: 14 * style.shadowScale, y: 6 * style.shadowScale)
    .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    .accessibilityElement(children: .combine)
  }

  private var timeRange: String {
    "\(upcoming.start.formattedInLanguage(date: .omitted, time: .shortened))–\(upcoming.end.formattedInLanguage(date: .omitted, time: .shortened))"
  }

  @ViewBuilder var timing: some View {
    if upcoming.isInProgress(at: now) {
      Text("until \(upcoming.end.formattedInLanguage(date: .omitted, time: .shortened))", tableName: "Today")
    } else if calendar.isDate(upcoming.start, inSameDayAs: now) {
      Text("in \(Text(upcoming.start, style: .relative))", tableName: "Today")
    } else {
      Text(upcoming.start, format: .dateTime.weekday(.wide))
    }
  }
}

struct ProgressBar: View {
  let fraction: Double
  var color: Color = .primary

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule().fill(color.opacity(0.15))
        Capsule().fill(color.opacity(0.55)).frame(width: proxy.size.width * min(max(fraction, 0), 1))
      }
    }
    .frame(height: 4)
    .accessibilityHidden(true)
  }
}

/// A deadline on the Today screen: its kind, title and when it is due.
struct DueSoonRow: View {
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
struct PinnedNoteCard: View {
  @Environment(\.kitbagStyle) private var style
  let note: Note
  var lines = 2
  /// Stretch to the height of the row, for notes side by side.
  var fillsHeight = false

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(note.title.isEmpty ? L10n.string("New note", table: "Notes") : note.title)
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
      if !note.preview.isEmpty {
        Text(note.preview).font(.footnote).foregroundStyle(.primary.opacity(0.7)).lineLimit(lines)
      }
    }
    .multilineTextAlignment(.leading)
    .padding(14 * style.paddingScale)
    .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
    .background(Color.stickyNote, in: RoundedRectangle(cornerRadius: 16 * style.radiusScale, style: .continuous))
    .shadow(color: .black.opacity(0.10 * min(style.shadowScale, 1)), radius: 8 * style.shadowScale, y: 3 * style.shadowScale)
    .contentShape(RoundedRectangle(cornerRadius: 16 * style.radiusScale, style: .continuous))
    .accessibilityElement(children: .combine)
  }
}

/// A line in the Due soon list: one of the person's own deadlines, or an event of a subscribed calendar.
enum DueEntry: Identifiable {
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

struct ExternalDueRow: View {
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
