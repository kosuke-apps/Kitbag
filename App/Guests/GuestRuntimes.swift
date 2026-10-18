import Observation

/// What each guest app does at launch, held for the whole life of the app. See docs/guests.md.
@MainActor
@Observable
final class GuestRuntimes {
  let headway = HeadwayRuntime()
}
