import KitbagCore
import SwiftUI

// MARK: Words for an alert

extension DeadlineAlert {
  /// "1 day before", "30 minutes before", "When it is due", "On the day". `hasTime` tells a deadline with a time from one
  /// without; nil when it is not known (the alerts a kind of deadline starts with), where the unit decides.
  func title(hasTime: Bool?) -> String {
    if amount == 0 {
      let timed = hasTime ?? !unit.isWholeDays
      return timed ? L10n.string("When it is due", table: "Calendar") : L10n.string("On the day", table: "Calendar")
    }
    let span = Duration.seconds(leadMinutes * 60)
      .formatted(.units(allowed: [unit.durationUnit], width: .wide).locale(LanguageStore.shared.locale))
    return L10n.string("\(span) before", table: "Calendar")
  }
}

extension DeadlineAlert.Unit {
  fileprivate var durationUnit: Duration.UnitsFormatStyle.Unit {
    switch self {
    case .minutes: .minutes
    case .hours: .hours
    case .days: .days
    case .weeks: .weeks
    }
  }

  var title: LocalizedStringResource {
    switch self {
    case .minutes: LocalizedStringResource("Minutes", table: "Calendar")
    case .hours: LocalizedStringResource("Hours", table: "Calendar")
    case .days: LocalizedStringResource("Days", table: "Calendar")
    case .weeks: LocalizedStringResource("Weeks", table: "Calendar")
    }
  }
}

/// A list of alerts to edit, as rows for a form: each row can be tapped to change it or swiped away, and a menu adds one
/// from the usual choices or from a custom one. It is used for one deadline and for the alerts a kind of deadline starts
/// with.
struct AlertList: View {
  @Binding var alerts: [DeadlineAlert]
  /// Whether the deadline has a time; nil when editing the alerts a kind starts with, which serve both.
  let hasTime: Bool?
  let preferences: NotificationPreferences
  /// When an alert would fire, for the deadline being edited; nil where there is no deadline to count from.
  var fireDate: ((DeadlineAlert) -> Date?)?
  /// The moment the deadline is due, which quiet hours must not push a reminder past.
  var due: Date?
  /// Called when the person changes the list, so that a screen can stop replacing it with the defaults.
  var changed: () -> Void = {}

  @State private var editing: DeadlineAlert?

  var body: some View {
    ForEach(alerts) { alert in
      Button {
        editing = alert
      } label: {
        row(alert)
      }
      .buttonStyle(.plain)
    }
    .onDelete { offsets in
      alerts.remove(atOffsets: offsets)
      changed()
    }

    Menu {
      ForEach(presets, id: \.signature) { preset in
        Button {
          add(preset)
        } label: {
          Text(preset.title(hasTime: hasTime))
        }
        .disabled(alerts.contains { $0.signature == preset.signature })
      }
      Divider()
      Button {
        editing = DeadlineAlert(amount: 1, unit: hasTime == false ? .days : .hours)
      } label: {
        Label {
          Text("Custom…", tableName: "Calendar")
        } icon: {
          Image(systemName: "slider.horizontal.3")
        }
      }
    } label: {
      Label {
        Text("Add a reminder", tableName: "Calendar")
      } icon: {
        Image(systemName: "plus.circle.fill")
      }
    }
    .sheet(item: $editing) { alert in
      AlertEditor(alert: alert, hasTime: hasTime, preferences: preferences, fireDate: fireDate, due: due) { saved in
        if let index = alerts.firstIndex(where: { $0.id == saved.id }) {
          alerts[index] = saved
        } else {
          alerts.append(saved)
        }
        alerts = DeadlineAlert.normalized(alerts, hasTime: hasTime ?? true)
        changed()
      }
      .presentationDetents([.medium, .large])
    }
  }

  private func add(_ preset: DeadlineAlert) {
    alerts.append(preset)
    alerts = DeadlineAlert.normalized(alerts, hasTime: hasTime ?? true)
    changed()
  }

  /// The usual choices; the ones already in the list are dimmed.
  private var presets: [DeadlineAlert] {
    switch hasTime {
    case true?: [.minutes(0), .minutes(5), .minutes(15), .minutes(30), .hours(1), .hours(2), .days(1), .days(2), .weeks(1)]
    case false?: [.days(0), .days(1), .days(2), .days(3), .weeks(1)]
    case nil: [.days(0), .minutes(15), .minutes(30), .hours(1), .hours(3), .days(1), .days(2), .weeks(1)]
    }
  }

