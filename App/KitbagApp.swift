import SwiftUI

@main
struct KitbagApp: App {
  /// The guests start with Kitbag, not when their tile is tapped: some of them register background tasks, and iOS only
  /// accepts that before the app has finished launching.
  @State private var guests = GuestRuntimes()
  @State private var timetable = TimetableStore()
  @State private var deadlines = DeadlineStore()
  @State private var notes = NoteStore()
  @State private var weather = WeatherStore()
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      HomeView()
        .environment(guests)
        .environment(timetable)
        .environment(deadlines)
        .environment(notes)
        .environment(weather)
        .task { await weather.refresh() }
        .onChange(of: scenePhase) { _, phase in
          if phase == .active { Task { await weather.refresh() } }
        }
    }
  }
}
