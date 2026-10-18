import KitbagCore
import SwiftUI

enum NameWidth { case short, wide }

extension Weekday {
  func name(width: NameWidth, calendar: Calendar = .current) -> String {
    switch width {
    case .wide: calendar.weekdaySymbols[calendarSymbolIndex]
    case .short: calendar.shortWeekdaySymbols[calendarSymbolIndex]
    }
  }
}

/// The week as a printed school timetable shows it: days across, hours down, each class a pastel block as tall as the
/// class is long, and the details written inside as far as they fit.
struct TimetableGrid: View {
  let timetable: Timetable
  let onSelect: (Timetable.Slot) -> Void

  private let rowHeight: CGFloat = 68
  private let headerHeight: CGFloat = 26
  private let timeColumnWidth: CGFloat = 38

  var body: some View {
    let days = timetable.visibleDays
    let hours = timetable.hourRange
    let height = headerHeight + CGFloat(hours.count) * rowHeight
    GeometryReader { proxy in
      let columnWidth = (proxy.size.width - timeColumnWidth) / CGFloat(days.count)
      ZStack(alignment: .topLeading) {
        lines(days: days.count, hours: hours.count, columnWidth: columnWidth, size: proxy.size)
        header(days: days, columnWidth: columnWidth)
        hourLabels(hours: hours)
        blocks(days: days, hours: hours, columnWidth: columnWidth)
        nowLine(days: days, hours: hours, columnWidth: columnWidth)
      }
    }
    .frame(height: height)
  }

  // MARK: Parts

  private func lines(days: Int, hours: Int, columnWidth: CGFloat, size: CGSize) -> some View {
    ZStack {
      Path { path in
        for row in 0...hours {
          let y = headerHeight + CGFloat(row) * rowHeight
          path.move(to: CGPoint(x: row == 0 ? timeColumnWidth : 0, y: y))
          path.addLine(to: CGPoint(x: size.width, y: y))
        }
        for column in 0...days {
          let x = timeColumnWidth + CGFloat(column) * columnWidth
          path.move(to: CGPoint(x: x, y: 0))
          path.addLine(to: CGPoint(x: x, y: size.height))
        }
        path.move(to: CGPoint(x: 0, y: headerHeight))
        path.addLine(to: CGPoint(x: 0, y: size.height))
      }
      .stroke(Color.primary.opacity(0.18), lineWidth: 0.5)
    }
  }