  private func row(_ alert: DeadlineAlert) -> some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 2) {
        Text(alert.title(hasTime: hasTime)).foregroundStyle(.primary)
        if hasTime != true, let time = alert.timeOfDay {
          Text("at \(time.formatted)", tableName: "Calendar").font(.caption).foregroundStyle(.secondary)
        }
        if let fireDate, let fire = fireDate(alert) {
          fireText(fire).font(.caption)
        }
      }
      Spacer(minLength: 8)
      Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
    }
    .contentShape(Rectangle())
  }

  /// When the reminder comes, and whether that is still ahead or got moved by the quiet hours.
  @ViewBuilder private func fireText(_ fire: Date) -> some View {
    let shown = preferences.adjusted(fire, notAfter: due ?? .distantFuture, calendar: .current)
    let format = Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day().hour().minute()
    if shown <= Date() {
      HStack(spacing: 4) {
        Text(shown, format: format)
        Text("· already passed", tableName: "Calendar")
      }
      .foregroundStyle(.red)
    } else if shown != fire {
      HStack(spacing: 4) {
        Image(systemName: "moon.zzz")
        Text(shown, format: format)
        Text("· after quiet hours", tableName: "Calendar")
      }
      .foregroundStyle(.secondary)
    } else {
      Text(shown, format: format).foregroundStyle(.secondary)
    }
  }
}

extension TimeOfDay {
  /// "9:00 AM" or "09:00", as the phone writes a time.
  var formatted: String {
    let date = Calendar.current.date(bySettingHour: min(hour, 23), minute: minute, second: 0, of: Date()) ?? Date()
    return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(LanguageStore.shared.locale))
  }
}

/// Changes one alert: how long before, and for a deadline with no time, at what time of the day.
struct AlertEditor: View {
  @Environment(\.dismiss) private var dismiss
  @State var alert: DeadlineAlert
  let hasTime: Bool?
  let preferences: NotificationPreferences
  let fireDate: ((DeadlineAlert) -> Date?)?
  let due: Date?
  let onSave: (DeadlineAlert) -> Void

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Stepper(value: $alert.amount, in: 0...(alert.unit == .minutes ? 999 : 99)) {
            Text(alert.title(hasTime: hasTime))
          }
          Picker(selection: $alert.unit) {
            ForEach(units, id: \.self) { unit in
              Text(unit.title).tag(unit)
            }
          } label: {
            Text("Unit", tableName: "Calendar")
          }
          .pickerStyle(.segmented)
        } header: {
          Text("How long before", tableName: "Calendar")
        } footer: {
          if hasTime != true, alert.unit.isWholeDays {
            Text("Zero means on the day itself.", tableName: "Calendar")
          }
        }

        if usesTimeOfDay {
          Section {
            Toggle(isOn: usualTime) {
              Text("Usual time (\(preferences.allDayTime.formatted))", tableName: "Calendar")
            }
            if alert.timeOfDay != nil {
              DatePicker(selection: timeBinding, displayedComponents: .hourAndMinute) {
                Text("Time", tableName: "Calendar")
              }
            }
          } header: {
            Text("Time of day", tableName: "Calendar")
          } footer: {
            Text("For a deadline with no time, the reminder comes at this time of the day.", tableName: "Calendar")
          }
        }

        if let fireDate, let fire = fireDate(alert) {
          Section {
            LabeledContent {
              Text(fire, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
            } label: {
              Text("Reminds you", tableName: "Calendar")
            }
          }
        }
      }
      .navigationTitle(Text("Reminder", tableName: "Calendar"))
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
          Button {
            onSave(alert)
            dismiss()
          } label: {
            Text("Done", tableName: "Calendar")
          }
        }
      }
      .onChange(of: alert.unit) { _, unit in
        if !unit.isWholeDays { alert.timeOfDay = nil }
      }
    }
  }

  private var units: [DeadlineAlert.Unit] {
    hasTime == false ? [.days, .weeks] : DeadlineAlert.Unit.allCases
  }

  /// Only a reminder counted in days for a deadline with no time has a time of day to choose.
  private var usesTimeOfDay: Bool { hasTime != true && alert.unit.isWholeDays }

  private var usualTime: Binding<Bool> {
    Binding(
      get: { alert.timeOfDay == nil },
      set: { usual in alert.timeOfDay = usual ? nil : preferences.allDayTime })
  }

  private var timeBinding: Binding<Date> {
    Binding(
      get: {
        let time = alert.timeOfDay ?? preferences.allDayTime
        return Calendar.current.date(bySettingHour: min(time.hour, 23), minute: time.minute, second: 0, of: Date())
          ?? Date()
      },
      set: {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
        alert.timeOfDay = TimeOfDay(hour: parts.hour ?? 9, minute: parts.minute ?? 0)
      })
  }
}
