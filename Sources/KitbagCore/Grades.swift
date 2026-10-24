import Foundation

/// A grading system: the grades a university gives and how many grade points each is worth. Schools (and study abroad)
/// differ, so every scale a person uses is their own and can be changed; the ones in `GradeScale.presets` are only
/// starting points that are copied when a person asks for one.
public struct GradeScale: Hashable, Identifiable, Codable, Sendable {
  public struct Grade: Hashable, Codable, Sendable {
    public var label: String
    /// Grade points, or nil for a grade that is not part of the GPA (pass, satisfactory, incomplete).
    public var points: Double?
    /// Whether the grade earns the credits: any grade with points above zero does; a pass does; a fail or an incomplete
    /// does not.
    public var earnsCredit: Bool

    public init(label: String, points: Double?, earnsCredit: Bool? = nil) {
      self.label = label
      self.points = points
      self.earnsCredit = earnsCredit ?? ((points ?? 0) > 0)
    }
  }

  /// A stable id. A preset has a fixed one, which its copy keeps when something already refers to it; a scale the person
  /// wrote has a made-up one.
  public let id: String
  /// What the person calls it. A preset is named by its grades, never by a country or a school.
  public var name: String?
  public var grades: [Grade]

  public init(id: String, name: String? = nil, grades: [Grade]) {
    self.id = id
    self.name = name
    self.grades = grades
  }

  /// The grade points of a grade, or nil when it is not in the scale or does not count.
  public func points(for label: String) -> Double? {
    grades.first { $0.label == label }?.points
  }

  public func contains(_ label: String) -> Bool { grades.contains { $0.label == label } }

  /// Whether the grade earns the credits (false for an unknown grade).
  public func earnsCredit(_ label: String) -> Bool {
    grades.first { $0.label == label }?.earnsCredit ?? false
  }

  /// The grades that count towards the GPA, best first.
  public var counted: [Grade] { grades.filter { $0.points != nil } }

  private static func scale(
    _ id: String, name: String, _ counted: [(String, Double)], passes: [String] = [], others: [String] = []
  ) -> GradeScale {
    GradeScale(
      id: id, name: name,
      grades: counted.map { Grade(label: $0.0, points: $0.1) }
        + (passes + others).map { Grade(label: $0, points: nil, earnsCredit: passes.contains($0)) })
  }

  // The presets are named by the grades they use, so that a person can tell them apart without being told where they are
  // from. The ids are older than the names and stay as they are: files and backups refer to them.

  /// A, AB, B, BC, C, D, F on a four-point scale.
  public static let usAB = scale(
    "us-ab", name: "A, AB, B, BC, C, D, F",
    [("A", 4.0), ("AB", 3.5), ("B", 3.0), ("BC", 2.5), ("C", 2.0), ("D", 1.0), ("F", 0.0)],
    passes: ["S", "CR", "P"], others: ["U", "N", "I"])

  /// A+ down to F, with plus and minus.
  public static let usPlusMinus = scale(
    "us-plus-minus", name: "A+, A, A-, B+ … D, F",
    [
      ("A+", 4.0), ("A", 4.0), ("A-", 3.7), ("B+", 3.3), ("B", 3.0), ("B-", 2.7), ("C+", 2.3), ("C", 2.0), ("C-", 1.7),
      ("D+", 1.3), ("D", 1.0), ("F", 0.0),
    ], passes: ["P"], others: ["NP", "I", "W"])

  /// S, A, B, C, D as 4, 3, 2, 1, 0; check yours.
  public static let japan = scale(
    "japan", name: "S, A, B, C, D", [("S", 4.0), ("A", 3.0), ("B", 2.0), ("C", 1.0), ("D", 0.0)], passes: ["P"],
    others: ["I"])

  /// AA, A, B, C, D as 4, 3, 2, 1, 0; check yours.
  public static let japanAA = scale(
    "japan-aa", name: "AA, A, B, C, D", [("AA", 4.0), ("A", 3.0), ("B", 2.0), ("C", 1.0), ("D", 0.0)], passes: ["P"],
    others: ["F", "I"])

  /// The starting points offered when a person adds a scale.
  public static let presets: [GradeScale] = [usAB, usPlusMinus, japan, japanAA]

  /// The presets that a person's scales do not yet include a copy of, among those whose ids are in `ids`. Something that
  /// refers to a preset by its id (a term, the scale chosen for the GPA screen) needs a scale of that id to show and to
  /// change; the copy keeps the id, so nothing that refers to it has to change.
  public static func presetsToAdopt(inUse ids: Set<String>, among scales: [GradeScale]) -> [GradeScale] {
    presets.filter { preset in ids.contains(preset.id) && !scales.contains { $0.id == preset.id } }
  }

