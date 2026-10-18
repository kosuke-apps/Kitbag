import KitbagCore
import SwiftUI

/// How a tool's tile is drawn on the home screen.
enum ModuleIcon {
  /// The icon of a guest app: the file `Guests/GuestIcons/<name>.png` that tools/sync_guests.sh copies from the guest.
  case guest(String)
  /// A tool made for Kitbag: an SF Symbol in white on a coloured rounded square.
  case symbol(String, Color)
}

/// A tool to open, and where in it to start: the Today screen opens the calendar on a day, or the notes on a note.
struct ModuleRoute: Identifiable {
  let module: ModuleID
  var day: LocalDate?
  var noteID: UUID?

  init(_ module: ModuleID, day: LocalDate? = nil, noteID: UUID? = nil) {
    self.module = module
    self.day = day
    self.noteID = noteID
  }

  var id: String { "\(module.rawValue)|\(day?.text ?? "")|\(noteID?.uuidString ?? "")" }
}

/// The tools on the home screen, in the order they appear.
enum ModuleID: String, CaseIterable, Identifiable {
  case timetable
  case calendar
  case notes
  case headway

  var id: String { rawValue }

  var title: LocalizedStringResource {
    switch self {
    case .timetable: LocalizedStringResource("Timetable", table: "Shell")
    case .calendar: LocalizedStringResource("Calendar", table: "Shell")
    case .notes: LocalizedStringResource("Notes", table: "Shell")
    case .headway: LocalizedStringResource("Headway", table: "Shell")
    }
  }

  var icon: ModuleIcon {
    switch self {
    case .timetable: .symbol("tablecells.fill", Color(red: 0.36, green: 0.34, blue: 0.84))
    case .calendar: .symbol("calendar", Color(red: 0.93, green: 0.31, blue: 0.30))
    case .notes: .symbol("note.text", Color(red: 0.96, green: 0.68, blue: 0.10))
    case .headway: .guest("Headway")
    }
  }

  /// The tool itself, shown full screen when its tile is tapped.
  @MainActor @ViewBuilder
  func content(guests: GuestRuntimes, route: ModuleRoute) -> some View {
    switch self {
    case .timetable: TimetableView()
    case .calendar: CalendarView(initialDay: route.day)
    case .notes: NotesView(initialNoteID: route.noteID)
    case .headway: HeadwayGuestView(runtime: guests.headway)
    }
  }
}
