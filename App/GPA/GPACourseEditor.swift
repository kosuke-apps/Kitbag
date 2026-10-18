import KitbagCore
import SwiftUI

extension GPAMode {
  var title: LocalizedStringResource {
    switch self {
    case .counted: LocalizedStringResource("Counts toward the GPA", table: "GPA")
    case .excluded: LocalizedStringResource("Left out of the GPA", table: "GPA")
    case .passFail: LocalizedStringResource("Pass / fail", table: "GPA")
    }
  }

  var symbol: String? {
    switch self {
    case .counted: nil
    case .excluded: "minus.circle"
    case .passFail: "p.circle"
    }
  }
}

/// A course for the GPA: its code, credits, grade, and how it counts. The timetable's courses and the ones entered only for
/// their grades are the same thing, so this edits either.
struct GPACourseEditor: View {
  @Environment(TimetableStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  let termID: UUID
  let scale: GradeScale
  let isNew: Bool

  @State private var course: Course
  @State private var creditsText: String
  @State private var confirmingDelete = false

  init(course: Course, termID: UUID, scale: GradeScale, isNew: Bool) {
    self.termID = termID
    self.scale = scale
    self.isNew = isNew
    _course = State(initialValue: course)
    _creditsText = State(
      initialValue: course.credits.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? "")
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField(text: $course.code) {
            Text("Code", tableName: "GPA")
          }
          .textInputAutocapitalization(.characters)
          TextField(text: $course.title) {
            Text("Title", tableName: "GPA")
          }
          LabeledContent {
            TextField(text: $creditsText, prompt: Text("–")) {
              Text("Credits", tableName: "GPA")
            }
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 90)
          } label: {
            Text("Credits", tableName: "GPA")
          }
        }
        Section {
          Picker(selection: $course.grade) {
            Text("Not graded yet", tableName: "GPA").tag(String?.none)
            ForEach(scale.grades, id: \.label) { grade in
              Text(grade.label).tag(String?.some(grade.label))
            }
          } label: {
            Text("Grade", tableName: "GPA")
          }
          Picker(selection: $course.gpaMode) {
            ForEach(GPAMode.allCases, id: \.self) { mode in
              Text(mode.title).tag(mode)
            }
          } label: {
            Text("In the GPA", tableName: "GPA")
          }
        } footer: {
          Text(
            "A course left out of the GPA, or taken pass/fail, adds nothing to it; if it is passed it still earns its credits.",
            tableName: "GPA")
        }
        if !isNew {
          Section {
            Button(role: .destructive) {
              confirmingDelete = true
            } label: {
              Text("Delete this course", tableName: "GPA")
            }
          } footer: {
            if !course.meetings.isEmpty {
              Text("It also has classes in the timetable, which go with it.", tableName: "GPA")
            }
          }
        }
      }
      .navigationTitle(isNew ? Text("New course", tableName: "GPA") : Text(course.code))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            dismiss()
          } label: {
            Text("Cancel", tableName: "GPA")
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            save()
          } label: {
            Text("Save", tableName: "GPA")
          }
          .disabled(course.code.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
      .confirmationDialog(
        Text("Delete this course?", tableName: "GPA"), isPresented: $confirmingDelete, titleVisibility: .visible
      ) {
        Button(role: .destructive) {
          store.deleteCourse(id: course.id, in: termID)
          dismiss()
        } label: {
          Text("Delete", tableName: "GPA")
        }
      }
    }
  }

  private func save() {
    var saved = course
    saved.code = saved.code.trimmingCharacters(in: .whitespaces)
    saved.credits = Double(creditsText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    store.upsertCourse(saved, in: termID)
    dismiss()
  }
}
