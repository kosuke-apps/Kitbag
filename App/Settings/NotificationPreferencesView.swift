import KitbagCore
import SwiftUI
import UserNotifications

/// What Kitbag reminds the person of, and when. Reminders are useful to some people and a nuisance to others, so every kind
/// can be turned off and the ones that are on can be tuned.
struct NotificationPreferencesView: View {
  @Environment(NotificationPreferencesStore.self) private var store
  @Environment(TimetableStore.self) private var timetable
  @Environment(\.palette) private var palette

  var body: some View {
    @Bindable var store = store
    List {
      Section {
        Toggle(isOn: $store.preferences.deadlinesEnabled) {
          Text("Remind me about deadlines", tableName: "Settings")
        }
        if store.preferences.deadlinesEnabled {
          ForEach(DeadlineKind.allCases, id: \.self) { kind in
            Toggle(isOn: kindBinding(kind)) {
              Label {
                Text(kind.title)
              } icon: {
                Image(systemName: kind.symbol).foregroundStyle(kind.color)
              }
            }
          }
        }
        if store.preferences.deadlinesEnabled {
          NavigationLink {
            DefaultAlertsView()
          } label: {
            Text("What new deadlines start with", tableName: "Settings")
          }
          DatePicker(selection: timeBinding(\.allDayTime), displayedComponents: .hourAndMinute) {
            Text("Morning reminder time", tableName: "Settings")
          }
          Picker(selection: $store.preferences.followUpDays) {
            Text("Never", tableName: "Settings").tag(0)
            ForEach(1...NotificationPreferences.maxFollowUps, id: \.self) { days in
              Text("For \(days) mornings", tableName: "Settings").tag(days)
            }
          } label: {
            Text("Remind again if not done", tableName: "Settings")
          }
        }
      } header: {
        Text("Deadlines", tableName: "Settings")
      } footer: {
        Text(
          "Every deadline can have several reminders, set when you edit it. The morning time is used for deadlines with no time of day. Reminding again repeats at that time on the mornings after the day it was due, for deadlines you have not ticked off.",
          tableName: "Settings")
      }
      .listRowBackground(palette.card)

      Section {
        NavigationLink {
          PendingRemindersView()
        } label: {
          Label {
            Text("Scheduled on this iPhone", tableName: "Settings")
          } icon: {
            Image(systemName: "bell.badge")
          }
        }
      } footer: {
        Text(
          "Shows what iOS will actually deliver. iOS allows an app at most 64 waiting reminders, so Kitbag schedules the soonest ones and adds the rest each time it opens.",
          tableName: "Settings")
      }
      .listRowBackground(palette.card)

      Section {
        Toggle(isOn: $store.preferences.classesEnabled) {
          Text("Remind me before classes", tableName: "Settings")
        }
        if store.preferences.classesEnabled {
          Picker(selection: $store.preferences.classLeadMinutes) {
            ForEach([5, 10, 15, 30, 60], id: \.self) { minutes in
              Text("\(minutes) min before", tableName: "Settings").tag(minutes)
            }
          } label: {
            Text("How long before", tableName: "Settings")
          }
          NavigationLink {
            MutedCoursesView()
          } label: {
            LabeledContent {
              Text(mutedSummary)
            } label: {
              Text("Courses", tableName: "Settings")
            }
          }
        }
      } header: {
        Text("Classes", tableName: "Settings")
      } footer: {
        Text(
          "Reminders are made for the next week of classes each time Kitbag runs, so they stop by themselves when a term ends.",
          tableName: "Settings")
      }
      .listRowBackground(palette.card)

      Section {
        Toggle(isOn: $store.preferences.quietHoursEnabled) {
          Text("Quiet hours", tableName: "Settings")
        }
        if store.preferences.quietHoursEnabled {
          DatePicker(selection: timeBinding(\.quietStart), displayedComponents: .hourAndMinute) {
            Text("From", tableName: "Settings")
          }
          DatePicker(selection: timeBinding(\.quietEnd), displayedComponents: .hourAndMinute) {
            Text("Until", tableName: "Settings")
          }
        }
      } header: {
        Text("Quiet hours", tableName: "Settings")
      } footer: {
        Text(
          "A reminder that falls in these hours waits until they end, unless that would be after the thing is due.",
          tableName: "Settings")
      }
      .listRowBackground(palette.card)

      Section {
        Toggle(isOn: $store.preferences.signatureEnabled) {
          Text("Warn before the signature runs out", tableName: "Settings")
        }
      } header: {
        Text("Signature", tableName: "Settings")
      } footer: {
        Text(
          "Two days before, the evening before and the morning of the day Kitbag stops opening.",
          tableName: "Settings")
      }
      .listRowBackground(palette.card)
    }
    .scrollContentBackground(.hidden)
    .themedScreen()
    .navigationTitle(Text("Reminders", tableName: "Settings"))
    .navigationBarTitleDisplayMode(.inline)
  }

