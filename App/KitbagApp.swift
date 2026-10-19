import SwiftUI
import UserNotifications

@main
struct KitbagApp: App {
  /// The guests start with Kitbag, not when their tile is tapped: some of them register background tasks, and iOS only
  /// accepts that before the app has finished launching.
  @State private var guests: GuestRuntimes
  @State private var timetable: TimetableStore
  @State private var deadlines: DeadlineStore
  @State private var notes = NoteStore()
  @State private var dataUse: DataUseStore
  @State private var weather: WeatherStore
  @State private var subscriptions: SubscriptionStore
  @State private var themes = ThemeStore()
  @State private var layout = LayoutStore()
  @State private var notificationPreferences: NotificationPreferencesStore
  @State private var gradeScales = GradeScaleStore()
  @State private var backupFolder = BackupFolderStore()
  @Environment(\.scenePhase) private var scenePhase

  /// Wires up what a notification button needs. iOS can start Kitbag in the background only to carry out a button of a
  /// reminder (Done, Snooze), without any screen, so this cannot wait for a view to appear: the handler has to be in
  /// place, and the deadlines must know the terms and the preferences, before the app has finished launching. The guests
  /// are made here, before the handler is set, because Headway installs its own handler when it starts and the last one
  /// wins; `@State` would make them later, when the first view is drawn, and Headway's would replace Kitbag's.
  init() {
    let guests = GuestRuntimes()
    // What is downloaded is counted and decided by one store, which watches the connection from the start.
    let dataUse = DataUseStore()
    let timetable = TimetableStore()
    let deadlines = DeadlineStore()
    let preferences = NotificationPreferencesStore()
    deadlines.courseCode = { [timetable] in timetable.course(id: $0)?.code }
    deadlines.library = { [timetable] in timetable.library }
    deadlines.preferences = { [preferences] in preferences.preferences }
    _guests = State(initialValue: guests)
    _dataUse = State(initialValue: dataUse)
    _weather = State(initialValue: WeatherStore(dataUse: dataUse))
    _subscriptions = State(initialValue: SubscriptionStore(dataUse: dataUse))
    _timetable = State(initialValue: timetable)
    _deadlines = State(initialValue: deadlines)
    _notificationPreferences = State(initialValue: preferences)
    // Kitbag's own handler comes after the guests', which set theirs when they start (just above).
    UNUserNotificationCenter.current().delegate = KitbagNotificationDelegate.shared
  }

  var body: some Scene {
    WindowGroup {
      LanguageRoot {
        ThemeRoot {
          HomeView()
        }
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
      .environment(dataUse)
      .environment(gradeScales)
      .environment(backupFolder)
      .task { deadlines.syncReminders() }
      .task { await weather.refresh() }
      .task { await subscriptions.refreshStale() }
      #if DEBUG
        .task { exportPDFIfAsked() }
        .task { backupIfAsked() }
        .task { importTimetableIfAsked() }
        .task { await backupFolderIfAsked() }
        .task { await fakeHeadwayReminderIfAsked() }
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
        // The automatic backup into the chosen folder, at most once a day (see BackupNaming.isDue).
        if phase == .active || phase == .background { Task { await backupFolder.backUpIfDue() } }
        // A reminder set in Headway just before leaving gets its icon while the app is still allowed to run.
        if phase == .inactive || phase == .background {
          var task = UIBackgroundTaskIdentifier.invalid
          task = UIApplication.shared.beginBackgroundTask { UIApplication.shared.endBackgroundTask(task) }
          Task {
            await deadlines.decorateGuestNotifications()
            UIApplication.shared.endBackgroundTask(task)
          }
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

    /// For checking the icon on Headway's notifications without setting a reminder in Headway: launch with
    /// `-kitbagFakeHeadwayReminder YES` and a notification named like Headway's comes in 25 seconds, after Kitbag has given it
    /// Headway's icon. Only in debug builds.
    @MainActor fileprivate func fakeHeadwayReminderIfAsked() async {
      guard UserDefaults.standard.bool(forKey: "kitbagFakeHeadwayReminder") else { return }
      let content = UNMutableNotificationContent()
      content.title = "Time to leave"
      content.body = "The 80 leaves in 10 minutes"
      content.sound = .default
      content.interruptionLevel = .timeSensitive
      let request = UNNotificationRequest(
        identifier: "headway.reminder.test", content: content,
        trigger: UNTimeIntervalNotificationTrigger(timeInterval: 25, repeats: false))
      try? await UNUserNotificationCenter.current().add(request)
      await deadlines.decorateGuestNotifications()
      // And one of Kitbag's own, with the calendar's icon, to compare how an attached picture is drawn.
      let own = UNMutableNotificationContent()
      own.title = "Calendar icon test"
      own.body = "A deadline reminder looks like this"
      own.sound = .default
      own.attachments = [NotificationIcon.attachment(for: .calendar)].compactMap { $0 }
      try? await UNUserNotificationCenter.current().add(
        UNNotificationRequest(
          identifier: "kitbag.test.icon", content: own,
          trigger: UNTimeIntervalNotificationTrigger(timeInterval: 25, repeats: false)))
    }

    /// For checking the backup folder without the picker: `-kitbagBackupFolder <name>` makes a folder of that name in the app's
    /// Documents, chooses it and backs up into it at once. Only in debug builds.
    @MainActor fileprivate func backupFolderIfAsked() async {
      guard let name = UserDefaults.standard.string(forKey: "kitbagBackupFolder") else { return }
      let url = URL.documentsDirectory.appending(path: name)
      try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      backupFolder.choose(url)
      await backupFolder.backUpIfDue(force: true)
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
        dataUse.reload()
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
