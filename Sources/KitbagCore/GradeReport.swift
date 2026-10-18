import Foundation

/// One course read from a university's grade list.
public struct ReportedCourse: Hashable, Sendable {
  public enum Semester: String, Sendable {
    case first
    case second
  }

  public var name: String
  public var credits: Double
  /// The grade as the report writes it (`AA`), or nil while the course is still being taken.
  public var grade: String?
  /// Whether the report marks the course as part of the GPA.
  public var countsInGPA: Bool
  public var year: Int
  public var semester: Semester
}

/// Reads the text of a Tohoku University "Grade list" (the English PDF a student can download), where a course is written as
/// the subject name, then `2.0 AA ○ 2024 Second semester` and the instructor, wrapped in narrow columns:
///
///     Introduction to Academic Learning
///     2.0 AA ○ 2024 Second semTAKESHI KOIK
///     ester E
///
/// A name that is too long wraps, and the credit line then starts with the rest of the name. A course still being taken is
/// written `* 1.0 Seminar II`, with the year and semester on the next line. Everything else (the headings, the faculty,
/// the student's name and number) is ignored, and the report's summary pages are not read. The student's name and number are
/// never kept.
public enum GradeReportParser {
  /// Nil when the text does not look like such a report.
  public static func parse(lines: [String]) -> [ReportedCourse]? {
    guard lines.contains(where: { $0.contains("Grade list") }) else { return nil }
    var courses: [ReportedCourse] = []
    var previous = ""
    var waitingForTerm: (name: String, credits: Double)?

    for raw in lines {
      let line = raw.trimmingCharacters(in: .whitespaces)
      if line.hasPrefix("Summary of acquired credits") { break }

      if let waiting = waitingForTerm {
        if let term = termStart(in: line) {
          courses.append(
            ReportedCourse(
              name: waiting.name, credits: waiting.credits, grade: nil, countsInGPA: true, year: term.year,
              semester: term.semester))
        }
        waitingForTerm = nil
        previous = ""
        if termStart(in: line) != nil { continue }
      }

      if let open = openCourse(in: line) {
        waitingForTerm = open
        continue
      }

      if let credit = creditLine(line) {
        var name = previous
        if !credit.prefix.isEmpty {
          // The name wrapped: its tail starts the credit line. A tail that begins in lower case continues a word.
          let continues = credit.prefix.first.map { $0.isLowercase } ?? false
          name = continues ? previous + credit.prefix : previous + " " + credit.prefix
        }
        name = name.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty {
          courses.append(
            ReportedCourse(
              name: name, credits: credit.credits, grade: credit.grade, countsInGPA: credit.counts, year: credit.year,
              semester: credit.semester))
        }
        previous = ""
        continue
      }
      if !line.isEmpty { previous = line }
    }
    return courses.isEmpty ? nil : courses
  }

  // MARK: Lines

  private struct CreditLine {
    var prefix: String
    var credits: Double
    var grade: String
    var counts: Bool
    var year: Int
    var semester: ReportedCourse.Semester
  }

  nonisolated(unsafe) private static let creditExpression =
    try! NSRegularExpression(
      pattern: #"^(.*?)(\d+\.\d)\s+([A-Z]{1,2})\s*(○)?\s*(20\d\d)\s+(First|Second)\s+sem"#)
  nonisolated(unsafe) private static let openExpression =
    try! NSRegularExpression(pattern: #"^\*\s*(\d+\.\d)\s+(.+)$"#)
  nonisolated(unsafe) private static let termExpression =
    try! NSRegularExpression(pattern: #"^(20\d\d)\s+(First|Second)\s+sem"#)

  private static func creditLine(_ line: String) -> CreditLine? {
    let range = NSRange(line.startIndex..., in: line)
    guard let match = creditExpression.firstMatch(in: line, range: range),
      let prefix = Range(match.range(at: 1), in: line), let credits = Range(match.range(at: 2), in: line),
      let grade = Range(match.range(at: 3), in: line), let year = Range(match.range(at: 5), in: line),
      let semester = Range(match.range(at: 6), in: line)
    else { return nil }
    return CreditLine(
      prefix: String(line[prefix]).trimmingCharacters(in: .whitespaces), credits: Double(line[credits]) ?? 0,
      grade: String(line[grade]), counts: match.range(at: 4).location != NSNotFound, year: Int(line[year]) ?? 0,
      semester: line[semester] == "First" ? .first : .second)
  }

  private static func openCourse(in line: String) -> (name: String, credits: Double)? {
    let range = NSRange(line.startIndex..., in: line)
    guard let match = openExpression.firstMatch(in: line, range: range),
      let credits = Range(match.range(at: 1), in: line),
      let name = Range(match.range(at: 2), in: line)
    else { return nil }
    return (String(line[name]).trimmingCharacters(in: .whitespaces), Double(line[credits]) ?? 0)
  }

  private static func termStart(in line: String) -> (year: Int, semester: ReportedCourse.Semester)? {
    let range = NSRange(line.startIndex..., in: line)
    guard let match = termExpression.firstMatch(in: line, range: range), let year = Range(match.range(at: 1), in: line),
      let semester = Range(match.range(at: 2), in: line)
    else { return nil }
    return (Int(line[year]) ?? 0, line[semester] == "First" ? .first : .second)
  }
}

/// A report's courses grouped into terms, ready to become grades-only terms.
public struct ReportedTerm: Hashable, Sendable {
  public var year: Int
  public var semester: ReportedCourse.Semester
  public var courses: [ReportedCourse]

  /// `Tohoku 2024 Second semester`, the title a term made from it gets.
  public func title(prefix: String) -> String {
    "\(prefix) \(year) \(semester == .first ? "First" : "Second") semester"
  }

  /// The first semester runs from April and the second from October, so they are the spring and the fall of the year.
  public var season: Season { semester == .first ? .spring : .fall }

  public static func group(_ courses: [ReportedCourse]) -> [ReportedTerm] {
    var order: [String] = []
    var groups: [String: ReportedTerm] = [:]
    for course in courses {
      let key = "\(course.year)-\(course.semester.rawValue)"
      if groups[key] == nil {
        order.append(key)
        groups[key] = ReportedTerm(year: course.year, semester: course.semester, courses: [])
      }
      groups[key]?.courses.append(course)
    }
    return order.compactMap { groups[$0] }
      .sorted { ($0.year, $0.semester == .second ? 1 : 0) < ($1.year, $1.semester == .second ? 1 : 0) }
  }
}
