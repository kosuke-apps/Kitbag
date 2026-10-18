import KitbagCore
import SwiftUI

/// The top of the home screen: today's date, the class that is on or comes next, and the rest of today's classes.
struct TodayView: View {
  @Environment(TimetableStore.self) private var store
  let openTimetable: () -> Void

  var body: some View {
    TimelineView(.everyMinute) { context in
      VStack(alignment: .leading, spacing: 16) {
        Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
          .font(.title2.weight(.semibold))
        if !store.timetable.courses.isEmpty {
          classes(now: context.date)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder private func classes(now: Date) -> some View {
    let calendar = Calendar.current
    if let upcoming = store.timetable.upcoming(after: now, calendar: calendar) {
      Button(action: openTimetable) {
        NextClassCard(upcoming: upcoming, now: now, calendar: calendar)
      }
      .buttonStyle(.plain)
    } else {
      Text("No classes in the next week.", tableName: "Today")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    let today = store.timetable.slots(on: Weekday(date: now, calendar: calendar))
    if !today.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Text("Today", tableName: "Today").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
        ForEach(today) { slot in
          TodayRow(slot: slot, now: now, calendar: calendar)
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

/// One line of today's list: a colour dot, the time, the course and the room. Classes that are over are dimmed.
private struct TodayRow: View {
  let slot: Timetable.Slot
  let now: Date
  let calendar: Calendar

  var body: some View {
    let over = end <= now
    HStack(spacing: 10) {
      Circle().fill(slot.course.color.blockColor).frame(width: 12, height: 12)
        .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
      Text("\(slot.meeting.start.twelveHourText)–\(slot.meeting.end.twelveHourText)")
        .font(.footnote.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(width: 88, alignment: .leading)
      Text(slot.course.code).font(.subheadline.weight(.medium))
      Spacer(minLength: 8)
      Text(slot.meeting.location).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
    }
    .opacity(over ? 0.4 : 1)
    .accessibilityElement(children: .combine)
  }

  private var end: Date {
    let start = calendar.startOfDay(for: now)
    return calendar.date(byAdding: .minute, value: slot.meeting.end.minutes, to: start) ?? start
  }
}