  private func kindBinding(_ kind: DeadlineKind) -> Binding<Bool> {
    Binding(
      get: { store.preferences.deadlineKinds.contains(kind) },
      set: { on in
        if on {
          store.preferences.deadlineKinds.insert(kind)
        } else {
          store.preferences.deadlineKinds.remove(kind)
        }
      })
  }

  /// A time of day as the date the picker works with.
  private func timeBinding(_ keyPath: WritableKeyPath<NotificationPreferences, TimeOfDay>) -> Binding<Date> {
    Binding(
      get: {
        let time = store.preferences[keyPath: keyPath]
        return Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: Date()) ?? Date()
      },
      set: { date in
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        store.preferences[keyPath: keyPath] = TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
      })
  }

  private var mutedSummary: String {
    let courses = timetable.timetable.courses
    let muted = courses.filter { store.preferences.mutedCourseIDs.contains($0.id) }.count
    return muted == 0
      ? L10n.string("All", table: "Settings")
      : L10n.string("\(courses.count - muted) of \(courses.count)", table: "Settings")
  }
}

/// A switch for every course of the term in force: the classes of a course that is off get no reminder.
private struct MutedCoursesView: View {
  @Environment(NotificationPreferencesStore.self) private var store
  @Environment(TimetableStore.self) private var timetable
  @Environment(\.palette) private var palette

  var body: some View {
    List {
      Section {
        ForEach(timetable.timetable.courses) { course in
          Toggle(isOn: binding(course.id)) {
            HStack(spacing: 8) {
              Circle().fill(course.color.blockColor).frame(width: 11, height: 11)
                .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
              VStack(alignment: .leading, spacing: 0) {
                Text(course.code)
                if !course.title.isEmpty { Text(course.title).font(.caption).foregroundStyle(.secondary) }
              }
            }
          }
        }
      } footer: {
        Text("Remind me before the classes of the courses that are on.", tableName: "Settings")
      }
      .listRowBackground(palette.card)
    }
    .scrollContentBackground(.hidden)
    .themedScreen()
    .navigationTitle(Text("Courses", tableName: "Settings"))
    .navigationBarTitleDisplayMode(.inline)
  }

  private func binding(_ id: UUID) -> Binding<Bool> {
    Binding(
      get: { !store.preferences.mutedCourseIDs.contains(id) },
      set: { on in
        if on {
          store.preferences.mutedCourseIDs.remove(id)
        } else {
          store.preferences.mutedCourseIDs.insert(id)
        }
      })
  }
}

/// The reminders that new deadlines of each kind start with (an exam can start with more than an assignment).
private struct DefaultAlertsView: View {
  @Environment(NotificationPreferencesStore.self) private var store
  @Environment(\.palette) private var palette

  var body: some View {
    List {
      Section {
        ForEach(DeadlineKind.allCases, id: \.self) { kind in
          NavigationLink {
            DefaultAlertsEditor(kind: kind)
          } label: {
            LabeledContent {
              Text(summary(kind)).multilineTextAlignment(.trailing)
            } label: {
              Label {
                Text(kind.title)
              } icon: {
                Image(systemName: kind.symbol).foregroundStyle(kind.color)
              }
            }
          }
        }
      } footer: {
        Text(
          "A new deadline starts with the reminders of its kind, and you can change them for that deadline. Deadlines you import from a calendar start with them too.",
          tableName: "Settings")
      }
      .listRowBackground(palette.card)
    }
    .scrollContentBackground(.hidden)
    .themedScreen()
    .navigationTitle(Text("New deadlines", tableName: "Settings"))
    .navigationBarTitleDisplayMode(.inline)
  }

