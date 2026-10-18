import SwiftUI
import UserNotifications

@main
struct KitbagApp: App {
  /// The guests start with Kitbag, not when their tile is tapped: some of them register background tasks, and iOS only
  /// accepts that before the app has finished launching.
  @State private var guests = GuestRuntimes()
  @State private var timetable = TimetableStore()
  @State private var deadlines = DeadlineStore()
  @State private var notes = NoteStore()
  @State private var weather = WeatherStore()
  @State private var subscriptions = SubscriptionStore()
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
      .environment(subscriptions)
      .environment(themes)
      .environment(layout)
      .task {
        // Kitbag's own handler comes after the guests', which set theirs when they start.
        UNUserNotificationCenter.current().delegate = KitbagNotificationDelegate.shared
        deadlines.courseCode = { [timetable] in timetable.course(id: $0)?.code }
        deadlines.syncReminders()
      }
      .task { await weather.refresh() }
      .task { await subscriptions.refreshStale() }
      #if DEBUG
        .task { exportPDFIfAsked() }
      #endif
      .task { WidgetBridge.sync(theme: themes.themeID) }
      .onChange(of: themes.themeID) { _, id in WidgetBridge.sync(theme: id) }
      .onChange(of: timetable.timetable.courses.map(\.code)) { _, _ in deadlines.syncReminders() }
      .onChange(of: scenePhase) { _, phase in
        // The widgets read a copy of the data; bring it up to date when the app is left as well as when it is entered.
        WidgetBridge.sync(theme: themes.themeID)
        if phase == .active {
          deadlines.syncReminders()
          Task { await weather.refresh() }
          Task { await subscriptions.refreshStale() }
        }
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
