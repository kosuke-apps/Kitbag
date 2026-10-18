import KitbagCore
import SwiftUI

enum Paper {
  /// A4 in points.
  static let a4 = CGSize(width: 595.28, height: 841.89)
}

enum NameWidth { case short, wide }

extension Weekday {
  func name(width: NameWidth, calendar: Calendar = .current) -> String {
    switch width {
    case .wide: calendar.weekdaySymbols[calendarSymbolIndex]
    case .short: calendar.shortWeekdaySymbols[calendarSymbolIndex]
    }
  }
}

/// The timetable drawn as a printed page: a heading, days across, hours down, each class a pastel block as tall as the
/// class is long, and (on paper) a legend of the courses. The same view is the preview on the screen and the PDF.
///
/// - `.paper` follows the printed timetable it was modelled on: A4, everything written in every block.
/// - `.screen` keeps the A4 proportions but writes in each block only what fits, in sizes that stay readable.
struct TimetablePage: View {
  enum Style { case screen, paper }

  let timetable: Timetable
  let heading: String
  let style: Style
  let size: CGSize
  var showsLegend = false
  var onSelect: ((Timetable.Slot) -> Void)?

  var body: some View {
    let days = timetable.visibleDays
    let hours = timetable.hourRange
    let layout = Layout(
      size: size, style: style, rows: hours.count, days: days.count,
      legendRows: showsLegend ? (timetable.courses.count + 4) / 5 : 0)
    ZStack(alignment: .topLeading) {
      pageBackground(layout)
      title(layout)
      lines(layout, days: days.count)
      dayHeaders(layout, days: days)
      hourLabels(layout, hours: hours)
      blocks(layout, days: days, hours: hours)
      if style == .screen { nowLine(layout, days: days, hours: hours) }
      if showsLegend { legend(layout) }
    }
    .frame(width: size.width, height: size.height, alignment: .topLeading)
  }

  // MARK: Measures

  /// Every measure of the page, from the A4 sizes of the printed original, scaled to the width of the page.
  private struct Layout {
    let size: CGSize
    let style: Style
    let rows: Int
    let days: Int
    let legendRows: Int

    var isPaper: Bool { style == .paper }
    var scale: CGFloat { size.width / Paper.a4.width }

    var margin: CGFloat { isPaper ? 36 * scale : 10 }
    var titleHeight: CGFloat { isPaper ? 28 * scale : 24 }
    var gap: CGFloat { isPaper ? 14 * scale : 8 }
    var gridTop: CGFloat { margin + titleHeight + gap }
    var headerHeight: CGFloat { isPaper ? 18 * scale : 18 }
    var timeColumn: CGFloat { isPaper ? 50 * scale : 32 }
    var gridWidth: CGFloat { size.width - 2 * margin }
    var columnWidth: CGFloat { (gridWidth - timeColumn) / CGFloat(days) }

    var legendHeight: CGFloat { legendRows == 0 ? 0 : 30 * scale + CGFloat(legendRows) * 62 * scale }
    var rowHeight: CGFloat {
      let spare = size.height - gridTop - headerHeight - legendHeight - (legendRows > 0 ? 12 * scale : 0) - margin
      let fitted = spare / CGFloat(rows)
      return isPaper ? min(58.5 * scale, fitted) : fitted
    }
    var gridHeight: CGFloat { headerHeight + rowHeight * CGFloat(rows) }
    var legendTop: CGFloat { gridTop + gridHeight + 12 * scale }

    var titleFont: CGFloat { isPaper ? 21 * scale : 12.5 }
    var dayFont: CGFloat { isPaper ? 10.5 * scale : 10 }
    var hourFont: CGFloat { isPaper ? 9.5 * scale : 8.5 }
    var codeFont: CGFloat { isPaper ? 10.5 * scale : max(9, 10 * scale) }
    var detailFont: CGFloat { isPaper ? 7.6 * scale : max(7.5, 7.6 * scale) }
    /// Whether a block is wide enough to write the section and the time on one line.
    var wide: Bool { isPaper || columnWidth >= 100 }
  }

  private var ink: Color { style == .paper ? .black : .primary }
  private var inkSoft: Color { style == .paper ? Color(white: 0.33) : Color.primary.opacity(0.7) }
  private var lineColor: Color { style == .paper ? Color(white: 0.62) : Color.primary.opacity(0.22) }

  // MARK: Parts

