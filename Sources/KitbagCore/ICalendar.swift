import Foundation

/// Reading iCalendar (`.ics`) text: the events and tasks in a file or a calendar feed.
public enum ICalendar {
  /// A content line: `NAME;PARAM=value:value`.
  struct Line {
    let name: String
    let parameters: [String: String]
    let value: String
  }

  /// The events and tasks in the text, in file order. Lines it cannot read are skipped, not fatal.
  public static func parse(_ text: String, defaultTimeZone: TimeZone = .current) -> [CalendarEvent] {
    var events: [CalendarEvent] = []
    var current: [Line]?
    var kind = ""
    var alarmDepth = 0
    for raw in unfold(text) {
      guard let line = parseLine(raw) else { continue }
      switch (line.name, line.value.uppercased()) {
      case ("BEGIN", "VEVENT"), ("BEGIN", "VTODO"):
        current = []
        kind = line.value.uppercased()
        alarmDepth = 0
      case ("BEGIN", "VALARM"):
        if current != nil { alarmDepth += 1 }
      case ("END", "VALARM"):
        alarmDepth = max(alarmDepth - 1, 0)
      case ("END", "VEVENT"), ("END", "VTODO"):
        if let lines = current, let event = makeEvent(lines, isTask: kind == "VTODO", defaultTimeZone: defaultTimeZone)
        {
          events.append(event)
        }
        current = nil
      default:
        if current != nil, alarmDepth == 0 { current?.append(line) }
      }
    }
    return events
  }

  // MARK: Lines

