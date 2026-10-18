import Foundation
import Testing

@testable import KitbagCore

private func edit(_ text: String, _ location: Int, _ length: Int = 0) -> (String, NSRange) {
  (text, NSRange(location: location, length: length))
}

@Suite("MarkdownBlock")
struct MarkdownBlockTests {
  @Test func readsHeadings() {
    #expect(MarkdownBlock.parse("# Title").kind == .heading(1))
    #expect(MarkdownBlock.parse("# Title").markerLength == 2)
    #expect(MarkdownBlock.parse("###### Six").kind == .heading(6))
    #expect(MarkdownBlock.parse("####### Seven").kind == .text)
    #expect(MarkdownBlock.parse("#hashtag").kind == .text)
  }

  @Test func readsBulletsAndCheckboxes() {
    #expect(MarkdownBlock.parse("- item").kind == .bullet)
    #expect(MarkdownBlock.parse("* item").markerCharacter == "*")
    #expect(MarkdownBlock.parse("+ item").kind == .bullet)
    let nested = MarkdownBlock.parse("  - nested")
    #expect(nested.kind == .bullet)
    #expect(nested.indentLength == 2)
    #expect(nested.markerLength == 4)
    #expect(MarkdownBlock.parse("- [ ] todo").kind == .checkbox(done: false))
    #expect(MarkdownBlock.parse("- [ ] todo").markerLength == 6)
    #expect(MarkdownBlock.parse("- [x] done").kind == .checkbox(done: true))
    #expect(MarkdownBlock.parse("- [X] done").kind == .checkbox(done: true))
    #expect(MarkdownBlock.parse("- [ ]").kind == .checkbox(done: false))
    #expect(MarkdownBlock.parse("- [y] no").kind == .bullet)
  }

  @Test func readsNumbersAndQuotes() {
    #expect(MarkdownBlock.parse("1. one").kind == .numbered(1))
    #expect(MarkdownBlock.parse("1. one").markerLength == 3)
    #expect(MarkdownBlock.parse("12) twelve").kind == .numbered(12))
    #expect(MarkdownBlock.parse("12) twelve").markerCharacter == ")")
    #expect(MarkdownBlock.parse("1.5 liters").kind == .text)
    #expect(MarkdownBlock.parse("2024").kind == .text)
    #expect(MarkdownBlock.parse("> quote").kind == .quote)
    #expect(MarkdownBlock.parse("> quote").markerLength == 2)
    #expect(MarkdownBlock.parse(">tight").markerLength == 1)
  }

  @Test func leavesOtherLinesAlone() {
    for line in ["", "---", "***", "-no space", "plain words", "   "] {
      #expect(MarkdownBlock.parse(line).kind == .text)
    }
  }
}

@Suite("Markdown plain text")
struct MarkdownPlainTests {
  @Test func removesMarks() {
    #expect(Markdown.plain("## **Due** [Friday](https://x.test)") == "Due Friday")
    #expect(Markdown.plain("~~old~~ `code` ![alt](x.png)") == "old code alt")
    #expect(Markdown.plain("_slanted_ and *also*") == "slanted and also")
  }

  @Test func keepsWhatIsNotAMark() {
    #expect(Markdown.plain("snake_case_name stays") == "snake_case_name stays")
    #expect(Markdown.plain("2 * 3 * 4") == "2 * 3 * 4")
  }

  @Test func decoratesListItemsOnRequest() {
    #expect(Markdown.plain("- [ ] Buy *notebook*") == "Buy notebook")
    #expect(Markdown.plain("- [ ] Buy *notebook*", decorated: true) == "☐ Buy notebook")
    #expect(Markdown.plain("- [x] Done", decorated: true) == "☑ Done")
    #expect(Markdown.plain("- item", decorated: true) == "• item")
    #expect(Markdown.plain("1. first", decorated: true) == "1. first")
  }
}

@Suite("MarkdownEditing inline")
struct MarkdownInlineTests {
  @Test func wrapsTheSelection() {
    let (text, range) = edit("hello world", 6, 5)
    let result = MarkdownEditing.toggleInline("**", in: text, selection: range)
    #expect(result.text == "hello **world**")
    #expect(result.selection == NSRange(location: 8, length: 5))
  }

