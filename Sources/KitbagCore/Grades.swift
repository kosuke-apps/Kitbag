import Foundation

/// A grading system: the grades a university gives and how many grade points each is worth.
public struct GradeScale: Hashable, Identifiable, Sendable {
  public struct Grade: Hashable, Sendable {
    public let label: String
    /// Grade points, or nil for a grade that is not part of the GPA (pass, satisfactory, incomplete).
    public let points: Double?
  }

  /// A stable id, also used to look up the scale's display name.
  public let id: String
  public let grades: [Grade]

  /// The grade points of a grade, or nil when it is not in the scale or does not count.
  public func points(for label: String) -> Double? {
    grades.first { $0.label == label }?.points
  }

  public func contains(_ label: String) -> Bool { grades.contains { $0.label == label } }

  /// The grades that count towards the GPA, best first.
  public var counted: [Grade] { grades.filter { $0.points != nil } }

  private static func scale(_ id: String, _ counted: [(String, Double)], others: [String] = []) -> GradeScale {
    GradeScale(
      id: id, grades: counted.map { Grade(label: $0.0, points: $0.1) } + others.map { Grade(label: $0, points: nil) })
  }

  /// UW–Madison: A, AB, B, BC, C, D, F on a four-point scale.
  public static let uwMadison = scale(
    "uw-madison", [("A", 4.0), ("AB", 3.5), ("B", 3.0), ("BC", 2.5), ("C", 2.0), ("D", 1.0), ("F", 0.0)],
    others: ["S", "U", "CR", "N", "P", "I"])

  /// The common American scale with plus and minus.
  public static let usPlusMinus = scale(
    "us-plus-minus",
    [
      ("A+", 4.0), ("A", 4.0), ("A-", 3.7), ("B+", 3.3), ("B", 3.0), ("B-", 2.7), ("C+", 2.3), ("C", 2.0), ("C-", 1.7),
      ("D+", 1.3), ("D", 1.0), ("F", 0.0),
    ], others: ["P", "NP", "I", "W"])

  /// The five-step Japanese scale (S, A, B, C, D as 4, 3, 2, 1, 0) that many universities use; check yours.
  public static let japan = scale(
    "japan", [("S", 4.0), ("A", 3.0), ("B", 2.0), ("C", 1.0), ("D", 0.0)], others: ["P", "I"])

  public static let all: [GradeScale] = [uwMadison, usPlusMinus, japan]

  public static func scale(id: String) -> GradeScale {
    all.first { $0.id == id } ?? uwMadison
  }
}

/// Grade point averages and what they take to reach.
public enum GPA {
  /// A course for the calculation: its credits and its (real or imagined) grade.
  public struct Entry: Hashable, Sendable {
    public var credits: Double
    public var grade: String?

    public init(credits: Double, grade: String?) {
      self.credits = credits
      self.grade = grade
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

  /// The credits and grade points of the courses that have a counting grade. Nil when none has.
  public static func result(of entries: [Entry], scale: GradeScale) -> Result? {
    var total = Result(credits: 0, points: 0)
    for entry in entries where entry.credits > 0 {
      guard let grade = entry.grade, let points = scale.points(for: grade) else { continue }
      total.credits += entry.credits
      total.points += points * entry.credits
    }
    return total.credits > 0 ? total : nil
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
