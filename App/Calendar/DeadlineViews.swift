import KitbagCore
import SwiftUI
import UserNotifications

/// One deadline in a list: a check circle to mark it done, the title, and what kind and when.
struct DeadlineRow: View {
  @Environment(TimetableStore.self) private var timetable
  @Environment(DeadlineStore.self) private var deadlines

  let deadline: Deadline
  /// Whether to write the date, as in a list across days; a day's agenda shows only the time.
  let showsDate: Bool
  let edit: () -> Void

  var body: some View {
    let calendar = Calendar.current
    let course = deadline.courseID.flatMap { timetable.course(id: $0) }
    let overdue = deadline.isOverdue(at: Date(), calendar: calendar)
    HStack(alignment: .top, spacing: 10) {
      Button {
        deadlines.setDone(id: deadline.id, !deadline.isDone, courseCode: course?.code)
      } label: {
        Image(systemName: deadline.isDone ? "checkmark.circle.fill" : "circle")
          .font(.title3)
          .foregroundStyle(deadline.isDone ? Color.green : Color.secondary)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        deadline.isDone ? Text("Mark as not done", tableName: "Calendar") : Text("Mark as done", tableName: "Calendar"))

      Button(action: edit) {
        VStack(alignment: .leading, spacing: 3) {
          Text(deadline.title)
            .font(.subheadline.weight(.medium))
            .strikethrough(deadline.isDone)
            .foregroundStyle(deadline.isDone ? Color.secondary : Color.primary)
            .multilineTextAlignment(.leading)
          HStack(spacing: 6) {
            Image(systemName: deadline.kind.symbol).foregroundStyle(deadline.kind.color)
            if let course {
              Circle().fill(course.color.blockColor).frame(width: 9, height: 9)
                .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
              Text(course.code)
            }
            dueText
              .foregroundStyle(overdue ? Color.red : Color.secondary)
          }
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder private var dueText: some View {
    let due = deadline.dueInstant(calendar: .current)
    if showsDate {
      if deadline.time != nil {
        Text(due, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
      } else {
        Text(due, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
      }
    } else if deadline.time != nil {
      Text(due, format: .dateTime.hour().minute())
    } else {
      Text("Due any time", tableName: "Calendar")
    }
  }
}

/// The form for a deadline: what, when, which course, and when to be reminded (as many times as wanted).
struct DeadlineEditor: View {
  @Environment(DeadlineStore.self) private var deadlines
  @Environment(TimetableStore.self) private var timetable
  @Environment(NotificationPreferencesStore.self) private var preferencesStore
  @Environment(\.dismiss) private var dismiss

  @State private var deadline: Deadline
  @State private var hasTime: Bool
  @State private var confirmingDelete = false
  /// Whether the person has touched the reminders. Until then a new deadline follows the defaults of its kind, which
  /// change when the kind or the time does.
  @State private var alertsEdited = false
  @State private var appliedDefaults = false
  @State private var access: UNAuthorizationStatus = .authorized
  private let isNew: Bool

  init(deadline: Deadline, isNew: Bool) {
    _deadline = State(initialValue: deadline)
    _hasTime = State(initialValue: deadline.time != nil)
    self.isNew = isNew
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField(text: $deadline.title, prompt: Text("Problem set 3", tableName: "Calendar")) {
            Text("Title", tableName: "Calendar")
          }
          Picker(selection: $deadline.kind) {
            ForEach(DeadlineKind.allCases, id: \.self) { kind in
              Label {
                Text(kind.title)
              } icon: {
                Image(systemName: kind.symbol)
              }
              .tag(kind)
            }
          } label: {
            Text("Kind", tableName: "Calendar")
          }
          Picker(selection: $deadline.courseID) {
            Text("None", tableName: "Calendar").tag(UUID?.none)
            ForEach(courseChoices) { course in
              Text(course.code).tag(Optional(course.id))
            }
          } label: {
            Text("Course", tableName: "Calendar")
          }
        }
        Section {
          DatePicker(selection: dayBinding, displayedComponents: .date) {
            Text("Date", tableName: "Calendar")
          }
          Toggle(isOn: $hasTime) {
            Text("Set a time", tableName: "Calendar")
          }
          if hasTime {
            DatePicker(selection: timeBinding, displayedComponents: .hourAndMinute) {
              Text("Time", tableName: "Calendar")
            }
          }
        }
        Section {
          AlertList(
            alerts: $deadline.alerts, hasTime: hasTime, preferences: preferencesStore.preferences,
            fireDate: { fireDate(of: $0) }, due: deadline.dueInstant(calendar: .current),
            changed: { alertsEdited = true })
        } header: {
          Text("Reminders", tableName: "Calendar")
        } footer: {
          reminderNotice
        }
        Section {
          TextField(text: $deadline.note, axis: .vertical) {
            Text("Notes", tableName: "Calendar")
          }
          .lineLimit(2...6)
        }
        if !isNew {
          Section {
            Toggle(isOn: $deadline.isDone) {
              Text("Done", tableName: "Calendar")
            }
            Button(role: .destructive) {
              confirmingDelete = true
            } label: {
              Text("Delete this deadline", tableName: "Calendar")
            }
          }
        }
      }
      .navigationTitle(
        isNew ? Text("New deadline", tableName: "Calendar") : Text("Edit deadline", tableName: "Calendar")
      )
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            dismiss()
          } label: {
            Text("Cancel", tableName: "Calendar")
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(action: save) { Text("Save", tableName: "Calendar") }
            .disabled(deadline.title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
      .confirmationDialog(
        Text("Delete this deadline?", tableName: "Calendar"), isPresented: $confirmingDelete, titleVisibility: .visible
      ) {
        Button(role: .destructive) {
          deadlines.remove(id: deadline.id)
          dismiss()
        } label: {
          Text("Delete", tableName: "Calendar")
        }
      }
      .onChange(of: hasTime) { _, isOn in
        deadline.time = isOn ? (deadline.time ?? TimeOfDay(hour: 23, minute: 59)) : nil
        refreshAlerts()
      }
      .onChange(of: deadline.kind) { _, _ in refreshAlerts() }
      .task {
        if isNew, !appliedDefaults {
          appliedDefaults = true
          refreshAlerts()
        }
        access = await ReminderScheduler().status()
      }
    }
  }

  /// A new deadline that the person has not given reminders of their own follows the defaults of its kind, counted for
  /// whether it has a time; otherwise the reminders stay and only what cannot apply is turned into what can.
  private func refreshAlerts() {
    if isNew, !alertsEdited {
      deadline.alerts = DeadlineAlert.normalized(preferencesStore.preferences.alerts(for: deadline.kind), hasTime: hasTime)
    } else {
      deadline.alerts = DeadlineAlert.normalized(deadline.alerts, hasTime: hasTime)
    }
  }

  /// When one alert would fire for this deadline as it is being edited.
  private func fireDate(of alert: DeadlineAlert) -> Date? {
    var probe = deadline
    probe.time = hasTime ? (deadline.time ?? TimeOfDay(hour: 23, minute: 59)) : nil
    probe.alerts = [alert]
    return probe.alertDates(defaultTime: preferencesStore.preferences.allDayTime, calendar: .current).first?.fire
  }

  /// What would stop the reminders from arriving, or that there are none: the person should see it here.
  @ViewBuilder private var reminderNotice: some View {
    let preferences = preferencesStore.preferences
    if deadline.alerts.isEmpty {
      Text("No reminders: this deadline stays silent.", tableName: "Calendar")
    } else if !preferences.deadlinesEnabled {
      Text("Reminders about deadlines are turned off in Settings > Reminders.", tableName: "Calendar")
        .foregroundStyle(.red)
    } else if !preferences.deadlineKinds.contains(deadline.kind) {
      Text("Reminders for this kind of deadline are turned off in Settings > Reminders.", tableName: "Calendar")
        .foregroundStyle(.red)
    } else if access == .denied {
      Text("Notifications are turned off for Kitbag in iOS Settings, so these cannot be shown.", tableName: "Calendar")
        .foregroundStyle(.red)
    }
  }

  private func save() {
    var saved = deadline
    saved.title = saved.title.trimmingCharacters(in: .whitespaces)
    if !hasTime { saved.time = nil }
    saved.alerts = DeadlineAlert.normalized(saved.alerts, hasTime: hasTime)
    deadlines.upsert(saved, courseCode: saved.courseID.flatMap { timetable.course(id: $0)?.code })
    dismiss()
  }

  /// The courses of the current term, and the one this deadline already belongs to if it is from another term.
  private var courseChoices: [Course] {
    var choices = timetable.timetable.courses
    if let id = deadline.courseID, !choices.contains(where: { $0.id == id }), let linked = timetable.course(id: id) {
      choices.append(linked)
    }
    return choices
  }

  /// A `DatePicker` works with dates; a deadline's day is a `LocalDate`.
  private var dayBinding: Binding<Date> {
    Binding(
      get: { deadline.date.date(calendar: .current) },
      set: { deadline.date = LocalDate($0, calendar: .current) })
  }

  private var timeBinding: Binding<Date> {
    Binding(
      get: {
        let time = deadline.time ?? TimeOfDay(hour: 23, minute: 59)
        return Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: Date()) ?? Date()
      },
      set: {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
        deadline.time = TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
      })
  }
}
