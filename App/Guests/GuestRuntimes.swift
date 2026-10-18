import KitbagCore
import Observation

/// What each guest app does at launch, held for the whole life of the app. See docs/guests.md.
@MainActor
@Observable
final class GuestRuntimes {
  /// Headway registers background tasks, which iOS only accepts before the app has finished launching.
  let headway = HeadwayRuntime()
  /// Mantissa has nothing to do at launch, so it is created when it is first opened.
  @ObservationIgnored lazy var mantissa: MantissaRuntime = {
    let runtime = MantissaRuntime()
    runtime.setLanguage(LanguageStore.shared.choice)
    return runtime
  }()

  init() {
    headway.setLanguage(LanguageStore.shared.choice)
  }

  /// Passes the language chosen in Settings on to the guests, which keep a language setting of their own.
  func applyLanguage(_ choice: LanguageChoice) {
    headway.setLanguage(choice)
    mantissa.setLanguage(choice)
  }
}