  /// The ids that two built-in scales had in the first versions, when they were named after a school. Files, backups and
  /// settings written then still say these; they are read as the ids the scales have now.
  public static let legacyIDs = ["uw-madison": "us-ab", "tohoku": "japan-aa"]

  public static func canonicalID(_ id: String) -> String { legacyIDs[id] ?? id }

  /// The scale with this id among the person's own and then the presets (so a copy of a preset that the person changed wins
  /// over the preset), or the first preset (`usAB`) when there is none.
  public static func scale(id: String, custom: [GradeScale] = []) -> GradeScale {
    let id = canonicalID(id)
    return (custom + presets).first { $0.id == id } ?? usAB
  }
}

/// Grade point averages and what they take to reach.
public enum GPA {
  /// A course for the calculation: its credits, its (real or imagined) grade and how it is treated.
  public struct Entry: Hashable, Sendable {
    public var credits: Double
    public var grade: String?
    public var mode: GPAMode

    public init(credits: Double, grade: String?, mode: GPAMode = .counted) {
      self.credits = credits
      self.grade = grade
      self.mode = mode
    }
  }

  /// One term for the cumulative GPA: its courses, the scale they are graded on, and whether it counts.
  public struct TermInput: Sendable {
    public var entries: [Entry]
    public var scale: GradeScale
    public var included: Bool

    public init(entries: [Entry], scale: GradeScale, included: Bool = true) {
      self.entries = entries
      self.scale = scale
      self.included = included
    }
  }

  public struct Result: Hashable, Sendable {
    /// Credits that count, and the grade points they earned.
    public var credits: Double
    public var points: Double

    public var gpa: Double { credits > 0 ? points / credits : 0 }

    public init(credits: Double, points: Double) {
      self.credits = credits
      self.points = points
    }

    public static func + (lhs: Result, rhs: Result) -> Result {
      Result(credits: lhs.credits + rhs.credits, points: lhs.points + rhs.points)
    }
  }

  /// The credits and grade points of the courses that count and have a counting grade. A course that is left out of the
  /// GPA, or taken pass/fail, adds nothing. Nil when no course counts.
  public static func result(of entries: [Entry], scale: GradeScale) -> Result? {
    var total = Result(credits: 0, points: 0)
    for entry in entries where entry.credits > 0 && entry.mode == .counted {
      guard let grade = entry.grade, let points = scale.points(for: grade) else { continue }
      total.credits += entry.credits
      total.points += points * entry.credits
    }
    return total.credits > 0 ? total : nil
  }

  /// The cumulative result over the terms that are included, each worked out on its own scale. Nil when none counts.
  public static func cumulative(_ terms: [TermInput]) -> Result? {
    var total: Result?
    for term in terms where term.included {
      guard let result = result(of: term.entries, scale: term.scale) else { continue }
      total = total.map { $0 + result } ?? result
    }
    return total
  }

  /// The credits that earned something: a course with a grade that earns its credits on the scale, however it counts in
  /// the GPA (a left-out or pass/fail course still earns credits).
  public static func earnedCredits(of entries: [Entry], scale: GradeScale) -> Double {
    entries.reduce(0) { sum, entry in
      guard entry.credits > 0, let grade = entry.grade, scale.earnsCredit(grade) else { return sum }
      return sum + entry.credits
    }
  }

  /// The grade point average that the next `plannedCredits` credits must earn for the overall GPA to reach `target`.
  /// Nil when there are no planned credits. It can be above the scale's top (not reachable) or below zero (already safe).
  public static func requiredAverage(current: Result?, plannedCredits: Double, target: Double) -> Double? {
    guard plannedCredits > 0 else { return nil }
    let now = current ?? Result(credits: 0, points: 0)
    return (target * (now.credits + plannedCredits) - now.points) / plannedCredits
  }

  /// The grade with the fewest points that still reaches `average` or more, or nil when even the best falls short.
  public static func lowestGrade(reaching average: Double, scale: GradeScale) -> String? {
    scale.counted
      .filter { ($0.points ?? 0) >= average - 1e-9 }
      .min { ($0.points ?? 0) < ($1.points ?? 0) }?.label
  }
}

/// How a course is treated in the GPA.
public enum GPAMode: String, CaseIterable, Codable, Sendable {
  /// Its grade points count (the usual case).
  case counted
  /// It stays on the record but is left out of the GPA (a transfer, a course abroad on another system).
  case excluded
  /// Taken pass/fail: it earns credits when passed and adds nothing to the GPA.
  case passFail
}