  private func header(days: [Weekday], columnWidth: CGFloat) -> some View {
    TimelineView(.everyMinute) { context in
      let today = Weekday(date: context.date, calendar: .current)
      ZStack(alignment: .topLeading) {
        ForEach(Array(days.enumerated()), id: \.element) { index, day in
          Text(day.name(width: columnWidth >= 100 ? .wide : .short))
            .font(.system(size: 12, weight: day == today ? .bold : .regular))
            .foregroundStyle(day == today ? Color.accentColor : Color.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: columnWidth, height: headerHeight)
            .offset(x: timeColumnWidth + CGFloat(index) * columnWidth)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  private func hourLabels(hours: ClosedRange<Int>) -> some View {
    ForEach(Array(hours.enumerated()), id: \.element) { row, hour in
      Text(Self.label(forHour: hour))
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(width: timeColumnWidth, height: rowHeight)
        .offset(y: headerHeight + CGFloat(row) * rowHeight)
    }
  }

  private func blocks(days: [Weekday], hours: ClosedRange<Int>, columnWidth: CGFloat) -> some View {
    ForEach(Array(days.enumerated()), id: \.element) { column, day in
      ForEach(timetable.slots(on: day)) { slot in
        let top = CGFloat(slot.meeting.start.minutes - hours.lowerBound * 60) / 60 * rowHeight
        let length = CGFloat(slot.meeting.end.minutes - slot.meeting.start.minutes) / 60 * rowHeight
        Button {
          onSelect(slot)
        } label: {
          CourseBlock(slot: slot, wide: columnWidth >= 100)
        }
        .buttonStyle(.plain)
        .frame(width: columnWidth - 2, height: max(length - 2, 12))
        .offset(
          x: timeColumnWidth + CGFloat(column) * columnWidth + 1,
          y: headerHeight + top + 1)
      }
    }
  }

  /// A thin line across today's column at the current time, as a calendar app draws it.
  private func nowLine(days: [Weekday], hours: ClosedRange<Int>, columnWidth: CGFloat) -> some View {
    TimelineView(.everyMinute) { context in
      let calendar = Calendar.current
      let today = Weekday(date: context.date, calendar: calendar)
      let minutes = calendar.component(.hour, from: context.date) * 60 + calendar.component(.minute, from: context.date)
      ZStack(alignment: .topLeading) {
        if let column = days.firstIndex(of: today), minutes >= hours.lowerBound * 60,
          minutes < (hours.upperBound + 1) * 60
        {
          let y = headerHeight + CGFloat(minutes - hours.lowerBound * 60) / 60 * rowHeight
          Rectangle()
            .fill(Color.red)
            .frame(width: columnWidth, height: 1.5)
            .overlay(alignment: .leading) { Circle().fill(Color.red).frame(width: 6, height: 6).offset(x: -3) }
            .offset(x: timeColumnWidth + CGFloat(column) * columnWidth, y: y - 0.75)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }
  }

  /// `8 AM`, `1 PM`: always the 12-hour clock, as the printed timetable and the times inside its blocks are written.
  private static func label(forHour hour: Int) -> String {
    let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.setLocalizedDateFormatFromTemplate("ha")
    return formatter.string(from: date)
  }
}

/// One class on the grid: the course code, then as many of section, time, room and instructor as the block has room for.
private struct CourseBlock: View {
  let slot: Timetable.Slot
  let wide: Bool

  var body: some View {
    ViewThatFits(in: .vertical) {
      content(level: 3)
      content(level: 2)
      content(level: 1)
      content(level: 0)
    }
    .padding(2)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(slot.course.color.blockColor)
    .overlay(Rectangle().stroke(Color.primary.opacity(0.18), lineWidth: 0.5))
    .accessibilityElement(children: .combine)
  }

  private var timeRange: String {
    "\(slot.meeting.start.twelveHourText)–\(slot.meeting.end.twelveHourText)"
  }

  /// Level 3 shows everything, 2 drops section and instructor, 1 keeps the time, 0 only the code.
  private func content(level: Int) -> some View {
    let meeting = slot.meeting
    return VStack(spacing: 1) {
      Text(slot.course.code)
        .font(.system(size: wide ? 14 : 11, weight: .semibold))
      if level >= 3, wide, !meeting.label.isEmpty {
        detail("\(meeting.label)  \(timeRange)")
      } else {
        if level >= 3, !meeting.label.isEmpty { detail(meeting.label) }
        if level >= 1 { detail(timeRange) }
      }
      if level >= 2, !meeting.location.isEmpty { detail(meeting.location) }
      if level >= 3, !meeting.instructor.isEmpty { detail(meeting.instructor) }
    }
    .multilineTextAlignment(.center)
    .fixedSize(horizontal: false, vertical: true)
  }

  private func detail(_ text: String) -> some View {
    Text(text)
      .font(.system(size: wide ? 10.5 : 8.5))
      .foregroundStyle(.primary.opacity(0.7))
  }
}

/// The legend under the grid: each course's colour, code, full title and the sections taken.
struct TimetableLegend: View {
  let courses: [Course]

  private let columns = [GridItem(.adaptive(minimum: 104), spacing: 0, alignment: .top)]

  var body: some View {
    LazyVGrid(columns: columns, spacing: 0) {
      ForEach(courses) { course in
        VStack(spacing: 3) {
          Text(course.code).font(.system(size: 13, weight: .semibold))
          if !course.title.isEmpty { Text(course.title).font(.footnote) }
          if !course.sectionsSummary.isEmpty {
            Text(course.sectionsSummary).font(.caption2).foregroundStyle(.primary.opacity(0.6))
          }
        }
        .multilineTextAlignment(.center)
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(course.color.blockColor)
        .overlay(Rectangle().stroke(Color.primary.opacity(0.18), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
      }
    }
  }
}
