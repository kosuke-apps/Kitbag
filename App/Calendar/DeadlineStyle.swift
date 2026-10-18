import KitbagCore
import SwiftUI

extension DeadlineKind {
  var title: LocalizedStringResource {
    switch self {
    case .assignment: LocalizedStringResource("Assignment", table: "Calendar")
    case .exam: LocalizedStringResource("Exam", table: "Calendar")
    case .quiz: LocalizedStringResource("Quiz", table: "Calendar")
    case .project: LocalizedStringResource("Project", table: "Calendar")
    case .other: LocalizedStringResource("Other", table: "Calendar")
    }
  }

  var symbol: String {
    switch self {
    case .assignment: "doc.text"
    case .exam: "pencil.and.list.clipboard"
    case .quiz: "questionmark.circle"
    case .project: "folder"
    case .other: "flag"
    }
  }

  /// Exams stand out in red, as the dots on the month page should.
  var color: Color {
    switch self {
    case .assignment: .blue
    case .exam: .red
    case .quiz: .orange
    case .project: .purple
    case .other: .gray
    }
  }
}

extension ReminderLead {
  var title: LocalizedStringResource {
    switch self {
    case .none: LocalizedStringResource("No reminder", table: "Calendar")
    case .atDue: LocalizedStringResource("When it is due", table: "Calendar")
    case .hourBefore: LocalizedStringResource("1 hour before", table: "Calendar")
    case .dayBefore: LocalizedStringResource("1 day before", table: "Calendar")
    case .twoDaysBefore: LocalizedStringResource("2 days before", table: "Calendar")
    }
  }
}

extension DeadlineBucket {
  var title: LocalizedStringResource {
    switch self {
    case .overdue: LocalizedStringResource("Overdue", table: "Calendar")
    case .today: LocalizedStringResource("Today", table: "Calendar")
    case .tomorrow: LocalizedStringResource("Tomorrow", table: "Calendar")
    case .thisWeek: LocalizedStringResource("Next 7 days", table: "Calendar")
    case .later: LocalizedStringResource("Later", table: "Calendar")
    }
  }
}
