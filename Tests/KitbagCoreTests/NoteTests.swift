import Foundation
import Testing

@testable import KitbagCore

private func moment(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + seconds) }

@Suite("Note")
struct NoteTests {
  @Test func takesTheFirstLineAsTheTitle() {
    #expect(Note(body: "Buy a lab notebook\nBring it on Monday").title == "Buy a lab notebook")
    #expect(Note(body: "\n\n  Spaced  \nrest").title == "Spaced")
    #expect(Note(body: "## Heading\ntext").title == "Heading")
    #expect(Note(body: "").title == "")
    #expect(Note(body: " \n \n").isEmpty)
  }

  @Test func previewsTheRestOnOneLine() {
    #expect(Note(body: "Title\nfirst line\n\nsecond line").preview == "first line second line")
    #expect(Note(body: "Only a title").preview == "")
    let long = Note(body: "T\n" + String(repeating: "x", count: 300))
    #expect(long.preview.count == 161)
    #expect(long.preview.hasSuffix("…"))
  }

  @Test func ordersPinnedFirstThenNewest() {
    let book = NoteBook(notes: [
      Note(body: "old", createdAt: moment(0)),
      Note(body: "new", createdAt: moment(100)),
      Note(body: "pinned old", isPinned: true, createdAt: moment(1)),
      Note(body: "pinned new", isPinned: true, createdAt: moment(50)),
    ])
    #expect(book.sorted.map(\.body) == ["pinned new", "pinned old", "new", "old"])
    #expect(book.pinned.map(\.body) == ["pinned new", "pinned old"])
  }

  @Test func searchesEveryWordIgnoringCaseAndAccents() {
    let book = NoteBook(notes: [
      Note(body: "Café hours\nOpen until nine", createdAt: moment(0)),
      Note(body: "Exam topics\nCircuits and signals", createdAt: moment(10)),
    ])
    #expect(book.search("cafe").count == 1)
    #expect(book.search("CIRCUITS signals").count == 1)
    #expect(book.search("circuits cafe").isEmpty)
    #expect(book.search("  ").count == 2)
    #expect(book.search("zebra").isEmpty)
  }

  @Test func addsReplacesAndRemoves() {
    var book = NoteBook()
    var note = Note(body: "a")
    book.upsert(note)
    note.body = "b"
    book.upsert(note)
    #expect(book.notes.count == 1)
    #expect(book.note(id: note.id)?.body == "b")
    book.remove(id: note.id)
    #expect(book.notes.isEmpty)
  }

  @Test func roundTripsThroughAFile() throws {
    let book = NoteBook(notes: [
      Note(body: "x\ny", isPinned: true, createdAt: moment(0), modifiedAt: moment(5), courseID: UUID())
    ])
    let data = try book.fileData()
    #expect(try NoteBook(fileData: data) == book)
    #expect(String(decoding: data, as: UTF8.self).contains("2026-"))
  }

  @Test func readsTitleAndPreviewWithoutMarks() {
    let note = Note(body: "## **Shopping** list\n- [ ] milk\n- [x] eggs\n_bold_ move")
    #expect(note.title == "Shopping list")
    #expect(note.preview == "☐ milk ☑ eggs bold move")
  }

  @Test func countsAnAttachmentAsContent() {
    let file = NoteAttachment(name: "Lecture 3.pdf", storedName: "a.pdf", byteCount: 10)
    #expect(Note(body: "", attachments: [file]).isEmpty == false)
    #expect(Note(body: "").isEmpty)
    let book = NoteBook(notes: [Note(body: "", attachments: [file]), Note(body: "other", createdAt: moment(5))])
    #expect(book.search("lecture").count == 1)
  }

  @Test func recognisesPicturesAndNamesStoredFiles() {
    let id = UUID()
    #expect(NoteAttachment.storedName(id: id, originalName: "Photo.HEIC") == "\(id.uuidString)/Photo.HEIC")
    #expect(NoteAttachment.storedName(id: id, originalName: "a/b: c.pdf") == "\(id.uuidString)/a-b- c.pdf")
    #expect(NoteAttachment.storedName(id: id, originalName: "  ") == "\(id.uuidString)/file")
    #expect(NoteAttachment(name: "p", storedName: "id/x.jpeg", byteCount: 1).isImage)
    #expect(NoteAttachment(name: "p", storedName: "id/x.PNG", byteCount: 1).isImage)
    #expect(!NoteAttachment(name: "p", storedName: "id/x.pdf", byteCount: 1).isImage)
  }

  @Test func readsAFileFromBeforeAttachments() throws {
    let json = """
      {"version":1,"notes":[{"id":"6D49C272-CF51-4607-B62C-CCF0D86CEBBB","body":"old","isPinned":false,\
      "createdAt":"2026-10-01T10:00:00Z","modifiedAt":"2026-10-01T10:00:00Z"}]}
      """
    let book = try NoteBook(fileData: Data(json.utf8))
    #expect(book.notes.count == 1)
    #expect(book.notes[0].attachments.isEmpty)
  }

  @Test func roundTripsAttachments() throws {
    let file = NoteAttachment(name: "Sketch.png", storedName: "b.png", byteCount: 2048, addedAt: moment(3))
    let book = NoteBook(notes: [Note(body: "x", createdAt: moment(0), attachments: [file])])
    #expect(try NoteBook(fileData: try book.fileData()) == book)
  }
}
