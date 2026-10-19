import KitbagCore
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

  /// What Headway has downloaded since its meter was last reset, from its own data meter (Headway > Settings > Live buses
  /// > Mobile data), for the data usage screen to show next to Kitbag's own. Headway's meter is not Kitbag's.
  func dataUsed() -> (wifi: Int, mobile: Int, since: Date) {
    let usage = DataMeter.shared.usage
    return (usage.bytes(metered: false), usage.bytes(metered: true), usage.since)
  }

  /// Makes Headway speak the language chosen for the whole of Kitbag. Headway has a language setting of its own; Kitbag's
  /// choice is written into it, so the two never disagree.
  func setLanguage(_ choice: LanguageChoice) {
    let language: AppLanguage
    switch choice {
    case .system: language = .system
    case .english: language = .english
    case .japanese: language = .japanese
    }
    if model.settings.values.language != language { model.settings.values.language = language }
    LanguageState.shared.apply(language)
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
