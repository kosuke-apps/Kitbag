import KitbagCore
import SwiftUI
import UniformTypeIdentifiers

/// Bytes for the system's "Save to Files" sheet: an `.ics` calendar file or a JSON file.
struct ExportDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.calendarEvent, .json] }

  var data: Data

  init(data: Data) { self.data = data }

  init(configuration: ReadConfiguration) throws {
    guard let contents = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
    data = contents
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}

/// What an imported calendar file would add: the person picks which of its events become deadlines.
struct ImportPreview: Identifiable {
  let id = UUID()
  let candidates: [Deadline]
}

struct ImportPreviewSheet: View {
  @Environment(DeadlineStore.self) private var deadlines
  @Environment(TimetableStore.self) private var timetable
  @Environment(\.dismiss) private var dismiss
  @Environment(\.palette) private var palette

  let candidates: [Deadline]
  @State private var selected: Set<UUID>

  init(candidates: [Deadline]) {
    self.candidates = candidates
    _selected = State(initialValue: Set(candidates.map(\.id)))
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          ForEach(candidates) { item in
            Button {
              if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
            } label: {
              row(item)
            }
          }
        } header: {
          HStack {
            Text("Choose what to import as deadlines", tableName: "Calendar")
            Spacer()
            Button {
              selected = selected.isEmpty ? Set(candidates.map(\.id)) : []
            } label: {
              selected.isEmpty ? Text("All", tableName: "Calendar") : Text("None", tableName: "Calendar")
            }
            .textCase(nil)
          }
        }
        .listRowBackground(palette.card)
      }
      .scrollContentBackground(.hidden)
      .themedScreen()
      .navigationTitle(Text("Import", tableName: "Calendar"))
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
            deadlines.importDeadlines(candidates.filter { selected.contains($0.id) }) { timetable.course(id: $0)?.code }
            dismiss()
          } label: {
            Text("Import", tableName: "Calendar")
          }
          .disabled(selected.isEmpty)
        }
      }
    }
  }

  private func row(_ item: Deadline) -> some View {
    let course = item.courseID.flatMap { timetable.course(id: $0) }
    let isUpdate = deadlines.book.deadlines.contains { $0.id == item.id }
    return HStack(spacing: 10) {
      Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
        .foregroundStyle(selected.contains(item.id) ? Color.accentColor : Color.secondary)
      VStack(alignment: .leading, spacing: 2) {
        Text(item.title).foregroundStyle(.primary).lineLimit(2)
        HStack(spacing: 6) {
          Image(systemName: item.kind.symbol).foregroundStyle(item.kind.color)
          if let course { Text(course.code) }
          Text(item.date.date(calendar: .current), format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
          if let time = item.time { Text(time.twelveHourText) }
          if isUpdate { Text("Update", tableName: "Calendar").bold() }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
  }
}

/// The subscribed calendars: each with its status and a switch for the Today screen, and a way to add one.
struct SubscriptionsView: View {
  @Environment(SubscriptionStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @Environment(\.palette) private var palette

  @State private var adding = false

  var body: some View {
    NavigationStack {
      List {
        if store.subscriptions.isEmpty {
          Section {
            Text(
              "Subscribe to your Canvas or Google calendar, and its events appear in Kitbag and stay up to date.",
              tableName: "Calendar"
            )
            .font(.subheadline)
          }
          .listRowBackground(palette.card)
        }
        ForEach(store.subscriptions) { subscription in
          VStack(alignment: .leading, spacing: 6) {
            HStack {
              Text(subscription.name).font(.headline)
              Spacer()
              if store.refreshing.contains(subscription.id) {
                ProgressView()
              } else {
                Button {
                  Task { await store.refresh(subscription.id) }
                } label: {
                  Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Refresh", tableName: "Calendar"))
              }
            }
            status(subscription)
            Toggle(
              isOn: Binding(
                get: { subscription.showsOnToday }, set: { store.setShowsOnToday(subscription.id, $0) })
            ) {
              Text("Show on Today", tableName: "Calendar")
            }
            .font(.subheadline)
          }
          .padding(.vertical, 2)
          .swipeActions {
            Button(role: .destructive) {
              store.remove(id: subscription.id)
            } label: {
              Label {
                Text("Remove", tableName: "Calendar")
              } icon: {
                Image(systemName: "trash")
              }
            }
          }
        }
        .listRowBackground(palette.card)
        Section {
          Button {
            adding = true
          } label: {
            Label {
              Text("Add a subscription", tableName: "Calendar")
            } icon: {
              Image(systemName: "plus")
            }
          }
        }
        .listRowBackground(palette.card)
      }
      .scrollContentBackground(.hidden)
      .themedScreen()
      .navigationTitle(Text("Subscriptions", tableName: "Calendar"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button {
            dismiss()
          } label: {
            Text("Done", tableName: "Calendar")
          }
        }
      }
      .sheet(isPresented: $adding) { AddSubscriptionView() }
    }
  }

  @ViewBuilder private func status(_ subscription: CalendarSubscription) -> some View {
    if let error = subscription.lastError {
      Text("Could not update: \(error)", tableName: "Calendar").font(.footnote).foregroundStyle(.red)
    } else {
      HStack(spacing: 6) {
        Text("Events: \(subscription.eventCount)", tableName: "Calendar")
        if let fetched = subscription.lastFetched {
          Text("·")
          Text("Updated \(fetched.formatted(date: .abbreviated, time: .shortened))", tableName: "Calendar")
        }
      }
      .font(.footnote)
      .foregroundStyle(.secondary)
    }
  }
}

struct AddSubscriptionView: View {
  @Environment(SubscriptionStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  @State private var name = ""
  @State private var address = ""
  @State private var working = false
  @State private var failure: String?

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField(text: $name, prompt: Text("Canvas", tableName: "Calendar")) {
            Text("Name", tableName: "Calendar")
          }
          TextField(text: $address, prompt: Text("https://…", tableName: "Calendar"), axis: .vertical) {
            Text("Address", tableName: "Calendar")
          }
          .keyboardType(.URL)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .lineLimit(1...4)
        } footer: {
          VStack(alignment: .leading, spacing: 6) {
            Text("Canvas: Calendar, then Calendar Feed, and copy the address.", tableName: "Calendar")
            Text("Google Calendar: the calendar's settings, then Secret address in iCal format.", tableName: "Calendar")
            Text("The address works like a password, so Kitbag keeps it in the keychain.", tableName: "Calendar")
          }
        }
        if let failure {
          Section { Text(failure).foregroundStyle(.red) }
        }
      }
      .navigationTitle(Text("Add a subscription", tableName: "Calendar"))
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
          if working {
            ProgressView()
          } else {
            Button(action: add) { Text("Add", tableName: "Calendar") }
              .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }
      }
    }
  }

  private func add() {
    working = true
    failure = nil
    Task {
      do {
        try await store.add(name: name, address: address)
        dismiss()
      } catch {
        failure = SubscriptionStore.describe(error)
      }
      working = false
    }
  }
}