  @Test func unwrapsWhenTheMarksAreOutsideOrInside() {
    let outside = MarkdownEditing.toggleInline("**", in: "hello **world**", selection: NSRange(location: 8, length: 5))
    #expect(outside.text == "hello world")
    #expect(outside.selection == NSRange(location: 6, length: 5))
    let inside = MarkdownEditing.toggleInline("**", in: "hello **world**", selection: NSRange(location: 6, length: 9))
    #expect(inside.text == "hello world")
    #expect(inside.selection == NSRange(location: 6, length: 5))
  }

  @Test func putsAPairDownWithNothingSelected() {
    let result = MarkdownEditing.toggleInline("**", in: "ab", selection: NSRange(location: 1, length: 0))
    #expect(result.text == "a****b")
    #expect(result.selection == NSRange(location: 3, length: 0))
    let again = MarkdownEditing.toggleInline("**", in: result.text, selection: result.selection)
    #expect(again.text == "ab")
  }

  @Test func tellsItalicFromBold() {
    let both = MarkdownEditing.toggleInline("*", in: "**bold**", selection: NSRange(location: 2, length: 4))
    #expect(both.text == "***bold***")
    #expect(both.selection == NSRange(location: 3, length: 4))
    let off = MarkdownEditing.toggleInline("*", in: "*it*", selection: NSRange(location: 1, length: 2))
    #expect(off.text == "it")
    #expect(off.selection == NSRange(location: 0, length: 2))
  }

  @Test func countsUTF16Units() {
    let kana = MarkdownEditing.toggleInline("**", in: "日本語 テスト", selection: NSRange(location: 4, length: 3))
    #expect(kana.text == "日本語 **テスト**")
    #expect(kana.selection == NSRange(location: 6, length: 3))
    let emoji = MarkdownEditing.toggleInline("**", in: "😀 hi", selection: NSRange(location: 3, length: 2))
    #expect(emoji.text == "😀 **hi**")
    #expect(emoji.selection == NSRange(location: 5, length: 2))
  }
}

@Suite("MarkdownEditing lines")
struct MarkdownLineTests {
  @Test func addsAndRemovesABullet() {
    let added = MarkdownEditing.toggleLine(.bullet, in: "buy milk", selection: NSRange(location: 3, length: 0))
    #expect(added.text == "- buy milk")
    #expect(added.selection == NSRange(location: 5, length: 0))
    let removed = MarkdownEditing.toggleLine(.bullet, in: added.text, selection: added.selection)
    #expect(removed.text == "buy milk")
    #expect(removed.selection == NSRange(location: 3, length: 0))
  }

  @Test func putsTheCaretAfterTheMarkerWhenItWasInFront() {
    let result = MarkdownEditing.toggleLine(.bullet, in: "buy milk", selection: NSRange(location: 0, length: 0))
    #expect(result.selection == NSRange(location: 2, length: 0))
    let empty = MarkdownEditing.toggleLine(.bullet, in: "", selection: NSRange(location: 0, length: 0))
    #expect(empty.text == "- ")
    #expect(empty.selection == NSRange(location: 2, length: 0))
  }

  @Test func marksEveryLineOfASelection() {
    let bullets = MarkdownEditing.toggleLine(.bullet, in: "a\nb\nc", selection: NSRange(location: 0, length: 5))
    #expect(bullets.text == "- a\n- b\n- c")
    #expect(bullets.selection == NSRange(location: 0, length: 11))
    let numbers = MarkdownEditing.toggleLine(.numbered, in: "a\nb", selection: NSRange(location: 0, length: 3))
    #expect(numbers.text == "1. a\n2. b")
  }

  @Test func leavesTheNextLineAloneWhenTheSelectionEndsAfterABreak() {
    let result = MarkdownEditing.toggleLine(.bullet, in: "a\nb", selection: NSRange(location: 0, length: 2))
    #expect(result.text == "- a\nb")
    #expect(result.selection == NSRange(location: 0, length: 3))
  }

