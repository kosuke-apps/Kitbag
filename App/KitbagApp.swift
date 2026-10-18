import SwiftUI

@main
struct KitbagApp: App {
  /// The guests start with Kitbag, not when their tile is tapped: some of them register background tasks, and iOS only
  /// accepts that before the app has finished launching.
  @State private var guests = GuestRuntimes()
  @State private var timetable = TimetableStore()

  var body: some Scene {
    WindowGroup {
      HomeView()
        .environment(guests)
        .environment(timetable)
    }
  }
}
