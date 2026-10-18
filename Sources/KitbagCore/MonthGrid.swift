import Foundation

/// The weeks of one month as a calendar page draws them: whole weeks, starting on the calendar's first weekday, with
/// the days of the neighbouring months that fill the first and last row.
public struct MonthGrid: Hashable, Sendable {
  /// The first day of the month.
  public let month: LocalDate
  /// Four to six rows of seven days.
  public let weeks: [[LocalDate]]

  public init(containing day: LocalDate, calendar: Calendar) {
    let first = LocalDate(year: day.year, month: day.month, day: 1)
    let gregorian = LocalDate.gregorian(like: calendar)
    let firstDate = first.date(calendar: calendar)
    let dayCount = gregorian.range(of: .day, in: .month, for: firstDate)?.count ?? 30
    // `Calendar` numbers Sunday as 1; the offset is how many days of the previous month sit in the first row.
    let weekdayOfFirst = gregorian.component(.weekday, from: firstDate)
    let offset = (weekdayOfFirst - gregorian.firstWeekday + 7) % 7
    let rows = (offset + dayCount + 6) / 7
    let start = first.adding(days: -offset, calendar: calendar)
    self.month = first
    self.weeks = (0..<rows).map { row in
      (0..<7).map { column in start.adding(days: row * 7 + column, calendar: calendar) }
    }
  }

  public func contains(_ day: LocalDate) -> Bool {
    day.year == month.year && day.month == month.month
  }

  /// The same grid some months later (or earlier).
  public func shifted(by months: Int, calendar: Calendar) -> MonthGrid {
    let moved = (month.year * 12 + (month.month - 1)) + months
    let year = Int((Double(moved) / 12).rounded(.down))
    return MonthGrid(containing: LocalDate(year: year, month: moved - year * 12 + 1, day: 1), calendar: calendar)
  }

  /// The weekdays in the order the columns run, starting with the calendar's first weekday.
  public static func columnOrder(calendar: Calendar) -> [Weekday] {
    (0..<7).map { column in
      // `Calendar` numbers Sunday as 1; `Weekday` numbers Monday as 1.
      let number = (column + calendar.firstWeekday - 1) % 7 + 1
      return Weekday(rawValue: number == 1 ? 7 : number - 1) ?? .monday
    }
  }
}
