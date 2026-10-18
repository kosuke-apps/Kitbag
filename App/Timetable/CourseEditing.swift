import KitbagCore
import SwiftUI

/// What one class is, shown when its block is tapped.
struct ClassDetailSheet: View {
  let slot: Timetable.Slot
  let edit: () -> Void

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section {
          VStack(alignment: .leading, spacing: 4) {
            Text(slot.course.code).font(.title2.weight(.semibold))
            if !slot.course.title.isEmpty { Text(slot.course.title).font(.body) }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 4)
          .listRowBackground(slot.course.color.blockColor)
        }
        Section {
          row("Class", slot.meeting.label)
          row("Day", slot.day.name(width: .wide))
          row("Time", "\(slot.meeting.start.twelveHourText)–\(slot.meeting.end.twelveHourText)")
          row("Location", slot.meeting.location)
          row("Instructor", slot.meeting.instructor)
        }
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(action: edit) { Text("Edit course", tableName: "Timetable") }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            dismiss()
          } label: {
            Text("Done", tableName: "Timetable")
          }
        }
      }
    }
    .presentationDetents([.medium, .large])
  }

  @ViewBuilder private func row(_ title: String.LocalizationValue, _ value: String) -> some View {
    if !value.isEmpty {
      LabeledContent {
        Text(value)
      } label: {
        Text(LocalizedStringResource(title, table: "Timetable"))
      }
    }
  }
}

/// The courses, to add, open and delete.
struct CourseListView: View {
  @Environment(TimetableStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  @State private var editing: Course?
  @State private var title = ""

  var body: some View {
    NavigationStack {
      List {
        Section {
          TextField(text: $title, prompt: Text("2026 Fall Semester", tableName: "Timetable")) {
            Text("Timetable title", tableName: "Timetable")
          }
          .onSubmit { store.setTitle(title) }
        }
        Section {
          ForEach(store.timetable.courses) { course in
            Button {
              editing = course
            } label: {
              HStack(spacing: 12) {
                Circle().fill(course.color.blockColor).frame(width: 18, height: 18)
                  .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
                VStack(alignment: .leading, spacing: 2) {
                  Text(course.code).foregroundStyle(.primary)
                  if !course.title.isEmpty { Text(course.title).font(.footnote).foregroundStyle(.secondary) }
                }
              }
            }
          }
          .onDelete { store.deleteCourses(at: $0) }
          Button {
            editing = Course(code: "", color: nextColor)
          } label: {
            Label {
              Text("Add a course", tableName: "Timetable")
            } icon: {
              Image(systemName: "plus")
            }
          }
        }
      }
      .navigationTitle(Text("Courses", tableName: "Timetable"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button {
            store.setTitle(title)
            dismiss()
          } label: {
            Text("Done", tableName: "Timetable")
          }
        }
      }
      .onAppear { title = store.timetable.title }
      .sheet(item: $editing) { course in
        CourseEditor(course: course, isNew: !store.timetable.courses.contains { $0.id == course.id })
      }
    }
  }

  /// The first colour no course uses yet, so that a new course stands out.
  private var nextColor: CourseColor {
    let used = Set(store.timetable.courses.map(\.color))
    return CourseColor.allCases.first { !used.contains($0) } ?? .lavender
  }
}

/// A course with its classes, as a form.
struct CourseEditor: View {
  @Environment(TimetableStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  @State var course: Course
  let isNew: Bool

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField(text: $course.code, prompt: Text("A B 123", tableName: "Timetable")) {
            Text("Course code", tableName: "Timetable")
          }
          .autocorrectionDisabled()
          TextField(text: $course.title) {
            Text("Title", tableName: "Timetable")
          }
        }
        Section {
          colorPicker
        } header: {
          Text("Colour", tableName: "Timetable")
        }
        ForEach($course.meetings) { $meeting in
          MeetingFields(meeting: $meeting) {
            course.meetings.removeAll { $0.id == meeting.id }
          }
        }
        Section {
          Button {
            course.meetings.append(
              Meeting(
                kind: "LEC", section: "", days: [.monday], start: TimeOfDay(hour: 9, minute: 0),
                end: TimeOfDay(hour: 9, minute: 50)))
          } label: {
            Label {
              Text("Add a class", tableName: "Timetable")
            } icon: {
              Image(systemName: "plus")
            }
          }
        }
      }
      .navigationTitle(
        isNew ? Text("New course", tableName: "Timetable") : Text("Edit course", tableName: "Timetable")
      )
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            dismiss()
          } label: {
            Text("Cancel", tableName: "Timetable")
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            course.code = course.code.trimmingCharacters(in: .whitespaces)
            store.upsert(course)
            dismiss()
          } label: {
            Text("Save", tableName: "Timetable")
          }
          .disabled(!canSave)
        }
      }
    }
  }

  private var canSave: Bool {
    !course.code.trimmingCharacters(in: .whitespaces).isEmpty
      && course.meetings.allSatisfy { !$0.days.isEmpty && $0.end > $0.start }
  }

  private var colorPicker: some View {
    HStack(spacing: 12) {
      ForEach(CourseColor.allCases, id: \.self) { color in
        Button {
          course.color = color
        } label: {
          Circle()
            .fill(color.blockColor)
            .frame(width: 28, height: 28)
            .overlay(Circle().stroke(Color.primary.opacity(0.3), lineWidth: 0.5))
            .overlay {
              if color == course.color {
                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.primary)
              }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(color.rawValue.capitalized))
        .accessibilityAddTraits(color == course.color ? .isSelected : [])
      }
    }
    .frame(maxWidth: .infinity)
  }
}

