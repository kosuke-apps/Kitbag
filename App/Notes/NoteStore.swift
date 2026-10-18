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
    var loaded = NoteBook()
    if let data = try? Data(contentsOf: url) {
      do {
        loaded = try NoteBook(fileData: data)
        if let normalized = try? loaded.fileData(), normalized != data { try? AppFiles.write(normalized, to: url) }
      } catch {
        AppFiles.setAside(url)
        setAsideUnreadableFile = true
      }
    }
    book = loaded
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
    saveNow()
  }

  /// Called when an editor closes: an empty note is dropped, and the rest is written at once.
  func finish(id: UUID) {
    if let note = book.note(id: id), note.isEmpty { book.remove(id: id) }
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
