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
  @State private var themes = ThemeStore()
  @State private var layout = LayoutStore()
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      ThemeRoot {
        HomeView()
      }
      .environment(guests)
      .environment(timetable)
      .environment(deadlines)
      .environment(notes)
      .environment(weather)
      .environment(themes)
      .environment(layout)
      .task { await weather.refresh() }
      #if DEBUG
        .task { exportPDFIfAsked() }
      #endif
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { Task { await weather.refresh() } }
      }
    }
  }
}

#if DEBUG
  extension KitbagApp {
    /// For checking the PDF from the command line: launch with `-kitbagExportPDF <path>` and the current term's page is
    /// written there. Only in debug builds.
    @MainActor fileprivate func exportPDFIfAsked() {
      guard let path = UserDefaults.standard.string(forKey: "kitbagExportPDF") else { return }
      let term = timetable.timetable
      if let data = TimetablePDF.data(for: term, heading: term.pageHeading) {
        try? data.write(to: URL(fileURLWithPath: path))
      }
    }
  }
#endif
