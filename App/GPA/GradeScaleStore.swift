import KitbagCore
import Observation
import SwiftUI

extension GradeScale {
  /// What to call the scale: its own name for one the person wrote, else the app's name for a built-in one.
  var displayName: String {
    name ?? L10n.string(title)
  }
}

/// The grading systems the person wrote, next to the built-in ones. Schools differ (and so does study abroad), so a scale
/// can be made from scratch or from a built-in one. Kept in UserDefaults as JSON, so that a backup carries it.
@MainActor
@Observable
final class GradeScaleStore {
  private(set) var custom: [GradeScale]
  @ObservationIgnored private let defaults: UserDefaults
  private static let key = "kitbag.customGradeScales"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    custom = Self.load(from: defaults)
  }

  /// The built-in scales, then the person's.
  var all: [GradeScale] { GradeScale.all + custom }

  func scale(id: String) -> GradeScale { GradeScale.scale(id: id, custom: custom) }

  func upsert(_ scale: GradeScale) {
    if let index = custom.firstIndex(where: { $0.id == scale.id }) {
      custom[index] = scale
    } else {
      custom.append(scale)
    }
    save()
  }

  func remove(id: String) {
    custom.removeAll { $0.id == id }
    save()
  }

  /// Reads the scales again, after a backup was restored.
  func reload() {
    custom = Self.load(from: defaults)
  }

  private static func load(from defaults: UserDefaults) -> [GradeScale] {
    defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([GradeScale].self, from: $0) } ?? []
  }

  private func save() {
    if let data = try? JSONEncoder().encode(custom) { defaults.set(data, forKey: Self.key) }
  }
}
