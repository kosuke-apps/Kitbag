import KitbagCore
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// The timetable, kept in a JSON file in the app's Application Support folder.
@MainActor
@Observable
final class TimetableStore {
  private(set) var timetable: Timetable
  /// True when the saved file could not be read; it was set aside (not overwritten) and an empty timetable started.
  private(set) var setAsideUnreadableFile = false
  private(set) var saveFailed = false
  private let url: URL

  init(url: URL = TimetableStore.defaultURL) {
    self.url = url
    var loaded = Timetable()
    if let data = try? Data(contentsOf: url) {
      do {
        loaded = try Timetable(fileData: data)
        // A hand-written file has no ids; writing it back once keeps every course's id the same from now on.
        if let normalized = try? loaded.fileData(), normalized != data { try? AppFiles.write(normalized, to: url) }
      } catch {
        AppFiles.setAside(url)
        setAsideUnreadableFile = true
      }
    }
    timetable = loaded
  }

  nonisolated static var defaultURL: URL { AppFiles.url("timetable.json") }

  // MARK: Changes

  func replace(with timetable: Timetable) {
    self.timetable = timetable
    save()
  }

  func setTitle(_ title: String) {
    timetable.title = title
    save()
  }

  /// Adds a course, or replaces the one with the same id.
  func upsert(_ course: Course) {
    if let index = timetable.courses.firstIndex(where: { $0.id == course.id }) {
      timetable.courses[index] = course
    } else {
      timetable.courses.append(course)
    }
    save()
  }

  func deleteCourses(at offsets: IndexSet) {
    timetable.courses.remove(atOffsets: offsets)
    save()
  }

  func dismissNotices() {
    setAsideUnreadableFile = false
    saveFailed = false
  }

  /// Reads a timetable file the person picked, and makes it the timetable.
  func importFile(at fileURL: URL) throws {
    let scoped = fileURL.startAccessingSecurityScopedResource()
    defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
    replace(with: try Timetable(fileData: try Data(contentsOf: fileURL)))
  }

  private func save() {
    do {
      try AppFiles.write(try timetable.fileData(), to: url)
      saveFailed = false
    } catch {
      saveFailed = true
    }
  }
}

/// The timetable as a file for the system's "Save to Files" sheet.
struct TimetableDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.json] }

  var timetable: Timetable

  init(timetable: Timetable) { self.timetable = timetable }

  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
    timetable = try Timetable(fileData: data)
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: try timetable.fileData())
  }
}
