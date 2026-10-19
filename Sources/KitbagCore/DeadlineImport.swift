import Foundation

/// Turning calendar events into deadlines.
public enum DeadlineImport {
  /// Words that make an event an exam, a quiz or a project; everything else is taken for an assignment.
  static func guessKind(_ title: String) -> DeadlineKind {
    let lower = title.lowercased()
    if ["exam", "midterm", "final", "試験", "テスト"].contains(where: lower.contains) { return .exam }
    if ["quiz", "小テスト"].contains(where: lower.contains) { return .quiz }
    if ["project", "プロジェクト", "presentation"].contains(where: lower.contains) { return .project }
    return .assignment
  }

  /// The course whose code appears in the text, ignoring spaces and case: `QR352` finds `Q R 352`.
  static func matchCourse(in text: String, courses: [Course]) -> Course? {
    func squash(_ string: String) -> String { string.lowercased().filter { !$0.isWhitespace } }
    let haystack = squash(text)
    return courses.filter { !$0.code.isEmpty && haystack.contains(squash($0.code)) }
      .max { $0.code.count < $1.code.count }
  }

  /// The deadlines in a set of events: each task or event as one (a repeating event once for each time it falls within
  /// `window`). Deadlines that came from the same event in an earlier import keep their id and their alerts, so importing
  /// again updates; a new one gets the alerts `defaultAlerts` gives for its kind (the person's own choice, in the app).
  public static func deadlines(
    from events: [CalendarEvent], courses: [Course], existing: [Deadline] = [], calendar: Calendar,
    window: DateInterval,
    defaultAlerts: (DeadlineKind) -> [DeadlineAlert] = { DeadlineAlert.standard(for: $0) }
  ) -> [Deadline] {
    var results: [Deadline] = []
    for event in events {
      for occurrence in event.occurrences(in: window, calendar: calendar) {
        let day = event.day(of: occurrence.start, calendar: calendar)
        let time: TimeOfDay? =
          event.isAllDay
          ? nil
          : TimeOfDay(
            hour: calendar.component(.hour, from: occurrence.start),
            minute: calendar.component(.minute, from: occurrence.start))
        let uid = event.recurrence == nil ? event.id : "\(event.id)#\(day.text)"
        let kind: DeadlineKind =
          event.kitbagKind.flatMap(DeadlineKind.init(rawValue:)) ?? guessKind(event.title)
        let course = matchCourse(in: event.kitbagCourse ?? event.title, courses: courses)
        let previous = existing.first { $0.sourceUID == uid }
        results.append(
          Deadline(
            id: previous?.id ?? UUID(), title: event.title.isEmpty ? "(untitled)" : event.title, kind: kind,
            courseID: previous?.courseID ?? course?.id, date: day, time: time,
            isDone: previous?.isDone ?? (event.isCompleted || event.kitbagDone), note: event.notes,
            alerts: previous?.alerts ?? DeadlineAlert.normalized(defaultAlerts(kind), hasTime: time != nil),
            sourceUID: uid))
      }
    }
    return results.sorted { ($0.date, $0.time?.minutes ?? 0, $0.title) < ($1.date, $1.time?.minutes ?? 0, $1.title) }
  }
}
