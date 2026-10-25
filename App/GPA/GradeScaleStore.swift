import KitbagCore
import Observation
import SwiftUI

extension GradeScale {
  /// What to call the scale: its name (a preset is named by its grades).
  var displayName: String {
    name ?? L10n.string("Grade scale", table: "GPA")
  }
}

/// The person's grading systems. Schools differ (and so does study abroad), so every scale is the person's own and can be
/// changed or deleted; a scale can be made from scratch or from one of the presets (`GradeScale.presets`), which is copied.
/// Kept in UserDefaults as JSON, so that a backup carries it.
///
/// Earlier versions had four fixed scales that could only be read. Something that still refers to one of them by its id (a
/// term, the scale chosen for the GPA screen) gets a copy of it with the same id (`adoptInUse`), so that it shows in the
/// lists and can be changed, and nothing that refers to it has to change.
@MainActor
@Observable
final class GradeScaleStore {
  private(set) var scales: [GradeScale]
  /// The terms, which say which scales are in use. Set once by the app, after the timetable is loaded.
  @ObservationIgnored var terms: () -> [Timetable] = { [] }
  @ObservationIgnored private let defaults: UserDefaults
  private static let key = "kitbag.customGradeScales"
  private static let choiceKey = "kitbag.gradeScale"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    scales = Self.load(from: defaults)
    Self.migrateChoice(in: defaults)
  }

  /// The scale chosen for the GPA screen may still be stored under an id from the first versions (`GradeScale.legacyIDs`).
  private static func migrateChoice(in defaults: UserDefaults) {
    guard let stored = defaults.string(forKey: choiceKey) else { return }
    let current = GradeScale.canonicalID(stored)
    if current != stored { defaults.set(current, forKey: choiceKey) }
  }

  /// The person's scales, for choosing among.
  var all: [GradeScale] { scales }

  func scale(id: String) -> GradeScale { GradeScale.scale(id: id, custom: scales) }

  func upsert(_ scale: GradeScale) {
    if let index = scales.firstIndex(where: { $0.id == scale.id }) {
      scales[index] = scale
    } else {
      scales.append(scale)
    }
    save()
  }

  func remove(id: String) {
    scales.removeAll { $0.id == id }
    save()
  }

  // MARK: What is in use

  /// The id of the scale chosen for the GPA screen (the first preset until one is chosen).
  var chosenID: String { GradeScale.canonicalID(defaults.string(forKey: Self.choiceKey) ?? GradeScale.usAB.id) }

  /// The ids of the scales that something refers to: the one chosen for the GPA screen and the one of each term.
  func idsInUse() -> Set<String> {
    GradeScale.idsInUse(termScaleIDs: terms().map(\.gradeScaleID), chosen: defaults.string(forKey: Self.choiceKey))
  }

  /// How many terms use the scale, and whether it is the one chosen for the GPA screen.
  func usage(of id: String) -> (terms: Int, isChosen: Bool) {
    (terms().filter { $0.gradeScaleID.map(GradeScale.canonicalID) == id }.count, chosenID == id)
  }

  /// Gives the person a copy of each preset that something refers to and that they do not have yet.
  func adoptInUse() { adopt(ids: idsInUse()) }

  /// Makes sure the person has a copy of the preset with this id, for terms that are about to refer to it.
  func adopt(ids: Set<String>) {
    let missing = GradeScale.presetsToAdopt(inUse: ids, among: scales)
    guard !missing.isEmpty else { return }
    scales += missing
    save()
  }

  /// Reads the scales again, after a backup was restored.
  func reload() {
    scales = Self.load(from: defaults)
    Self.migrateChoice(in: defaults)
    adoptInUse()
  }

  private static func load(from defaults: UserDefaults) -> [GradeScale] {
    defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([GradeScale].self, from: $0) } ?? []
  }

  private func save() {
    if let data = try? JSONEncoder().encode(scales) { defaults.set(data, forKey: Self.key) }
  }
}