  @Test func replacesAnotherMarker() {
    let heading = MarkdownEditing.toggleLine(.heading(2), in: "- item", selection: NSRange(location: 6, length: 0))
    #expect(heading.text == "## item")
    #expect(heading.selection == NSRange(location: 7, length: 0))
    let same = MarkdownEditing.toggleLine(.heading(2), in: "## item", selection: NSRange(location: 7, length: 0))
    #expect(same.text == "item")
    let other = MarkdownEditing.toggleLine(.heading(1), in: "## item", selection: NSRange(location: 7, length: 0))
    #expect(other.text == "# item")
  }

  @Test func keepsTheIndentOfAList() {
    let result = MarkdownEditing.toggleLine(.bullet, in: "  - x", selection: NSRange(location: 5, length: 0))
    #expect(result.text == "  x")
    let checkbox = MarkdownEditing.toggleLine(.checkbox, in: "  task", selection: NSRange(location: 6, length: 0))
    #expect(checkbox.text == "  - [ ] task")
  }
}

@Suite("MarkdownEditing return and taps")
struct MarkdownReturnTests {
  @Test func continuesABullet() {
    let result = MarkdownEditing.continueList(in: "- one", at: 5)
    #expect(result?.text == "- one\n- ")
    #expect(result?.selection == NSRange(location: 8, length: 0))
  }

  @Test func countsUpAndStartsCheckboxesUnchecked() {
    #expect(MarkdownEditing.continueList(in: "1. one", at: 6)?.text == "1. one\n2. ")
    #expect(MarkdownEditing.continueList(in: "9) nine", at: 7)?.text == "9) nine\n10) ")
    let box = MarkdownEditing.continueList(in: "- [x] done", at: 10)
    #expect(box?.text == "- [x] done\n- [ ] ")
    #expect(box?.selection == NSRange(location: 17, length: 0))
    #expect(MarkdownEditing.continueList(in: "> hi", at: 4)?.text == "> hi\n> ")
  }

  @Test func splitsAnItemAtTheCaret() {
    let result = MarkdownEditing.continueList(in: "- ab", at: 3)
    #expect(result?.text == "- a\n- b")
    #expect(result?.selection == NSRange(location: 6, length: 0))
  }

  @Test func endsTheListOnAnEmptyItem() {
    let result = MarkdownEditing.continueList(in: "- one\n- ", at: 8)
    #expect(result?.text == "- one\n")
    #expect(result?.selection == NSRange(location: 6, length: 0))
    #expect(MarkdownEditing.continueList(in: "  - ", at: 4)?.text == "")
  }

  @Test func leavesReturnAloneElsewhere() {
    #expect(MarkdownEditing.continueList(in: "- one", at: 1) == nil)
    #expect(MarkdownEditing.continueList(in: "- one", at: 0) == nil)
    #expect(MarkdownEditing.continueList(in: "hello", at: 5) == nil)
    #expect(MarkdownEditing.continueList(in: "# Title", at: 7) == nil)
    #expect(MarkdownEditing.continueList(in: "x\n- two", at: 7)?.text == "x\n- two\n- ")
  }

  @Test func togglesACheckbox() {
    let text = "- [ ] a\n- [x] b"
    #expect(MarkdownEditing.toggleCheckbox(in: text, at: 2)?.text == "- [x] a\n- [x] b")
    #expect(MarkdownEditing.toggleCheckbox(in: text, at: 10)?.text == "- [ ] a\n- [ ] b")
    #expect(MarkdownEditing.toggleCheckbox(in: "- item", at: 2) == nil)
  }

  @Test func findsTheBoxForATap() {
    #expect(MarkdownEditing.checkboxRange(inLine: "- [ ] a", lineStart: 10) == NSRange(location: 12, length: 3))
    #expect(MarkdownEditing.checkboxRange(inLine: "  - [x] a", lineStart: 0) == NSRange(location: 4, length: 3))
    #expect(MarkdownEditing.checkboxRange(inLine: "- a", lineStart: 0) == nil)
  }
}
