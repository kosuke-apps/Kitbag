import KitbagCore
import PhotosUI
import QuickLook
import SwiftUI

/// The notes tool: a list with search, pinned notes first, and an editor for each note.
struct NotesView: View {
  @Environment(NoteStore.self) private var store
  @Environment(\.palette) private var palette

  /// A note to open straight away (from the Today screen).
  let initialNoteID: UUID?

  @State private var path: [UUID] = []
  @State private var query = ""

  var body: some View {
    NavigationStack(path: $path) {
      List {
        notices
        let results = store.book.search(query)
        if results.isEmpty {
          emptyState.listRowBackground(Color.clear)
        } else if query.isEmpty, !store.book.pinned.isEmpty {
          Section {
            ForEach(store.book.pinned) { row($0) }
          } header: {
            Text("Pinned", tableName: "Notes")
          }
          .listRowBackground(palette.card)
          Section {
            ForEach(results.filter { !$0.isPinned }) { row($0) }
          } header: {
            Text("Notes", tableName: "Notes")
          }
          .listRowBackground(palette.card)
        } else {
          ForEach(results) { row($0) }
            .listRowBackground(palette.card)
        }
      }
      .listStyle(.insetGrouped)
      .scrollContentBackground(.hidden)
      .themedScreen()
      .contentMargins(.bottom, 80, for: .scrollContent)
      .searchable(text: $query, prompt: Text("Search notes", tableName: "Notes"))
      .navigationTitle(Text("Notes", tableName: "Notes"))
      .navigationBarTitleDisplayMode(.inline)
      .navigationDestination(for: UUID.self) { NoteEditor(noteID: $0) }
      .overlay(alignment: .bottomTrailing) { newNoteButton }
    }
    .onAppear {
      if let id = initialNoteID, path.isEmpty, store.book.note(id: id) != nil { path = [id] }
    }
  }

  // MARK: Parts

  private func row(_ note: Note) -> some View {
    NavigationLink(value: note.id) {
      NoteRow(note: note)
    }
    .swipeActions(edge: .leading) {
      Button {
        store.setPinned(id: note.id, !note.isPinned)
      } label: {
        Label {
          note.isPinned ? Text("Unpin", tableName: "Notes") : Text("Pin", tableName: "Notes")
        } icon: {
          Image(systemName: note.isPinned ? "pin.slash" : "pin")
        }
      }
      .tint(.orange)
    }
    .swipeActions(edge: .trailing) {
      Button(role: .destructive) {
        store.remove(id: note.id)
      } label: {
        Label {
          Text("Delete", tableName: "Notes")
        } icon: {
          Image(systemName: "trash")
        }
      }
    }
  }

  @ViewBuilder private var emptyState: some View {
    if query.isEmpty {
      ContentUnavailableView {
        Label {
          Text("No notes yet", tableName: "Notes")
        } icon: {
          Image(systemName: "note.text")
        }
      } description: {
        Text("Write down what you want to keep. Pin a note to show it on the home screen.", tableName: "Notes")
      }
    } else {
      ContentUnavailableView.search(text: query)
    }
  }

  @ViewBuilder private var notices: some View {
    if store.setAsideUnreadableFile {
      Text(
        "The saved notes could not be read. They were kept as a separate file and a new list was started.",
        tableName: "Notes"
      )
      .font(.footnote)
      .listRowBackground(Color.yellow.opacity(0.25))
    }
    if store.saveFailed {
      Text("The notes could not be saved.", tableName: "Notes")
        .font(.footnote)
        .listRowBackground(Color.yellow.opacity(0.25))
    }
  }

  private var newNoteButton: some View {
    Button {
      query = ""
      path.append(store.create().id)
    } label: {
      Image(systemName: "square.and.pencil")
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 56, height: 56)
        .background(Color.accentColor, in: Circle())
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
    }
    .accessibilityLabel(Text("New note", tableName: "Notes"))
    .padding(20)
    .padding(.bottom, 44)
  }
}

/// A note in a list: its title, the start of its text, when it changed, and a pin if it is pinned.
struct NoteRow: View {
  @Environment(TimetableStore.self) private var timetable
  let note: Note

  var body: some View {
    let course = note.courseID.flatMap { timetable.course(id: $0) }
    VStack(alignment: .leading, spacing: 3) {
      HStack {
        Text(note.title.isEmpty ? String(localized: "New note", table: "Notes") : note.title)
          .font(.headline)
          .lineLimit(1)
        if note.isPinned {
          Image(systemName: "pin.fill").font(.caption).foregroundStyle(.orange)
        }
        if !note.attachments.isEmpty {
          Label("\(note.attachments.count)", systemImage: "paperclip")
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text("\(note.attachments.count) attachments", tableName: "Notes"))
        }
      }
      if !note.preview.isEmpty {
        Text(note.preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
      }
      HStack(spacing: 6) {
        Text(note.modifiedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
        if let course {
          Circle().fill(course.color.blockColor).frame(width: 9, height: 9)
            .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
          Text(course.code)
        }
      }
      .font(.caption)
      .foregroundStyle(.tertiary)
    }
    .padding(.vertical, 2)
  }
}

/// The text of one note, with its photos and files. It saves as you type, and an empty note is dropped when you leave.
struct NoteEditor: View {
  @Environment(NoteStore.self) private var store
  @Environment(TimetableStore.self) private var timetable
  @Environment(\.dismiss) private var dismiss