  private func summary(_ kind: DeadlineKind) -> String {
    let alerts = store.preferences.alerts(for: kind)
    guard !alerts.isEmpty else { return L10n.string("None", table: "Settings") }
    return alerts.map { $0.title(hasTime: nil) }.joined(separator: ", ")
  }
}

private struct DefaultAlertsEditor: View {
  @Environment(NotificationPreferencesStore.self) private var store
  @Environment(\.palette) private var palette
  let kind: DeadlineKind

  var body: some View {
    List {
      Section {
        AlertList(alerts: alerts, hasTime: nil, preferences: store.preferences)
      } footer: {
        Text(
          "For a deadline with no time of day, a reminder counted in hours or minutes comes on the day itself, at the morning reminder time.",
          tableName: "Settings")
      }
      .listRowBackground(palette.card)

      if store.preferences.hasCustomAlerts(for: kind) {
        Section {
          Button {
            store.preferences.defaultAlerts[kind.rawValue] = nil
          } label: {
            Text("Use Kitbag's suggestion", tableName: "Settings")
          }
        }
        .listRowBackground(palette.card)
      }
    }
    .scrollContentBackground(.hidden)
    .themedScreen()
    .navigationTitle(Text(kind.title))
    .navigationBarTitleDisplayMode(.inline)
  }

  private var alerts: Binding<[DeadlineAlert]> {
    Binding(
      get: { store.preferences.alerts(for: kind) },
      set: { store.preferences.setAlerts($0, for: kind) })
  }
}

/// What iOS has waiting to show, read from the phone itself rather than worked out again: if a reminder is not here, it will
/// not arrive.
private struct PendingRemindersView: View {
  @Environment(\.palette) private var palette
  @Environment(\.scenePhase) private var scenePhase
  @State private var mine: [PendingReminder] = []
  @State private var others = 0
  @State private var loaded = false
  @State private var status: UNAuthorizationStatus = .authorized

  private let scheduler = ReminderScheduler()

  var body: some View {
    List {
      Section {
        LabeledContent {
          Text("\(mine.count) of 64", tableName: "Settings")
        } label: {
          Text("Kitbag's reminders", tableName: "Settings")
        }
        if others > 0 {
          LabeledContent {
            Text(others, format: .number)
          } label: {
            Text("From Headway", tableName: "Settings")
          }
        }
        if status == .denied {
          Text("Notifications are turned off for Kitbag in iOS Settings, so none of these will be shown.", tableName: "Settings")
            .foregroundStyle(.red)
        }
      }
      .listRowBackground(palette.card)

      if loaded, mine.isEmpty {
        Section {
          Text("Nothing is scheduled right now.", tableName: "Settings").foregroundStyle(.secondary)
        }
        .listRowBackground(palette.card)
      }

      Section {
        ForEach(mine) { item in
          HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol(item.kind)).foregroundStyle(.secondary).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
              Text(item.title).font(.subheadline.weight(.medium))
              let detail = [item.subtitle, item.body].filter { !$0.isEmpty }.joined(separator: " · ")
              if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
              if let date = item.date {
                Text(date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                  .font(.caption.weight(.medium))
                  .foregroundStyle(palette.accent)
              }
            }
          }
        }
      }
      .listRowBackground(palette.card)
    }
    .scrollContentBackground(.hidden)
    .themedScreen()
    .navigationTitle(Text("Scheduled", tableName: "Settings"))
    .navigationBarTitleDisplayMode(.inline)
    .task { await load() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { Task { await load() } }
    }
  }

  private func load() async {
    (mine, others) = await scheduler.pendingSummary()
    status = await scheduler.status()
    loaded = true
  }

  private func symbol(_ kind: PendingReminder.Kind) -> String {
    switch kind {
    case .deadline: "checkmark.circle"
    case .snoozed: "zzz"
    case .classStart: "graduationcap"
    case .signature: "signature"
    }
  }
}
