import KitbagCore
import SwiftUI

/// The Data section of Settings: send everything to another place, or put a backup back.
struct DataSettings: View {
  @State private var importing = false
  @State private var candidate: URL?
  @State private var importFailed = false
  @State private var exporting = false
  @State private var exportFailed = false

  var body: some View {
    Section {
      Button {
        Task { await export() }
      } label: {
        HStack {
          Label {
            Text("Export everything…", tableName: "Settings")
          } icon: {
            Image(systemName: "square.and.arrow.up")
          }
          Spacer()
          if exporting { ProgressView() }
        }
      }
      .disabled(exporting)
      Button {
        importing = true
      } label: {
        Label {
          Text("Restore from a backup…", tableName: "Settings")
        } icon: {
          Image(systemName: "square.and.arrow.down")
        }
      }
    } header: {
      Text("Data", tableName: "Settings")
    } footer: {
      Text(
        "One file with the timetable, deadlines, notes with their photos and files, and the settings. Send it to yourself by AirDrop or keep it in Files; opening it on another iPhone offers to restore it. Calendar subscriptions are left out because their addresses are secret.",
        tableName: "Settings")
    }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.kitbagBackup]) { result in
      switch result {
      case .success(let url): candidate = url
      case .failure: importFailed = true
      }
    }
    .restoreBackup($candidate)
    .alert(Text("The backup could not be made.", tableName: "Settings"), isPresented: $exportFailed) {
      Button {
      } label: {
        Text("OK", tableName: "Notes")
      }
    }
    .alert(Text("That file could not be opened.", tableName: "Settings"), isPresented: $importFailed) {
      Button {
      } label: {
        Text("OK", tableName: "Notes")
      }
    }
  }
}

extension DataSettings {
  /// Makes the backup off the main thread (it copies every photo), then opens the share sheet with it.
  fileprivate func export() async {
    exporting = true
    let url = try? await Task.detached { try BackupManager().makeTemporaryBackup() }.value
    exporting = false
    if let url {
      ShareSheet.present(url)
    } else {
      exportFailed = true
    }
  }
}

/// The system share sheet for a file (AirDrop, Save to Files, Mail), presented from whatever is on top. Wrapping it in a
/// SwiftUI sheet made it close again at once.
@MainActor
private enum ShareSheet {
  static func present(_ url: URL) {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    guard var top = scene?.keyWindow?.rootViewController else { return }
    while let presented = top.presentedViewController { top = presented }
    let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    controller.popoverPresentationController?.sourceView = top.view
    top.present(controller, animated: true)
  }
}

extension View {
  /// Asks before a backup replaces what is in Kitbag, does it, and says how it went. Set `url` to a backup file.
  func restoreBackup(_ url: Binding<URL?>) -> some View {
    modifier(RestoreBackupModifier(url: url))
  }
}

private struct RestoreBackupModifier: ViewModifier {
  @Binding var url: URL?
  @Environment(TimetableStore.self) private var timetable
  @Environment(DeadlineStore.self) private var deadlines
  @Environment(NoteStore.self) private var notes
  @Environment(ThemeStore.self) private var themes
  @Environment(LayoutStore.self) private var layout
  @Environment(NotificationPreferencesStore.self) private var notifications
  @Environment(GradeScaleStore.self) private var gradeScales

  @State private var summary: BackupSummary?
  @State private var accessing: URL?
  @State private var outcome: Outcome?

  private enum Outcome: Identifiable {
    case restored
    case failed(String)

    var id: String {
      switch self {
      case .restored: "restored"
      case .failed(let text): "failed-\(text)"
      }
    }
  }

  func body(content: Content) -> some View {
    content
      .onChange(of: url) { _, new in
        if let new { prepare(new) }
      }
      .confirmationDialog(
        Text("Restore this backup?", tableName: "Settings"),
        isPresented: Binding(get: { summary != nil }, set: { if !$0 { cancel() } }), titleVisibility: .visible
      ) {
        Button(role: .destructive) {
          restore()
        } label: {
          Text("Replace what is in Kitbag", tableName: "Settings")
        }
        Button(role: .cancel) {
          cancel()
        } label: {
          Text("Cancel", tableName: "Settings")
        }
      } message: {
        if let summary {
          Text(
            "Made \(summary.createdAt.formatted(date: .abbreviated, time: .shortened)). It replaces the timetable, deadlines, notes and settings that are in Kitbag now. What is here now is saved first in a backup of its own, so this can be undone.",
            tableName: "Settings")
        }
      }
      .alert(
        Text(outcomeTitle, tableName: "Settings"),
        isPresented: Binding(get: { outcome != nil }, set: { if !$0 { outcome = nil } })
      ) {
        Button {
          outcome = nil
        } label: {
          Text("OK", tableName: "Notes")
        }
      } message: {
        if case .failed(let text) = outcome { Text(text) }
      }
  }

  private var outcomeTitle: LocalizedStringKey {
    if case .failed = outcome { return "The backup could not be restored." }
    return "Restored."
  }

  private func prepare(_ file: URL) {
    if file.startAccessingSecurityScopedResource() { accessing = file }
    do {
      summary = try BackupManager().summary(of: file)
    } catch {
      finish()
      outcome = .failed(String(localized: "This is not a Kitbag backup, or it is damaged.", table: "Settings"))
    }
  }

  private func cancel() {
    summary = nil
    finish()
  }

  private func finish() {
    accessing?.stopAccessingSecurityScopedResource()
    accessing = nil
    url = nil
  }

  private func restore() {
    guard let file = url else { return }
    summary = nil
    do {
      try BackupManager().restore(from: file)
      timetable.reload()
      deadlines.reload()
      notes.reload()
      themes.reload()
      layout.reload()
      notifications.reload()
      gradeScales.reload()
      WidgetBridge.sync(theme: themes.themeID)
      outcome = .restored
    } catch {
      outcome = .failed(
        String(
          localized: "Nothing was lost: what was in Kitbag before is kept in a backup of its own.", table: "Settings"))
    }
    finish()
  }
}
