import SwiftUI

/// How a tool's tile is drawn on the home screen.
enum ModuleIcon {
  /// The icon of a guest app: the file `Guests/GuestIcons/<name>.png` that tools/sync_guests.sh copies from the guest.
  case guest(String)
  /// A tool made for Kitbag: an SF Symbol in white on a coloured rounded square.
  case symbol(String, Color)
}

/// The tools on the home screen, in the order they appear.
enum ModuleID: String, CaseIterable, Identifiable {
  case timetable
  case headway

  var id: String { rawValue }

  var title: LocalizedStringResource {
    switch self {
    case .timetable: LocalizedStringResource("Timetable", table: "Shell")
    case .headway: LocalizedStringResource("Headway", table: "Shell")
    }
  }

  var icon: ModuleIcon {
    switch self {
    case .timetable: .symbol("tablecells.fill", Color(red: 0.36, green: 0.34, blue: 0.84))
    case .headway: .guest("Headway")
    }
  }

  /// The tool itself, shown full screen when its tile is tapped.
  @MainActor @ViewBuilder
  func content(guests: GuestRuntimes) -> some View {
    switch self {
    case .timetable: TimetableView()
    case .headway: HeadwayGuestView(runtime: guests.headway)
    }
  }
}
