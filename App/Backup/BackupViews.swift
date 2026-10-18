import KitbagCore
import SwiftUI

/// The Data section of Settings: send everything to another place, or put a backup back.
struct DataSettings: View {
  @Environment(BackupFolderStore.self) private var folder
  @State private var choosingFolder = false
  @State private var folderRestore: URL?
  @State private var nothingInFolder = false
  @State private var importing = false
  @State private var candidate: URL?
  @State private var importFailed = false
  @State private var exporting = false
  @State private var exportFailed = false

  var body: some View {
    Group {
      manualSection
      folderSection
    }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.kitbagBackup]) { result in
      switch result {
      case .success(let url): candidate = url
      case .failure: importFailed = true
      }
    }
    .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
      if case .success(let url) = result {
        folder.choose(url)
        Task { await folder.backUpIfDue(force: true) }
      }
    }
    .restoreBackup($candidate)
    .restoreBackup($folderRestore)
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
    .alert(Text("There is no backup in that folder yet.", tableName: "Settings"), isPresented: $nothingInFolder) {
      Button {
      } label: {
        Text("OK", tableName: "Notes")
      }
    }
  }

  private var manualSection: some View {
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
  }

  /// Automatic backups into a folder the person picks, for example in iCloud Drive, so that another device can restore them.
  private var folderSection: some View {
    Section {
      if folder.isSet {
        LabeledContent {
          Text(folder.folderName ?? "")
        } label: {
          Text("Backup folder", tableName: "Settings")
        }
        if let last = folder.lastBackup {
          LabeledContent {
            Text(last.formattedInLanguage(date: .abbreviated, time: .shortened))
          } label: {
            Text("Last backup", tableName: "Settings")
          }
        }
        if let error = folder.lastError {
          Text(error).font(.footnote).foregroundStyle(.red)
        }
        Button {
          Task { await folder.backUpIfDue(force: true) }
        } label: {
          HStack {
            Label {
              Text("Back up now", tableName: "Settings")
            } icon: {
              Image(systemName: "arrow.triangle.2.circlepath")
            }
            Spacer()
            if folder.isWorking { ProgressView() }
          }
        }
        .disabled(folder.isWorking)
        Button {
          Task {
            if let copy = try? await folder.newestBackupCopy() {
              folderRestore = copy
            } else {
              nothingInFolder = true
            }
          }
        } label: {
          Label {
            Text("Restore the newest backup from it", tableName: "Settings")
          } icon: {
            Image(systemName: "clock.arrow.circlepath")
          }
        }
        Button {
          choosingFolder = true
        } label: {
          Text("Choose another folder…", tableName: "Settings")
        }
        Button(role: .destructive) {
          folder.forget()
        } label: {
          Text("Stop backing up to a folder", tableName: "Settings")
        }
      } else {
        Button {
          choosingFolder = true
        } label: {
          Label {
            Text("Back up to a folder…", tableName: "Settings")
          } icon: {
            Image(systemName: "folder.badge.plus")
          }
        }
      }
    } header: {
      Text("Backup folder", tableName: "Settings")
    } footer: {
      Text(
        "Pick a folder in iCloud Drive and Kitbag saves a dated backup there once a day, keeping the last ten. On another iPhone or iPad, pick the same folder and restore the newest one. This is not live sync: whichever device backed up last has the newest data.",
        tableName: "Settings")
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
  @Environment(GuestRuntimes.self) private var guests

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
            "Made \(summary.createdAt.formattedInLanguage(date: .abbreviated, time: .shortened)). It replaces the timetable, deadlines, notes and settings that are in Kitbag now. What is here now is saved first in a backup of its own, so this can be undone.",
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
      outcome = .failed(L10n.string("This is not a Kitbag backup, or it is damaged.", table: "Settings"))
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
      LanguageStore.shared.reload()
      guests.applyLanguage(LanguageStore.shared.choice)
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
