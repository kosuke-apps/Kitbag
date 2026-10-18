import Foundation

/// Writing iCalendar (`.ics`) text: deadlines and the weekly classes of a term, for other calendar apps.
public enum ICSWriter {
  // MARK: Deadlines

  /// Every deadline as an event, with a reminder alarm for each of its alerts. Kitbag's own fields (kind, course, done) are
  /// written as `X-KITBAG-…` lines, which other apps ignore and Kitbag reads back.
  public static func deadlines(
    _ deadlines: [Deadline], courseCode: (UUID) -> String?, calendar: Calendar, now: Date = Date(),
    allDayTime: TimeOfDay = .usualReminder
  ) -> String {
    var out = header()
    for deadline in deadlines {
      let code = deadline.courseID.flatMap(courseCode)
      out += lines(for: deadline, code: code, calendar: calendar, now: now, allDayTime: allDayTime)
    }
    return out + "END:VCALENDAR\r\n"
  }

  private static func lines(
    for deadline: Deadline, code: String?, calendar: Calendar, now: Date, allDayTime: TimeOfDay
  ) -> String {
    var event = ["BEGIN:VEVENT", "UID:\(deadline.id.uuidString)@kitbag", "DTSTAMP:\(utcStamp(now))"]
    event.append("SUMMARY:\(escape(deadline.title))")
    if let time = deadline.time {
      let start = deadline.date.date(calendar: calendar).addingTimeInterval(0)
      let begin = calendar.date(byAdding: .minute, value: time.minutes, to: start) ?? start
      let finish = begin.addingTimeInterval(30 * 60)
      event.append("DTSTART;TZID=\(calendar.timeZone.identifier):\(localStamp(begin, calendar))")
      event.append("DTEND;TZID=\(calendar.timeZone.identifier):\(localStamp(finish, calendar))")
    } else {
      event.append("DTSTART;VALUE=DATE:\(dayStamp(deadline.date))")
      event.append("DTEND;VALUE=DATE:\(dayStamp(deadline.date.adding(days: 1, calendar: calendar)))")
    }
    let description = [code, deadline.note].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
    if !description.isEmpty { event.append("DESCRIPTION:\(escape(description))") }
    event.append("CATEGORIES:\(deadline.kind.rawValue.uppercased())")
    event.append("X-KITBAG-KIND:\(deadline.kind.rawValue)")
    if let code { event.append("X-KITBAG-COURSE:\(escape(code))") }
    if deadline.isDone { event.append("X-KITBAG-DONE:TRUE") }
    if !deadline.isDone {
      for (_, fire) in deadline.alertDates(defaultTime: allDayTime, calendar: calendar) {
        event += [
          "BEGIN:VALARM", "ACTION:DISPLAY", "DESCRIPTION:\(escape(deadline.title))",
          "TRIGGER;VALUE=DATE-TIME:\(utcStamp(fire))", "END:VALARM",
        ]
      }
    }
    event.append("END:VEVENT")
    return event.map(fold).joined()
  }

  // MARK: Classes

  /// Each class of a term as a weekly repeating event, from the first day of the term to its last (sixteen weeks when the
  /// term has no end).
  public static func classes(of term: Timetable, calendar: Calendar, now: Date = Date()) -> String {
    var out = header()
    let from = term.startDate ?? LocalDate(now, calendar: calendar)
    for course in term.courses {
      for meeting in course.meetings where !meeting.days.isEmpty {
        guard
          let firstDay = (0..<7).map({ from.adding(days: $0, calendar: calendar) }).first(where: {
            meeting.days.contains($0.weekday(calendar: calendar))
          })
        else { continue }
        let dayStart = firstDay.date(calendar: calendar)
        let begin = calendar.date(byAdding: .minute, value: meeting.start.minutes, to: dayStart) ?? dayStart
        let finish = calendar.date(byAdding: .minute, value: meeting.end.minutes, to: dayStart) ?? dayStart
        let byDay = meeting.days.map { dayCode($0) }.joined(separator: ",")
        var rule = "FREQ=WEEKLY;BYDAY=\(byDay)"
        if let end = term.endDate {
          let endOfLast = calendar.date(byAdding: .minute, value: 24 * 60 - 1, to: end.date(calendar: calendar)) ?? now
          rule += ";UNTIL=\(utcStamp(endOfLast))"
        } else {
          rule += ";COUNT=\(16 * meeting.days.count)"
        }
        var event = [
          "BEGIN:VEVENT", "UID:\(course.id.uuidString)-\(meeting.id.uuidString)@kitbag", "DTSTAMP:\(utcStamp(now))",
          "SUMMARY:\(escape([course.code, meeting.label].filter { !$0.isEmpty }.joined(separator: " · ")))",
          "DTSTART;TZID=\(calendar.timeZone.identifier):\(localStamp(begin, calendar))",
          "DTEND;TZID=\(calendar.timeZone.identifier):\(localStamp(finish, calendar))", "RRULE:\(rule)",
        ]
        if !meeting.location.isEmpty { event.append("LOCATION:\(escape(meeting.location))") }
        let description = [course.title, meeting.instructor].filter { !$0.isEmpty }.joined(separator: "\n")
        if !description.isEmpty { event.append("DESCRIPTION:\(escape(description))") }
        event.append("END:VEVENT")
        out += event.map(fold).joined()
      }
    }
    return out + "END:VCALENDAR\r\n"
  }

  // MARK: Text

  private static func header() -> String {
    ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Kosuke Satake//Kitbag//EN", "CALSCALE:GREGORIAN"].map(fold).joined()
  }

  static func escape(_ text: String) -> String {
    text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ";", with: "\\;")
      .replacingOccurrences(of: ",", with: "\\,").replacingOccurrences(of: "\r\n", with: "\\n")
      .replacingOccurrences(of: "\n", with: "\\n")
  }

  /// A line, folded so that no line is longer than 75 bytes, and ended with CRLF.
  static func fold(_ line: String) -> String {
    var out = ""
    var length = 0
    for character in line {
      let size = String(character).utf8.count
      if length + size > 74 {
        out += "\r\n "
        length = 1
      }
      out.append(character)
      length += size
    }
    return out + "\r\n"
  }

  private static func dayCode(_ day: Weekday) -> String {
    ["MO", "TU", "WE", "TH", "FR", "SA", "SU"][day.rawValue - 1]
  }

  private static func formatter(_ format: String, zone: TimeZone) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = zone
    formatter.dateFormat = format
    return formatter
  }

  static func utcStamp(_ date: Date) -> String { formatter("yyyyMMdd'T'HHmmss'Z'", zone: .gmt).string(from: date) }

  static func localStamp(_ date: Date, _ calendar: Calendar) -> String {
    formatter("yyyyMMdd'T'HHmmss", zone: calendar.timeZone).string(from: date)
  }

  static func dayStamp(_ day: LocalDate) -> String { String(format: "%04d%02d%02d", day.year, day.month, day.day) }
}