/// The fields of one class: kind, section, days, times, room and instructor.
private struct MeetingFields: View {
  @Binding var meeting: Meeting
  let delete: () -> Void

  var body: some View {
    Section {
      HStack {
        TextField(text: $meeting.kind, prompt: Text("LEC", tableName: "Timetable")) {
          Text("Kind", tableName: "Timetable")
        }
        .textInputAutocapitalization(.characters)
        .autocorrectionDisabled()
        TextField(text: $meeting.section, prompt: Text("001", tableName: "Timetable")) {
          Text("Section", tableName: "Timetable")
        }
        .autocorrectionDisabled()
      }
      daysRow
      DatePicker(selection: date(for: $meeting.start), displayedComponents: .hourAndMinute) {
        Text("Starts", tableName: "Timetable")
      }
      DatePicker(selection: date(for: $meeting.end), displayedComponents: .hourAndMinute) {
        Text("Ends", tableName: "Timetable")
      }
      TextField(text: $meeting.location) { Text("Location", tableName: "Timetable") }
      TextField(text: $meeting.instructor) { Text("Instructor", tableName: "Timetable") }
      if meeting.days.isEmpty {
        Text("Choose at least one day.", tableName: "Timetable").font(.footnote).foregroundStyle(.red)
      }
      if meeting.end <= meeting.start {
        Text("The end must be after the start.", tableName: "Timetable").font(.footnote).foregroundStyle(.red)
      }
      Button(role: .destructive, action: delete) {
        Text("Delete this class", tableName: "Timetable")
      }
    } header: {
      Text(meeting.label.isEmpty ? String(localized: "Class", table: "Timetable") : meeting.label)
    }
  }

  private var daysRow: some View {
    HStack(spacing: 6) {
      ForEach(Weekday.allCases, id: \.self) { day in
        let isOn = meeting.days.contains(day)
        Button {
          if isOn {
            meeting.days.removeAll { $0 == day }
          } else {
            meeting.days = (meeting.days + [day]).sorted()
          }
        } label: {
          Text(String(day.name(width: .short).prefix(3)))
            .font(.system(size: 11, weight: .medium))
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(isOn ? Color.accentColor : Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(day.name(width: .wide)))
        .accessibilityAddTraits(isOn ? .isSelected : [])
      }
    }
  }

  /// A `DatePicker` works with dates; a class time is a time of day.
  private func date(for time: Binding<TimeOfDay>) -> Binding<Date> {
    Binding(
      get: {
        Calendar.current.date(
          bySettingHour: time.wrappedValue.hour, minute: time.wrappedValue.minute, second: 0, of: Date())
          ?? Date()
      },
      set: {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
        time.wrappedValue = TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
      })
  }
}
