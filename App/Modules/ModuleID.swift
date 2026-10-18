import SwiftUI

/// The tools on the home screen, in the order they appear.
enum ModuleID: String, CaseIterable, Identifiable {
  case headway

  var id: String { rawValue }

  var title: LocalizedStringResource {
    switch self {
    case .headway: LocalizedStringResource("Headway", table: "Shell")
    }
  }

  /// The icon of a guest app: the file `Guests/GuestIcons/<name>.png` that tools/sync_guests.sh copies from the guest.
  var guestIconName: String? {
    switch self {
    case .headway: "Headway"
    }
  }

  /// The tool itself, shown full screen when its tile is tapped.
  @MainActor @ViewBuilder
  func content(guests: GuestRuntimes) -> some View {
    switch self {
    case .headway: HeadwayGuestView(runtime: guests.headway)
    }
  }
}