  let noteID: UUID

  @State private var text = ""
  @State private var confirmingDelete = false
  @State private var showingPhotos = false
  @State private var showingFiles = false
  @State private var pickedPhotos: [PhotosPickerItem] = []
  @State private var preview: URL?
  @State private var attachFailed = false

  var body: some View {
    let note = store.book.note(id: noteID)
    VStack(spacing: 0) {
      MarkdownEditor(
        text: $text, autofocus: note?.body.isEmpty ?? false,
        onPhoto: { showingPhotos = true }, onFile: { showingFiles = true }
      )
      if let note, !note.attachments.isEmpty {
        Divider()
        AttachmentStrip(noteID: noteID, attachments: note.attachments, preview: $preview)
      }
    }
    .themedScreen()
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItemGroup(placement: .bottomBar) {
        Button {
          store.setPinned(id: noteID, !(note?.isPinned ?? false))
        } label: {
          Image(systemName: note?.isPinned == true ? "pin.slash" : "pin")
        }
        .accessibilityLabel(
          note?.isPinned == true ? Text("Unpin", tableName: "Notes") : Text("Pin", tableName: "Notes"))
        courseMenu(note: note)
        attachMenu
        ShareLink(item: text) { Image(systemName: "square.and.arrow.up") }
          .disabled(text.isEmpty)
        Spacer()
        Button(role: .destructive) {
          confirmingDelete = true
        } label: {
          Image(systemName: "trash")
        }
        .accessibilityLabel(Text("Delete", tableName: "Notes"))
      }
    }
    .confirmationDialog(
      Text("Delete this note?", tableName: "Notes"), isPresented: $confirmingDelete, titleVisibility: .visible
    ) {
      Button(role: .destructive) {
        store.remove(id: noteID)
        dismiss()
      } label: {
        Text("Delete", tableName: "Notes")
      }
    }
    .photosPicker(isPresented: $showingPhotos, selection: $pickedPhotos, maxSelectionCount: 10, matching: .images)
    .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
      attachFiles(result)
    }
    .quickLookPreview($preview)
    .alert(Text("Could not attach that.", tableName: "Notes"), isPresented: $attachFailed) {
      Button {
      } label: {
        Text("OK", tableName: "Notes")
      }
    }
    .onAppear { text = note?.body ?? "" }
    .onChange(of: text) { _, new in store.updateBody(id: noteID, new) }
    .onChange(of: pickedPhotos) { _, items in
      guard !items.isEmpty else { return }
      Task { await attachPhotos(items) }
    }
    .onDisappear { store.finish(id: noteID) }
  }

  private var attachMenu: some View {
    Menu {
      Button {
        showingPhotos = true
      } label: {
        Label {
          Text("Add a photo", tableName: "Notes")
        } icon: {
          Image(systemName: "photo")
        }
      }
      Button {
        showingFiles = true
      } label: {
        Label {
          Text("Attach a file", tableName: "Notes")
        } icon: {
          Image(systemName: "paperclip")
        }
      }
    } label: {
      Image(systemName: "paperclip")
    }
    .accessibilityLabel(Text("Attach", tableName: "Notes"))
  }

  private func attachPhotos(_ items: [PhotosPickerItem]) async {
    pickedPhotos = []
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
    let stamp = formatter.string(from: Date())
    for (offset, item) in items.enumerated() {
      guard let data = try? await item.loadTransferable(type: Data.self) else {
        attachFailed = true
        continue
      }
      let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
      let suffix = items.count > 1 ? " (\(offset + 1))" : ""
      do {
        try store.attach(data: data, name: "Photo \(stamp)\(suffix).\(ext)", to: noteID)
      } catch {
        attachFailed = true
      }
    }
  }

  private func attachFiles(_ result: Result<[URL], Error>) {
    guard case .success(let urls) = result else {
      if case .failure = result { attachFailed = true }
      return
    }
    for url in urls {
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      do {
        try store.attach(fileAt: url, to: noteID)
      } catch {
        attachFailed = true
      }
    }
  }

  private func courseMenu(note: Note?) -> some View {
    Menu {
      Button {
        store.setCourse(id: noteID, nil)
      } label: {
        Text("No course", tableName: "Notes")
      }
      ForEach(timetable.timetable.courses) { course in
        Button {
          store.setCourse(id: noteID, course.id)
        } label: {
          if note?.courseID == course.id {
            Label(course.code, systemImage: "checkmark")
          } else {
            Text(course.code)
          }
        }
      }
    } label: {
      Image(systemName: "tag")
    }
    .accessibilityLabel(Text("Course", tableName: "Notes"))
  }
}
