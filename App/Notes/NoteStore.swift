import KitbagCore
import Observation
import SwiftUI

/// The notes, kept in a JSON file in the app's Application Support folder. Typing changes a note on every key, so the
/// file is written a moment after the last change and again when the editor closes.
@MainActor
@Observable
final class NoteStore {
  private(set) var book: NoteBook
  /// True when the saved file could not be read; it was set aside (not overwritten) and an empty list started.
  private(set) var setAsideUnreadableFile = false
  private(set) var saveFailed = false
  private let url: URL
  private var pendingSave: Task<Void, Never>?

  init(url: URL = AppFiles.url("notes.json")) {
    self.url = url
    (book, setAsideUnreadableFile) = Self.load(url: url)
  }

  /// Reads the file again, after a backup was restored over it.
  func reload() {
    pendingSave?.cancel()
    (book, setAsideUnreadableFile) = Self.load(url: url)
  }

  private static func load(url: URL) -> (NoteBook, Bool) {
    var loaded = NoteBook()
    var setAside = false
    if let data = try? Data(contentsOf: url) {
      do {
        loaded = try NoteBook(fileData: data)
        if let normalized = try? loaded.fileData(), normalized != data { try? AppFiles.write(normalized, to: url) }
      } catch {
        AppFiles.setAside(url)
        setAside = true
      }
    }
    return (loaded, setAside)
  }

  /// A new, empty note. It is kept only once it has text (see `finish`).
  @discardableResult
  func create(courseID: UUID? = nil) -> Note {
    let note = Note(courseID: courseID)
    book.upsert(note)
    return note
  }

  func updateBody(id: UUID, _ body: String) {
    guard var note = book.note(id: id), note.body != body else { return }
    note.body = body
    note.modifiedAt = Date()
    book.upsert(note)
    saveSoon()
  }

  func setPinned(id: UUID, _ pinned: Bool) {
    guard var note = book.note(id: id) else { return }
    note.isPinned = pinned
    book.upsert(note)
    saveNow()
  }

  func setCourse(id: UUID, _ courseID: UUID?) {
    guard var note = book.note(id: id) else { return }
    note.courseID = courseID
    book.upsert(note)
    saveNow()
  }

  func remove(id: UUID) {
    book.remove(id: id)
    try? FileManager.default.removeItem(at: folder(for: id))
    saveNow()
  }

  /// Called when an editor closes: an empty note is dropped, and the rest is written at once.
  func finish(id: UUID) {
    if let note = book.note(id: id), note.isEmpty {
      book.remove(id: id)
      try? FileManager.default.removeItem(at: folder(for: id))
    }
    saveNow()
  }

  // MARK: Attachments

  /// Where the photos and files of a note are kept: one folder per note, so that deleting the note deletes them.
  func folder(for noteID: UUID) -> URL {
    AppFiles.url("Attachments/\(noteID.uuidString)")
  }

  func url(for attachment: NoteAttachment, in noteID: UUID) -> URL {
    folder(for: noteID).appending(path: attachment.storedName)
  }

  /// Keeps `data` (a photo from the picker) with the note under `name`.
  func attach(data: Data, name: String, to noteID: UUID) throws {
    try add(name: name, byteCount: data.count, to: noteID) { try AppFiles.write(data, to: $0) }
  }

  /// Keeps a copy of a file with the note. The original is left where it is.
  func attach(fileAt source: URL, to noteID: UUID) throws {
    let size = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    try add(name: source.lastPathComponent, byteCount: size, to: noteID) { destination in
      try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
      try FileManager.default.copyItem(at: source, to: destination)
    }
  }

  func removeAttachment(_ id: UUID, from noteID: UUID) {
    guard var note = book.note(id: noteID), let attachment = note.attachments.first(where: { $0.id == id }) else {
      return
    }
    // The file sits in a folder of its own, which goes with it.
    let file = url(for: attachment, in: noteID)
    let parent = file.deletingLastPathComponent()
    try? FileManager.default.removeItem(at: parent == folder(for: noteID) ? file : parent)
    note.attachments.removeAll { $0.id == id }
    note.modifiedAt = Date()
    book.upsert(note)
    saveNow()
  }

  private func add(name: String, byteCount: Int, to noteID: UUID, write: (URL) throws -> Void) throws {
    guard var note = book.note(id: noteID) else { return }
    let id = UUID()
    let attachment = NoteAttachment(
      id: id, name: name, storedName: NoteAttachment.storedName(id: id, originalName: name), byteCount: byteCount)
    try write(url(for: attachment, in: noteID))
    note.attachments.append(attachment)
    note.modifiedAt = Date()
    book.upsert(note)
    saveNow()
  }

  func dismissNotices() {
    setAsideUnreadableFile = false
    saveFailed = false
  }

  private func saveSoon() {
    pendingSave?.cancel()
    pendingSave = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(600))
      guard !Task.isCancelled else { return }
      self?.saveNow()
    }
  }

  func saveNow() {
    pendingSave?.cancel()
    // Empty notes that are still open are not worth keeping on disk.
    var toSave = book
    toSave.notes.removeAll { $0.isEmpty }
    do {
      try AppFiles.write(try toSave.fileData(), to: url)
      saveFailed = false
    } catch {
      saveFailed = true
    }
  }
}
