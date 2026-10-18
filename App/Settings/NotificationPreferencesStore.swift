import KitbagCore
import Observation
import SwiftUI

/// The person's choices about what to be reminded of (`NotificationPreferences`), kept in UserDefaults as JSON, so that
/// they are saved with the other settings and travel in a backup.
@MainActor
@Observable
final class NotificationPreferencesStore {
  var preferences: NotificationPreferences {
    didSet { save() }
  }

  @ObservationIgnored private let defaults: UserDefaults
  private static let key = "kitbag.notificationPreferences"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    preferences = Self.load(from: defaults)
  }

  /// Reads the choices again, after a backup was restored.
  func reload() {
    preferences = Self.load(from: defaults)
  }

  private static func load(from defaults: UserDefaults) -> NotificationPreferences {
    defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(NotificationPreferences.self, from: $0) }
      ?? NotificationPreferences()
  }

  private func save() {
    if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: Self.key) }
  }
}
