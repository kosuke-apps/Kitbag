import Observation

/// What each guest app does at launch, held for the whole life of the app. See docs/guests.md.
@MainActor
@Observable
final class GuestRuntimes {
  /// Headway registers background tasks, which iOS only accepts before the app has finished launching.
  let headway = HeadwayRuntime()
  /// Mantissa has nothing to do at launch, so it is created when it is first opened.
  @ObservationIgnored lazy var mantissa = MantissaRuntime()
}
