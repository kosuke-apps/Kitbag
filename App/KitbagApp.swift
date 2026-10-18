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
  @State private var notificationPreferences = NotificationPreferencesStore()
  @State private var gradeScales = GradeScaleStore()
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
      .environment(notificationPreferences)
      .environment(gradeScales)
      .task {
        // Kitbag's own handler comes after the guests', which set theirs when they start.
        UNUserNotificationCenter.current().delegate = KitbagNotificationDelegate.shared
        deadlines.courseCode = { [timetable] in timetable.course(id: $0)?.code }
        deadlines.library = { [timetable] in timetable.library }
        deadlines.preferences = { [notificationPreferences] in notificationPreferences.preferences }
        deadlines.syncReminders()
      }
      .task { await weather.refresh() }
      .task { await subscriptions.refreshStale() }
      #if DEBUG
        .task { exportPDFIfAsked() }
        .task { backupIfAsked() }
        .task { importTimetableIfAsked() }
      #endif
      .task {
        deadlines.applyWidgetActions()
        WidgetBridge.sync(theme: themes.themeID)
      }
      .onChange(of: themes.themeID) { _, id in WidgetBridge.sync(theme: id) }
      .onChange(of: timetable.library) { _, _ in deadlines.syncReminders() }
      .onChange(of: notificationPreferences.preferences) { _, _ in deadlines.syncReminders() }
      .onChange(of: scenePhase) { _, phase in
        // The widgets read a copy of the data; bring it up to date when the app is left as well as when it is entered.
        // What a widget queued (a deadline ticked off) is applied first, so that the copy does not undo it.
        deadlines.applyWidgetActions()
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
    /// For putting a timetable file on a phone from the Mac without touching it: copy the file into the app's folder with
    /// `devicectl device copy to`, then launch with `-kitbagImportTimetable <file name>` (a file in the app's Documents folder). Only in debug builds.
    @MainActor fileprivate func importTimetableIfAsked() {
      guard let name = UserDefaults.standard.string(forKey: "kitbagImportTimetable") else { return }
      _ = try? timetable.importFile(at: URL.documentsDirectory.appending(path: name))
      WidgetBridge.sync(theme: themes.themeID)
    }

    /// For checking backups from the command line: `-kitbagBackupTo <path>` writes a backup there, and
    /// `-kitbagRestoreFrom <path>` restores one. Only in debug builds.
    @MainActor fileprivate func backupIfAsked() {
      if let path = UserDefaults.standard.string(forKey: "kitbagBackupTo"),
        let file = try? BackupManager().makeTemporaryBackup()
      {
        try? FileManager.default.removeItem(atPath: path)
        try? FileManager.default.copyItem(at: file, to: URL(fileURLWithPath: path))
      }
      if let path = UserDefaults.standard.string(forKey: "kitbagRestoreFrom"),
        (try? BackupManager().restore(from: URL(fileURLWithPath: path))) != nil
      {
        timetable.reload()
        deadlines.reload()
        notes.reload()
        themes.reload()
        layout.reload()
        notificationPreferences.reload()
        gradeScales.reload()
        WidgetBridge.sync(theme: themes.themeID)
      }
    }

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
