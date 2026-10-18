import KitbagCore
import SwiftUI

/// A course in the list under the timetable: its colour, code, title, credits, sections and instructors.
struct CourseCard: View {
  @Environment(\.titleDesign) private var design
  @Environment(\.palette) private var palette
  let course: Course
  let open: () -> Void

  var body: some View {
    Button(action: open) {
      HStack(spacing: 0) {
        course.color.strongColor.frame(width: 6)
        VStack(alignment: .leading, spacing: 6) {
          HStack(alignment: .firstTextBaseline) {
            Text(course.code).font(.system(size: 19, weight: .semibold, design: design))
            Spacer(minLength: 8)
            if let credits = course.credits {
              Text(creditsText(credits))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(course.color.strongColor.opacity(0.18), in: Capsule())
                .foregroundStyle(course.color.strongColor)
            }
            if let grade = course.grade {
              Text(grade)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.1), in: Capsule())
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
          }
          if !course.title.isEmpty { Text(course.title).font(.subheadline).foregroundStyle(.primary) }
          if !course.sectionsSummary.isEmpty || !course.instructors.isEmpty {
            HStack(spacing: 8) {
              if !course.sectionsSummary.isEmpty {
                Text(course.sectionsSummary).font(.caption.monospacedDigit())
              }
              if !course.instructors.isEmpty {
                Text(course.instructors.joined(separator: ", ")).font(.caption).lineLimit(1)
              }
            }
            .foregroundStyle(.secondary)
          }
        }
        .multilineTextAlignment(.leading)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .background(palette.card)
      .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(palette.cardStroke, lineWidth: 0.75))
      .shadow(color: palette.shadow, radius: 10, y: 4)
      .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
  }
}

func creditsText(_ credits: Double) -> String {
  let number = credits == credits.rounded() ? "\(Int(credits))" : String(format: "%.1f", credits)
  return String(localized: "\(number) cr", table: "Timetable")
}

/// Everything about one course: credits, instructors, when it meets, its grade, and the deadlines and notes that belong
/// to it, with ways to add one.
struct CourseDetailView: View {
  @Environment(TimetableStore.self) private var store
  @Environment(DeadlineStore.self) private var deadlines
  @Environment(NoteStore.self) private var notes
  @Environment(\.openModule) private var openModule
  @Environment(\.dismiss) private var dismiss
  @Environment(\.palette) private var palette
  @Environment(\.titleDesign) private var design
  @AppStorage("kitbag.gradeScale") private var scaleID = GradeScale.uwMadison.id

  let courseID: UUID
  let termID: UUID
  let edit: (Course) -> Void

  @State private var editingDeadline: Deadline?

