import KitbagCore
import SwiftUI

/// The top of the home screen: today's date (it opens the calendar), the class that is on or comes next, today's
/// classes, and what is due soon.
struct TodayView: View {
  @Environment(TimetableStore.self) private var timetable
  @Environment(DeadlineStore.self) private var deadlines
  @Environment(NoteStore.self) private var notes
  let open: (ModuleRoute) -> Void

  var body: some View {
    TimelineView(.everyMinute) { context in
      VStack(alignment: .leading, spacing: 16) {
        header(now: context.date)
        if !timetable.timetable.courses.isEmpty {
          classes(now: context.date)
        }
        dueSoon(now: context.date)
        pinnedNotes
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func header(now: Date) -> some View {
    Button {
      open(ModuleRoute(.calendar, day: LocalDate(now, calendar: .current)))
    } label: {
      HStack(spacing: 6) {
        Text(now, format: .dateTime.weekday(.wide).month(.wide).day())
          .font(.title2.weight(.semibold))
        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
      }
    }
    .buttonStyle(.plain)
    .accessibilityHint(Text("Opens the calendar", tableName: "Today"))
  }

  // MARK: Classes

  @ViewBuilder private func classes(now: Date) -> some View {
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
    let today = timetable.timetable.slots(on: Weekday(date: now, calendar: calendar))
    if !today.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Text("Today", tableName: "Today").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
        ForEach(today) { slot in
          ClassLine(slot: slot, isOver: endOf(slot, now: now, calendar: calendar) <= now)
        }
      }
    }
  }

  private func endOf(_ slot: Timetable.Slot, now: Date, calendar: Calendar) -> Date {
    let start = calendar.startOfDay(for: now)
    return calendar.date(byAdding: .minute, value: slot.meeting.end.minutes, to: start) ?? start
  }

  // MARK: Notes

  @ViewBuilder private var pinnedNotes: some View {
    let pinned = Array(notes.book.pinned.prefix(3))
    if !pinned.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Text("Pinned", tableName: "Today").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
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

  // MARK: Deadlines

  @ViewBuilder private func dueSoon(now: Date) -> some View {
    let calendar = Calendar.current
    let today = LocalDate(now, calendar: calendar)
    let overdue = deadlines.book.overdue(at: now, calendar: calendar)
    let soon = deadlines.book.upcoming(after: now, calendar: calendar)
      .filter { $0.date.days(since: today, calendar: calendar) <= 14 }
      .prefix(3)
    if !overdue.isEmpty || !soon.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Text("Due soon", tableName: "Today").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
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
        ForEach(Array(soon)) { item in
          Button {
            open(ModuleRoute(.calendar, day: item.date))
          } label: {
            DueSoonRow(deadline: item)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }
}

/// The class on now or next: when, where, and how long until it starts.
private struct NextClassCard: View {
  let upcoming: Timetable.Upcoming
  let now: Date
  let calendar: Calendar

  var body: some View {
    let slot = upcoming.slot
    let inProgress = upcoming.isInProgress(at: now)
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        (inProgress ? Text("Now", tableName: "Today") : Text("Next", tableName: "Today"))
          .font(.caption.weight(.bold))
          .foregroundStyle(.primary.opacity(0.6))
        Text(slot.course.code).font(.title3.weight(.semibold))
        if !slot.course.title.isEmpty { Text(slot.course.title).font(.subheadline) }
        if !slot.meeting.location.isEmpty {
          Label(slot.meeting.location, systemImage: "mappin.and.ellipse")
            .font(.footnote)
            .foregroundStyle(.primary.opacity(0.7))
        }
      }
      Spacer(minLength: 8)
      VStack(alignment: .trailing, spacing: 3) {
        Text(
          "\(upcoming.start.formatted(date: .omitted, time: .shortened))–\(upcoming.end.formatted(date: .omitted, time: .shortened))"
        )
        .font(.subheadline.weight(.medium))
        timing
          .font(.footnote)
          .foregroundStyle(.primary.opacity(0.7))
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(slot.course.color.blockColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder private var timing: some View {
    if upcoming.isInProgress(at: now) {
      Text("until \(upcoming.end.formatted(date: .omitted, time: .shortened))", tableName: "Today")
    } else if calendar.isDate(upcoming.start, inSameDayAs: now) {
      Text("in \(Text(upcoming.start, style: .relative))", tableName: "Today")
    } else {
      Text(upcoming.start, format: .dateTime.weekday(.wide))
    }
  }
}

/// A deadline on the Today screen: its kind, title and when it is due.
private struct DueSoonRow: View {
  @Environment(TimetableStore.self) private var timetable
  let deadline: Deadline

  var body: some View {
    let course = deadline.courseID.flatMap { timetable.timetable.course(id: $0) }
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
      Text(note.title.isEmpty ? String(localized: "New note", table: "Notes") : note.title)
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
      if !note.preview.isEmpty {
        Text(note.preview).font(.footnote).foregroundStyle(.primary.opacity(0.7)).lineLimit(2)
      }
    }
    .multilineTextAlignment(.leading)
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.stickyNote, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .accessibilityElement(children: .combine)
  }
}