  private func pageBackground(_ l: Layout) -> some View {
    Group {
      if style == .paper {
        Color.white
      } else {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.12, alpha: 1) : .white })
      }
    }
    .frame(width: size.width, height: size.height)
  }

  private func title(_ l: Layout) -> some View {
    Text(heading)
      .font(.system(size: l.titleFont))
      .foregroundStyle(ink)
      .lineLimit(1)
      .minimumScaleFactor(0.5)
      .padding(.horizontal, 6 * l.scale)
      .frame(height: l.titleHeight)
      .background(style == .paper ? Color(white: 0.85) : Color.secondary.opacity(0.16))
      .frame(width: size.width - 2 * l.margin)
      .offset(x: l.margin, y: l.margin)
  }

  private func lines(_ l: Layout, days: Int) -> some View {
    Path { path in
      let width = l.gridWidth
      // The outer frame includes the header row and the empty cell at its left, as in the printed original.
      path.move(to: CGPoint(x: l.margin, y: l.gridTop))
      path.addLine(to: CGPoint(x: l.margin + width, y: l.gridTop))
      for row in 0...l.rows {
        let y = l.gridTop + l.headerHeight + CGFloat(row) * l.rowHeight
        path.move(to: CGPoint(x: l.margin, y: y))
        path.addLine(to: CGPoint(x: l.margin + width, y: y))
      }
      for column in 0...days {
        let x = l.margin + l.timeColumn + CGFloat(column) * l.columnWidth
        path.move(to: CGPoint(x: x, y: l.gridTop))
        path.addLine(to: CGPoint(x: x, y: l.gridTop + l.gridHeight))
      }
      path.move(to: CGPoint(x: l.margin, y: l.gridTop))
      path.addLine(to: CGPoint(x: l.margin, y: l.gridTop + l.gridHeight))
    }
    .stroke(lineColor, lineWidth: l.isPaper ? 0.5 * l.scale : 0.5)
  }

  private func dayHeaders(_ l: Layout, days: [Weekday]) -> some View {
    TimelineView(.everyMinute) { context in
      let today = Weekday(date: context.date, calendar: .current)
      ZStack(alignment: .topLeading) {
        ForEach(Array(days.enumerated()), id: \.element) { index, day in
          Text(day.name(width: l.columnWidth >= 80 ? .wide : .short))
            .font(.system(size: l.dayFont, weight: style == .screen && day == today ? .bold : .regular))
            .foregroundStyle(style == .screen && day == today ? Color.accentColor : ink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: l.columnWidth, height: l.headerHeight)
            .offset(x: l.margin + l.timeColumn + CGFloat(index) * l.columnWidth, y: l.gridTop)
        }
      }
      .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
  }

  private func hourLabels(_ l: Layout, hours: ClosedRange<Int>) -> some View {
    ZStack(alignment: .topLeading) {
      ForEach(Array(hours.enumerated()), id: \.element) { row, hour in
        Text(Self.label(forHour: hour))
          .font(.system(size: l.hourFont))
          .foregroundStyle(inkSoft)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
          .frame(width: l.timeColumn, height: l.rowHeight)
          .offset(x: l.margin, y: l.gridTop + l.headerHeight + CGFloat(row) * l.rowHeight)
      }
    }
  }

  private func blocks(_ l: Layout, days: [Weekday], hours: ClosedRange<Int>) -> some View {
    ZStack(alignment: .topLeading) {
      ForEach(Array(days.enumerated()), id: \.element) { column, day in
        ForEach(timetable.slots(on: day)) { slot in
          let top = CGFloat(slot.meeting.start.minutes - hours.lowerBound * 60) / 60 * l.rowHeight
          let length = CGFloat(slot.meeting.end.minutes - slot.meeting.start.minutes) / 60 * l.rowHeight
          let inset: CGFloat = l.isPaper ? 0 : 1
          let block = Block(slot: slot, layout: l, style: style, ink: ink, inkSoft: inkSoft, lineColor: lineColor)
            .frame(width: l.columnWidth - 2 * inset, height: max(length - 2 * inset, 10))
          Group {
            if let onSelect {
              Button {
                onSelect(slot)
              } label: {
                block
              }.buttonStyle(.plain)
            } else {
              block
            }
          }
          .offset(
            x: l.margin + l.timeColumn + CGFloat(column) * l.columnWidth + inset,
            y: l.gridTop + l.headerHeight + top + inset)
        }
      }
    }
  }

  /// A thin line across today's column at the current time, as a calendar app draws it.
  private func nowLine(_ l: Layout, days: [Weekday], hours: ClosedRange<Int>) -> some View {
    TimelineView(.everyMinute) { context in
      let calendar = Calendar.current
      let today = Weekday(date: context.date, calendar: calendar)
      let minutes = calendar.component(.hour, from: context.date) * 60 + calendar.component(.minute, from: context.date)
      ZStack(alignment: .topLeading) {
        if timetable.contains(LocalDate(context.date, calendar: calendar)), let column = days.firstIndex(of: today),
          minutes >= hours.lowerBound * 60, minutes < (hours.upperBound + 1) * 60
        {
          let y = l.gridTop + l.headerHeight + CGFloat(minutes - hours.lowerBound * 60) / 60 * l.rowHeight
          Rectangle()
            .fill(Color.red)
            .frame(width: l.columnWidth, height: 1.2)
            .overlay(alignment: .leading) { Circle().fill(Color.red).frame(width: 5, height: 5).offset(x: -2.5) }
            .offset(x: l.margin + l.timeColumn + CGFloat(column) * l.columnWidth, y: y - 0.6)
        }
      }
      .frame(width: size.width, height: size.height, alignment: .topLeading)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }
  }

  /// "Notes:" and a box per course: its colour, code, title and the sections taken (the printed original's legend).
  private func legend(_ l: Layout) -> some View {
    let boxWidth = l.gridWidth / 5
    return ZStack(alignment: .topLeading) {
      Text("Notes:", tableName: "Timetable")
        .font(.system(size: 19 * l.scale))
        .foregroundStyle(ink)
        .padding(.horizontal, 4 * l.scale)
        .background(Color(white: 0.85))
        .offset(x: l.margin, y: l.legendTop)
      ForEach(Array(timetable.courses.enumerated()), id: \.element.id) { index, course in
        VStack(spacing: 2 * l.scale) {
          Text(course.code).font(.system(size: 11 * l.scale, weight: .semibold))
          if !course.title.isEmpty {
            Text(course.title).font(.system(size: 9 * l.scale, weight: .medium)).minimumScaleFactor(0.75)
          }
          if !course.sectionsSummary.isEmpty {
            Text(course.sectionsSummary).font(.system(size: 6.5 * l.scale)).foregroundStyle(Color(white: 0.4))
          }
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(Color.black)
        .padding(3 * l.scale)
        .frame(width: boxWidth, height: 62 * l.scale)
        .background(course.color.blockColor)
        .overlay(Rectangle().stroke(Color(white: 0.62), lineWidth: 0.5 * l.scale))
        .offset(
          x: l.margin + CGFloat(index % 5) * boxWidth, y: l.legendTop + 30 * l.scale + CGFloat(index / 5) * 62 * l.scale
        )
      }
    }
  }

  /// `8 AM`, `1 PM`: always the 12-hour clock, as the printed timetable is written.
  private static func label(forHour hour: Int) -> String {
    let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.setLocalizedDateFormatFromTemplate("ha")
    return formatter.string(from: date)
  }

  // MARK: A class

  /// One class on the grid: the course code, then as much of section, time, room and instructor as the block has room
  /// for (on paper, all of it).
  private struct Block: View {
    let slot: Timetable.Slot
    let layout: Layout
    let style: Style
    let ink: Color
    let inkSoft: Color
    let lineColor: Color

    var body: some View {
      Group {
        if style == .paper {
          content(level: 3)
        } else {
          ViewThatFits(in: .vertical) {
            content(level: 3)
            content(level: 2)
            content(level: 1)
            content(level: 0)
          }
        }
      }
      .padding(layout.isPaper ? 2 * layout.scale : 2)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(slot.course.color.blockColor)
      .overlay(Rectangle().stroke(lineColor, lineWidth: layout.isPaper ? 0.5 * layout.scale : 0.5))
      .accessibilityElement(children: .combine)
    }

    private var timeRange: String { "\(slot.meeting.start.twelveHourText)–\(slot.meeting.end.twelveHourText)" }

    /// Level 3 shows everything, 2 drops section and instructor, 1 keeps the time, 0 only the code.
    private func content(level: Int) -> some View {
      let meeting = slot.meeting
      return VStack(spacing: layout.isPaper ? 1 * layout.scale : 1) {
        Text(slot.course.code)
          .font(.system(size: layout.codeFont, weight: .semibold))
          .foregroundStyle(ink)
        if level >= 3, layout.wide, !meeting.label.isEmpty {
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
        .font(.system(size: layout.detailFont))
        .foregroundStyle(inkSoft)
    }
  }
}

/// The timetable as a one-page A4 PDF, drawn by the same view as the preview but in the printed original's style.
@MainActor
enum TimetablePDF {
  static func data(for timetable: Timetable, heading: String) -> Data? {
    let page = TimetablePage(
      timetable: timetable, heading: heading, style: .paper, size: Paper.a4, showsLegend: true
    )
    .environment(\.colorScheme, .light)
    let renderer = ImageRenderer(content: page)
    renderer.proposedSize = ProposedViewSize(Paper.a4)
    let output = NSMutableData()
    renderer.render { _, draw in
      var box = CGRect(origin: .zero, size: Paper.a4)
      guard let consumer = CGDataConsumer(data: output as CFMutableData),
        let context = CGContext(consumer: consumer, mediaBox: &box, nil)
      else { return }
      context.beginPDFPage(nil)
      draw(context)
      context.endPDFPage()
      context.closePDF()
    }
    return output.length > 0 ? output as Data : nil
  }
}
