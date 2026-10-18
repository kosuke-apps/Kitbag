import KitbagCore
import SwiftUI

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
      } header: {
        Text("Deadlines", tableName: "Settings")
      } footer: {
        Text(
          "Each deadline keeps its own lead time, which you set when you edit it.", tableName: "Settings")
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
      ? String(localized: "All", table: "Settings")
      : String(localized: "\(courses.count - muted) of \(courses.count)", table: "Settings")
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
