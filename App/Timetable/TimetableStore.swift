import KitbagCore
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// All the terms, kept in a JSON file in the app's Application Support folder.
@MainActor
@Observable
final class TimetableStore {
  private(set) var library: TimetableLibrary
  /// True when the saved file could not be read; it was set aside (not overwritten) and an empty library started.
  private(set) var setAsideUnreadableFile = false
  private(set) var saveFailed = false
  private let url: URL
  private let legacyURL: URL

  init(url: URL = AppFiles.url("timetables.json"), legacyURL: URL = AppFiles.url("timetable.json")) {
    self.url = url
    self.legacyURL = legacyURL
    (library, setAsideUnreadableFile) = Self.load(url: url, legacyURL: legacyURL)
  }

  /// Reads the file again, after a backup was restored over it.
  func reload() {
    (library, setAsideUnreadableFile) = Self.load(url: url, legacyURL: legacyURL)
  }

  private static func load(url: URL, legacyURL: URL) -> (TimetableLibrary, Bool) {
    var loaded = TimetableLibrary()
    var setAside = false
    if let data = try? Data(contentsOf: url) {
      do {
        loaded = try TimetableLibrary(fileData: data)
        // A hand-written file has no ids; writing it back once keeps every id the same from now on.
        if let normalized = try? loaded.fileData(), normalized != data { try? AppFiles.write(normalized, to: url) }
      } catch {
        AppFiles.setAside(url)
        setAside = true
      }
    } else if let data = try? Data(contentsOf: legacyURL), let old = try? Timetable(fileData: data) {
      // The first version kept a single timetable; it becomes the first term. The old file is left where it is.
      loaded = TimetableLibrary(timetables: [old])
      try? AppFiles.write((try? loaded.fileData()) ?? Data(), to: url)
    }
    return (loaded, setAside)
  }

  // MARK: Reading

  /// The term in force today: what the Today screen, the calendar and the notes use.
  var timetable: Timetable { library.active(on: Date(), calendar: .current) ?? Timetable() }

  /// The terms, the latest first.
  var terms: [Timetable] { library.ordered }

  func term(id: UUID) -> Timetable? { library.timetable(id: id) }

  /// Every course in every term, for linking a deadline or a note to a course.
  func course(id: UUID) -> Course? {
    library.timetables.lazy.compactMap { $0.course(id: id) }.first
  }

  // MARK: Changes

  func upsertTerm(_ term: Timetable) {
    library.upsert(term)
    save()
  }

  func deleteTerm(id: UUID) {
    library.remove(id: id)
    save()
  }

  func prefer(_ id: UUID?) {
    library.preferredID = id
    save()
  }

  func upsertCourse(_ course: Course, in termID: UUID) {
    guard var term = library.timetable(id: termID) else { return }
    if let index = term.courses.firstIndex(where: { $0.id == course.id }) {
      term.courses[index] = course
    } else {
      term.courses.append(course)
    }
    upsertTerm(term)
  }

  func deleteCourse(id: UUID, in termID: UUID) {
    guard var term = library.timetable(id: termID) else { return }
    term.courses.removeAll { $0.id == id }
    upsertTerm(term)
  }

  func setGrade(_ grade: String?, courseID: UUID, in termID: UUID) {
    guard var term = library.timetable(id: termID), let index = term.courses.firstIndex(where: { $0.id == courseID })
    else {
      return
    }
    term.courses[index].grade = grade
    upsertTerm(term)
  }

  func dismissNotices() {
    setAsideUnreadableFile = false
    saveFailed = false
  }

  /// Reads a timetable file the person picked and adds it as a term (or replaces the term with the same id).
  func importFile(at fileURL: URL) throws -> UUID {
    let scoped = fileURL.startAccessingSecurityScopedResource()
    defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
    let term = try Timetable(fileData: try Data(contentsOf: fileURL))
    upsertTerm(term)
    return term.id
  }

  private func save() {
    do {
      try AppFiles.write(try library.fileData(), to: url)
      saveFailed = false
    } catch {
      saveFailed = true
    }
  }
}