  var body: some View {
    NavigationStack {
      if let course = store.term(id: termID)?.course(id: courseID) {
        List {
          header(course)
          facts(course)
          schedule(course)
          grade(course)
          deadlinesSection(course)
          notesSection(course)
        }
        .scrollContentBackground(.hidden)
        .themedScreen()
        .navigationTitle(Text(course.code))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button {
              edit(course)
            } label: {
              Text("Edit course", tableName: "Timetable")
            }
          }
          ToolbarItem(placement: .confirmationAction) {
            Button {
              dismiss()
            } label: {
              Text("Done", tableName: "Timetable")
            }
          }
        }
        .sheet(item: $editingDeadline) { deadline in
          DeadlineEditor(deadline: deadline, isNew: !deadlines.book.deadlines.contains { $0.id == deadline.id })
        }
      } else {
        ContentUnavailableView {
          Label {
            Text("This course no longer exists.", tableName: "Timetable")
          } icon: {
            Image(systemName: "questionmark.folder")
          }
        }
      }
    }
    .presentationDetents([.large])
  }

  // MARK: Sections

  private func header(_ course: Course) -> some View {
    Section {
      VStack(alignment: .leading, spacing: 4) {
        Text(course.code).font(.system(size: 28, weight: .semibold, design: design))
        if !course.title.isEmpty { Text(course.title).font(.title3) }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 6)
      .listRowBackground(
        LinearGradient(
          colors: [course.color.blockColor, course.color.blockColor.opacity(0.7)], startPoint: .topLeading,
          endPoint: .bottomTrailing))
    }
  }

  private func facts(_ course: Course) -> some View {
    Section {
      if let credits = course.credits {
        LabeledContent {
          Text(creditsText(credits))
        } label: {
          Text("Credits", tableName: "Timetable")
        }
      }
      if !course.instructors.isEmpty {
        LabeledContent {
          Text(course.instructors.joined(separator: "\n")).multilineTextAlignment(.trailing)
        } label: {
          Text("Instructors", tableName: "Timetable")
        }
      }
      if let term = store.term(id: termID) {
        LabeledContent {
          Text(term.termName)
        } label: {
          Text("Term", tableName: "Timetable")
        }
      }
    }
    .listRowBackground(palette.card)
  }

  private func schedule(_ course: Course) -> some View {
    Section {
      ForEach(course.meetings) { meeting in
        VStack(alignment: .leading, spacing: 3) {
          HStack {
            Text(meeting.label).font(.subheadline.weight(.semibold))
            Spacer()
            Text("\(meeting.start.twelveHourText)–\(meeting.end.twelveHourText)")
              .font(.subheadline.monospacedDigit())
          }
          Text(meeting.days.map { $0.name(width: .short) }.joined(separator: " "))
            .font(.footnote).foregroundStyle(.secondary)
          if !meeting.location.isEmpty {
            Label(meeting.location, systemImage: "mappin.and.ellipse").font(.footnote).foregroundStyle(.secondary)
          }
        }
        .padding(.vertical, 2)
      }
    } header: {
      Text("Schedule", tableName: "Timetable")
    }
    .listRowBackground(palette.card)
  }

  private func grade(_ course: Course) -> some View {
    let scale = GradeScale.scale(id: scaleID)
    return Section {
      Picker(
        selection: Binding(
          get: { course.grade ?? "" },
          set: { store.setGrade($0.isEmpty ? nil : $0, courseID: course.id, in: termID) })
      ) {
        Text("Not graded yet", tableName: "Timetable").tag("")
        ForEach(scale.grades, id: \.label) { grade in
          Text(grade.label).tag(grade.label)
        }
        if let current = course.grade, !scale.contains(current) { Text(current).tag(current) }
      } label: {
        Text("Grade", tableName: "Timetable")
      }
    } header: {
      Text("Grade", tableName: "Timetable")
    } footer: {
      Text("Grades feed the GPA tool.", tableName: "Timetable")
    }
    .listRowBackground(palette.card)
  }

  private func deadlinesSection(_ course: Course) -> some View {
    let mine = deadlines.book.deadlines.filter { $0.courseID == course.id }
    let open = mine.filter { !$0.isDone }.sorted { $0.date < $1.date }
    return Section {
      ForEach(open.prefix(5)) { item in
        Button {
          editingDeadline = item
        } label: {
          HStack {
            Image(systemName: item.kind.symbol).foregroundStyle(item.kind.color).frame(width: 22)
            Text(item.title).foregroundStyle(.primary)
            Spacer()
            Text(item.date.date(calendar: .current), format: .dateTime.month(.abbreviated).day())
              .font(.footnote).foregroundStyle(.secondary)
          }
        }
      }
      Button {
        editingDeadline = Deadline(title: "", courseID: course.id, date: LocalDate(Date(), calendar: .current))
      } label: {
        Label {
          Text("Add a deadline", tableName: "Timetable")
        } icon: {
          Image(systemName: "plus")
        }
      }
      if mine.count > open.count || open.count > 5 {
        Button {
          dismiss()
          openModule(ModuleRoute(.calendar))
        } label: {
          Text("See all in the calendar", tableName: "Timetable")
        }
      }
    } header: {
      Text("Deadlines", tableName: "Timetable")
    }
    .listRowBackground(palette.card)
  }

  private func notesSection(_ course: Course) -> some View {
    let mine = notes.book.sorted.filter { $0.courseID == course.id }
    return Section {
      ForEach(mine.prefix(5)) { note in
        Button {
          dismiss()
          openModule(ModuleRoute(.notes, noteID: note.id))
        } label: {
          VStack(alignment: .leading, spacing: 2) {
            Text(note.title.isEmpty ? String(localized: "New note", table: "Notes") : note.title).foregroundStyle(
              .primary)
            if !note.preview.isEmpty {
              Text(note.preview).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
          }
        }
      }
      Button {
        let note = notes.create(courseID: course.id)
        dismiss()
        openModule(ModuleRoute(.notes, noteID: note.id))
      } label: {
        Label {
          Text("New note for this course", tableName: "Timetable")
        } icon: {
          Image(systemName: "square.and.pencil")
        }
      }
    } header: {
      Text("Notes", tableName: "Timetable")
    }
    .listRowBackground(palette.card)
  }
}

/// The form for a course: code, title, credits, colour and its classes.
struct CourseEditor: View {
  @Environment(TimetableStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  @State private var course: Course
  @State private var creditsText: String
  @State private var confirmingDelete = false
  let termID: UUID
  let isNew: Bool

  init(course: Course, termID: UUID, isNew: Bool) {
    _course = State(initialValue: course)
    _creditsText = State(initialValue: course.credits.map { $0 == $0.rounded() ? "\(Int($0))" : String($0) } ?? "")
    self.termID = termID
    self.isNew = isNew
  }

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
          TextField(text: $creditsText, prompt: Text("3", tableName: "Timetable")) {
            Text("Credits", tableName: "Timetable")
          }
          .keyboardType(.decimalPad)
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
        if !isNew {
          Section {
            Button(role: .destructive) {
              confirmingDelete = true
            } label: {
              Text("Delete this course", tableName: "Timetable")
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
          Button(action: save) { Text("Save", tableName: "Timetable") }
            .disabled(!canSave)
        }
      }
      .confirmationDialog(
        Text("Delete this course?", tableName: "Timetable"), isPresented: $confirmingDelete, titleVisibility: .visible
      ) {
        Button(role: .destructive) {
          store.deleteCourse(id: course.id, in: termID)
          dismiss()
        } label: {
          Text("Delete", tableName: "Timetable")
        }
      }
    }
  }

  private var parsedCredits: Double? {
    Double(creditsText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
  }

  private var canSave: Bool {
    let creditsOK = creditsText.trimmingCharacters(in: .whitespaces).isEmpty || (parsedCredits.map { $0 >= 0 } ?? false)
    return !course.code.trimmingCharacters(in: .whitespaces).isEmpty && creditsOK
      && course.meetings.allSatisfy { !$0.days.isEmpty && $0.end > $0.start }
  }

  private func save() {
    var saved = course
    saved.code = saved.code.trimmingCharacters(in: .whitespaces)
    saved.credits = parsedCredits
    store.upsertCourse(saved, in: termID)
    dismiss()
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
