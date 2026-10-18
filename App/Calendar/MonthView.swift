import KitbagCore
import SwiftUI

/// The month's name with buttons for the month before and after.
struct MonthHeader: View {
  let month: MonthGrid
  let previous: () -> Void
  let next: () -> Void

  var body: some View {
    HStack {
      Button(action: previous) { Image(systemName: "chevron.left") }
        .accessibilityLabel(Text("Previous month", tableName: "Calendar"))
      Spacer()
      Text(month.month.date(calendar: .current), format: .dateTime.month(.wide).year())
        .font(.title3.weight(.semibold))
      Spacer()
      Button(action: next) { Image(systemName: "chevron.right") }
        .accessibilityLabel(Text("Next month", tableName: "Calendar"))
    }
    .padding(.horizontal, 8)
  }
}

/// A month page: weekday initials, then the days in rows of seven, with a dot for each open deadline.
struct MonthGridView: View {
  let month: MonthGrid
  @Binding var selected: LocalDate
  let book: DeadlineBook

  private let calendar = Calendar.current

  var body: some View {
    let today = LocalDate(Date(), calendar: calendar)
    VStack(spacing: 2) {
      HStack(spacing: 0) {
        ForEach(MonthGrid.columnOrder(calendar: calendar), id: \.self) { weekday in
          Text(calendar.veryShortStandaloneWeekdaySymbols[weekday.calendarSymbolIndex])
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        }
      }
      ForEach(month.weeks.indices, id: \.self) { row in
        HStack(spacing: 0) {
          ForEach(month.weeks[row], id: \.self) { day in
            DayCell(
              day: day, isToday: day == today, isSelected: day == selected, isInMonth: month.contains(day),
              kinds: book.openKinds(on: day), hasDone: book.hasDeadlines(on: day)
            ) {
              selected = day
            }
          }
        }
      }
    }
  }
}

private struct DayCell: View {
  let day: LocalDate
  let isToday: Bool
  let isSelected: Bool
  let isInMonth: Bool
  let kinds: [DeadlineKind]
  let hasDone: Bool
  let select: () -> Void

  var body: some View {
    Button(action: select) {
      VStack(spacing: 3) {
        Text("\(day.day)")
          .font(.system(size: 16, weight: isToday ? .bold : .regular))
          .foregroundStyle(isToday ? Color.white : (isInMonth ? Color.primary : Color.secondary.opacity(0.55)))
          .frame(width: 32, height: 32)
          .background {
            if isToday {
              Circle().fill(Color.accentColor)
            } else if isSelected {
              Circle().strokeBorder(Color.accentColor, lineWidth: 1.5)
            }
          }
          .overlay {
            if isToday && isSelected { Circle().strokeBorder(Color.primary.opacity(0.35), lineWidth: 2).padding(-3) }
          }
        HStack(spacing: 3) {
          ForEach(Array(kinds.prefix(3).enumerated()), id: \.offset) { _, kind in
            Circle().fill(kind.color).frame(width: 5, height: 5)
          }
          if kinds.isEmpty && hasDone {
            Circle().fill(Color.secondary.opacity(0.4)).frame(width: 5, height: 5)
          }
        }
        .frame(height: 6)
      }
      .frame(maxWidth: .infinity, minHeight: 48)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(day.date(calendar: .current), format: .dateTime.weekday(.wide).month(.wide).day()))
    .accessibilityValue(kinds.isEmpty ? Text("") : Text("Deadlines: \(kinds.count)", tableName: "Calendar"))
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

/// What is on the selected day: the classes of the timetable, then the deadlines.
struct DayAgenda: View {
  @Environment(TimetableStore.self) private var timetable
  @Environment(DeadlineStore.self) private var deadlines

  let day: LocalDate
  let edit: (Deadline) -> Void

  var body: some View {
    let calendar = Calendar.current
    let slots = timetable.timetable.slots(on: day.weekday(calendar: calendar))
    let items = deadlines.book.on(day, calendar: calendar)
    VStack(alignment: .leading, spacing: 12) {
      Text(day.date(calendar: calendar), format: .dateTime.weekday(.wide).month(.wide).day())
        .font(.headline)
        .frame(maxWidth: .infinity, alignment: .leading)
      if !slots.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(slots) { ClassLine(slot: $0) }
        }
      }
      if !items.isEmpty {
        VStack(alignment: .leading, spacing: 10) {
          ForEach(items) { item in
            DeadlineRow(deadline: item, showsDate: false) { edit(item) }
          }
        }
      }
      if slots.isEmpty && items.isEmpty {
        Text("Nothing on this day.", tableName: "Calendar")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}
