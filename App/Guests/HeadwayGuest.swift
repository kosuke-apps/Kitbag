import SwiftUI
import UserNotifications

// Headway's own sources, built unchanged as the HeadwayGuest module (project.yml). `@testable` is what reaches its
// internal types without touching its code.
@testable import HeadwayGuest

/// Everything Headway's `@main` (`HeadwayApp.init`) does at launch. If a new Headway release changes that file, this
/// has to follow it (docs/guests.md).
@MainActor
final class HeadwayRuntime {
  let model: AppModel

  init() {
    let model = AppModel(settings: AppSettings())
    self.model = model
    LanguageState.shared.apply(model.settings.values.language)
    UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    WatchBackground.register(model)
  }
}

/// Headway's window content: what `HeadwayApp.body` puts in its `WindowGroup`.
struct HeadwayGuestView: View {
  let runtime: HeadwayRuntime

  var body: some View {
    LanguageRoot {
      RootView()
        .environment(runtime.model)
        .task { await runtime.model.start() }
    }
    // Headway has no accent colour of its own, so it uses the system blue, not Kitbag's theme accent.
    .accentColor(Color.blue)
    .tint(Color.blue)
  }
}
