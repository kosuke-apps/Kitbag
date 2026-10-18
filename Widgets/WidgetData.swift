import KitbagCore
import SwiftUI
import WidgetKit

/// What the widgets show, read from the copy that the app keeps in the App Group folder (`WidgetBridge`).
struct KitbagSnapshot {
  var library = TimetableLibrary()
  var deadlines = DeadlineBook()
  var theme = ThemeID.ivory

  static func load() -> KitbagSnapshot {
    var snapshot = KitbagSnapshot()
    if let url = AppGroup.url("timetables.json"), let data = try? Data(contentsOf: url),
      let library = try? TimetableLibrary(fileData: data)
    {
      snapshot.library = library
    }
    if let url = AppGroup.url("deadlines.json"), let data = try? Data(contentsOf: url),
      let deadlines = try? DeadlineBook(fileData: data)
    {
      snapshot.deadlines = deadlines
    }
    if let url = AppGroup.url(AppGroup.settingsFile), let data = try? Data(contentsOf: url),
      let settings = try? JSONDecoder().decode(WidgetSettings.self, from: data),
      let id = ThemeID(rawValue: settings.theme)
    {
      snapshot.theme = id
    }
    return snapshot
  }

  /// Made-up data for the widget gallery and for a widget that has nothing to show yet.
  static var sample: KitbagSnapshot {
    let lecture = Meeting(
      kind: "LEC", section: "001", days: Weekday.allCases, start: TimeOfDay(hour: 9, minute: 55),
      end: TimeOfDay(hour: 10, minute: 45), location: "Hall 101")
    let lab = Meeting(
      kind: "LAB", section: "002", days: Weekday.allCases, start: TimeOfDay(hour: 13, minute: 20),
      end: TimeOfDay(hour: 15, minute: 15), location: "Lab 22")
    let courses = [
      Course(code: "MATH 101", title: "Calculus", color: .periwinkle, meetings: [lecture]),
      Course(code: "PHYS 202", title: "Mechanics", color: .mint, meetings: [lab]),
    ]
    var snapshot = KitbagSnapshot()
    snapshot.library = TimetableLibrary(timetables: [Timetable(title: "Sample", courses: courses)])
    snapshot.deadlines = DeadlineBook(deadlines: [
      Deadline(
        title: "Problem set 4", kind: .assignment,
        date: LocalDate(Date().addingTimeInterval(86400), calendar: .current),
        time: TimeOfDay(hour: 23, minute: 59)),
      Deadline(
        title: "Midterm", kind: .exam, date: LocalDate(Date().addingTimeInterval(4 * 86400), calendar: .current)),
    ])
    return snapshot
  }
}

struct KitbagEntry: TimelineEntry {
  let date: Date
  let snapshot: KitbagSnapshot

  var calendar: Calendar { .current }

  /// The term in force on this entry's day.
  var term: Timetable? { snapshot.library.active(on: date, calendar: calendar) }

  /// The class on now or next.
  var upcoming: Timetable.Upcoming? { term?.upcoming(after: date, calendar: calendar) }

  /// The classes on the day that `day` falls on, with their start and end, earliest first.
  func classes(onDayOf day: Date) -> [(slot: Timetable.Slot, start: Date, end: Date)] {
    guard let term else { return [] }
    let dayStart = calendar.startOfDay(for: day)
    return term.slots(on: LocalDate(dayStart, calendar: calendar), calendar: calendar).map { slot in
      (
        slot,
        calendar.date(byAdding: .minute, value: slot.meeting.start.minutes, to: dayStart) ?? dayStart,
        calendar.date(byAdding: .minute, value: slot.meeting.end.minutes, to: dayStart) ?? dayStart
      )
    }
  }

  /// The day whose classes a list should show: today while any class is still to come or on, else the day of the next one.
  var listDay: Date {
    guard let upcoming else { return date }
    return calendar.startOfDay(for: upcoming.start)
  }

  /// The code of a course in any term, for a deadline's label.
  func courseCode(_ id: UUID?) -> String? {
    guard let id else { return nil }
    return snapshot.library.timetables.lazy.compactMap { $0.course(id: id)?.code }.first
  }

  /// Open deadlines that are still to come, soonest first.
  var openDeadlines: [Deadline] {
    snapshot.deadlines.deadlines
      .filter { !$0.isDone && $0.dueInstant(calendar: calendar) >= date }
      .sorted { $0.dueInstant(calendar: calendar) < $1.dueInstant(calendar: calendar) }
  }
}