  /// Joins folded lines (a line that continues on the next starts with a space or a tab) and splits on line ends.
  static func unfold(_ text: String) -> [String] {
    var lines: [String] = []
    let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    for piece in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
      if let first = piece.first, first == " " || first == "\t", !lines.isEmpty {
        lines[lines.count - 1] += piece.dropFirst()
      } else {
        lines.append(String(piece))
      }
    }
    return lines.filter { !$0.isEmpty }
  }

  static func parseLine(_ raw: String) -> Line? {
    // The first colon outside double quotes separates the name and parameters from the value.
    var inQuotes = false
    var split: String.Index?
    for index in raw.indices {
      let character = raw[index]
      if character == "\"" { inQuotes.toggle() }
      if character == ":" && !inQuotes {
        split = index
        break
      }
    }
    guard let split else { return nil }
    let head = raw[..<split]
    let value = String(raw[raw.index(after: split)...])
    var parts: [String] = []
    var piece = ""
    inQuotes = false
    for character in head {
      if character == "\"" { inQuotes.toggle() }
      if character == ";" && !inQuotes {
        parts.append(piece)
        piece = ""
      } else {
        piece.append(character)
      }
    }
    parts.append(piece)
    guard let name = parts.first?.uppercased(), !name.isEmpty else { return nil }
    var parameters: [String: String] = [:]
    for parameter in parts.dropFirst() {
      guard let equals = parameter.firstIndex(of: "=") else { continue }
      let key = parameter[..<equals].uppercased()
      parameters[key] = String(parameter[parameter.index(after: equals)...]).trimmingCharacters(
        in: CharacterSet(charactersIn: "\""))
    }
    return Line(name: name, parameters: parameters, value: value)
  }

  /// Undoes iCalendar's text escapes: `\n`, `\,`, `\;` and `\\`.
  static func unescape(_ text: String) -> String {
    var result = ""
    var iterator = text.makeIterator()
    while let character = iterator.next() {
      guard character == "\\", let next = iterator.next() else {
        result.append(character)
        continue
      }
      switch next {
      case "n", "N": result.append("\n")
      case ",", ";", "\\": result.append(next)
      default: result.append(next)
      }
    }
    return result
  }

  // MARK: Dates

  private static let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
  }()

  /// `20261022`, `20261022T130000` or `20261022T130000Z`, read in the line's time zone. All-day dates are midnight UTC.
  static func parseDate(_ line: Line, defaultTimeZone: TimeZone) -> (date: Date, allDay: Bool, zoneID: String?)? {
    let text = line.value.trimmingCharacters(in: .whitespaces)
    let digits = text.filter(\.isNumber)
    if line.parameters["VALUE"] == "DATE" || (text.count == 8 && digits.count == 8) {
      guard digits.count >= 8, let year = Int(digits.prefix(4)), let month = Int(digits.dropFirst(4).prefix(2)),
        let day = Int(digits.dropFirst(6).prefix(2)),
        let date = utc.date(from: DateComponents(year: year, month: month, day: day))
      else { return nil }
      return (date, true, nil)
    }
    guard digits.count >= 12, let year = Int(digits.prefix(4)), let month = Int(digits.dropFirst(4).prefix(2)),
      let day = Int(digits.dropFirst(6).prefix(2)), let hour = Int(digits.dropFirst(8).prefix(2)),
      let minute = Int(digits.dropFirst(10).prefix(2))
    else { return nil }
    let second = digits.count >= 14 ? Int(digits.dropFirst(12).prefix(2)) ?? 0 : 0
    var calendar = Calendar(identifier: .gregorian)
    var zoneID: String?
    if text.hasSuffix("Z") {
      calendar.timeZone = .gmt
    } else if let tzid = line.parameters["TZID"], let zone = TimeZone(identifier: tzid) {
      calendar.timeZone = zone
      zoneID = zone.identifier
    } else {
      calendar.timeZone = defaultTimeZone
    }
    guard
      let date = calendar.date(
        from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))
    else { return nil }
    return (date, false, zoneID ?? (text.hasSuffix("Z") ? nil : defaultTimeZone.identifier))
  }

  /// `PT1H30M`, `P1D`, `P2W`: the length in seconds.
  static func parseDuration(_ text: String) -> TimeInterval? {
    var seconds = 0.0
    var number = ""
    var inTime = false
    var sign = 1.0
    for character in text.trimmingCharacters(in: .whitespaces) {
      switch character {
      case "-": sign = -1
      case "P", "+": continue
      case "T": inTime = true
      case "W":
        seconds += (Double(number) ?? 0) * 7 * 86400
        number = ""
      case "D":
        seconds += (Double(number) ?? 0) * 86400
        number = ""
      case "H":
        seconds += (Double(number) ?? 0) * 3600
        number = ""
      case "M":
        seconds += (Double(number) ?? 0) * (inTime ? 60 : 0)
        number = ""
      case "S":
        seconds += Double(number) ?? 0
        number = ""
      default: if character.isNumber { number.append(character) } else { return nil }
      }
    }
    return sign * seconds
  }

  // MARK: Recurrence

  private static let weekdayCodes: [String: Weekday] = [
    "MO": .monday, "TU": .tuesday, "WE": .wednesday, "TH": .thursday, "FR": .friday, "SA": .saturday, "SU": .sunday,
  ]

  /// Reads `FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;COUNT=10;UNTIL=20261209T000000Z`. Rules it does not understand give nil.
  static func parseRule(_ text: String, defaultTimeZone: TimeZone) -> Recurrence? {
    var parts: [String: String] = [:]
    for pair in text.split(separator: ";") {
      let kv = pair.split(separator: "=", maxSplits: 1)
      if kv.count == 2 { parts[kv[0].uppercased()] = String(kv[1]) }
    }
    guard let rawFrequency = parts["FREQ"]?.lowercased(), let frequency = Recurrence.Frequency(rawValue: rawFrequency)
    else {
      return nil
    }
    var days: [Weekday] = []
    for code in (parts["BYDAY"] ?? "").split(separator: ",") {
      // Codes with a count in front (`1MO`, the first Monday) mean more than this reader handles.
      guard let day = weekdayCodes[String(code).uppercased()] else { return nil }
      days.append(day)
    }
    if parts["BYMONTHDAY"] != nil || parts["BYSETPOS"] != nil || parts["BYMONTH"] != nil && frequency != .yearly {
      return nil
    }
    var until: Date?
    if let value = parts["UNTIL"] {
      var untilLine = Line(name: "UNTIL", parameters: [:], value: value)
      if value.count == 8 { untilLine = Line(name: "UNTIL", parameters: ["VALUE": "DATE"], value: value) }
      if let parsed = parseDate(untilLine, defaultTimeZone: defaultTimeZone) {
        until = parsed.allDay ? parsed.date.addingTimeInterval(86400 - 1) : parsed.date
      }
    }
    return Recurrence(
      frequency: frequency, interval: Int(parts["INTERVAL"] ?? "") ?? 1, count: Int(parts["COUNT"] ?? ""), until: until,
      days: days)
  }

  // MARK: Events

  private static func makeEvent(_ lines: [Line], isTask: Bool, defaultTimeZone: TimeZone) -> CalendarEvent? {
    func first(_ name: String) -> Line? { lines.first { $0.name == name } }
    guard let startLine = first("DTSTART") ?? (isTask ? first("DUE") : nil),
      let start = parseDate(startLine, defaultTimeZone: defaultTimeZone)
    else { return nil }
    var end: Date?
    if isTask {
      end = nil
    } else if let endLine = first("DTEND"), let parsed = parseDate(endLine, defaultTimeZone: defaultTimeZone) {
      end = parsed.date
    } else if let duration = first("DURATION")?.value, let length = parseDuration(duration) {
      end = start.date.addingTimeInterval(length)
    }
    // A task that has both a start and a due moment is shown at its due moment.
    var when = start
    if isTask, let due = first("DUE"), let parsed = parseDate(due, defaultTimeZone: defaultTimeZone) { when = parsed }
    let status = first("STATUS")?.value.uppercased() ?? ""
    let completed = isTask && (status == "COMPLETED" || first("COMPLETED") != nil)
    let uid = first("UID")?.value ?? "\(first("SUMMARY")?.value ?? "event")-\(when.date.timeIntervalSince1970)"
    let rule = first("RRULE").flatMap { parseRule($0.value, defaultTimeZone: defaultTimeZone) }
    var exceptions: [Date] = []
    for line in lines where line.name == "EXDATE" {
      for piece in line.value.split(separator: ",") {
        let single = Line(name: "EXDATE", parameters: line.parameters, value: String(piece))
        if let parsed = parseDate(single, defaultTimeZone: defaultTimeZone) { exceptions.append(parsed.date) }
      }
    }
    return CalendarEvent(
      id: uid, title: unescape(first("SUMMARY")?.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
      notes: unescape(first("DESCRIPTION")?.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
      location: unescape(first("LOCATION")?.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
      start: when.date,
      end: end, isAllDay: when.allDay, isTask: isTask, isCompleted: completed, recurrence: rule, exceptions: exceptions,
      timeZoneID: when.zoneID, kitbagKind: first("X-KITBAG-KIND")?.value,
      kitbagCourse: first("X-KITBAG-COURSE").map { unescape($0.value) },
      kitbagDone: first("X-KITBAG-DONE")?.value.uppercased() == "TRUE")
  }
}
