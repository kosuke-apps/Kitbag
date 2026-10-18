import Foundation

/// What a line of a note is, judging by its first characters. Notes are written in Markdown, so a line that starts
/// with `# ` is a heading, `- ` a bullet, `- [ ] ` a checkbox, `1. ` a numbered item and `> ` a quote.
public struct MarkdownBlock: Equatable, Sendable {
  public enum Kind: Equatable, Sendable {
    case text
    case heading(Int)
    case bullet
    case numbered(Int)
    case checkbox(done: Bool)
    case quote
  }

  public var kind: Kind
  /// Length in UTF-16 units of the spaces in front of the marker.
  public var indentLength: Int
  /// Length in UTF-16 units of the spaces and the marker, including the space after it.
  public var markerLength: Int
  /// The `-`, `*` or `+` of a bullet or checkbox, or the `.` or `)` after a number; nil for the other kinds.
  public var markerCharacter: Character?

  public var isList: Bool {
    switch kind {
    case .bullet, .numbered, .checkbox: true
    case .text, .heading, .quote: false
    }
  }

  /// Reads the start of one line (without its line break).
  public static func parse(_ line: String) -> MarkdownBlock {
    let units = Array(line.utf16)
    var start = 0
    while start < units.count, units[start] == 0x20 || units[start] == 0x09 { start += 1 }
    func block(_ kind: Kind, _ marker: Int, _ character: Character? = nil) -> MarkdownBlock {
      MarkdownBlock(kind: kind, indentLength: start, markerLength: marker, markerCharacter: character)
    }
    let plain = MarkdownBlock(kind: .text, indentLength: start, markerLength: start, markerCharacter: nil)
    guard start < units.count else { return plain }

    func at(_ index: Int) -> UInt16? { index < units.count ? units[index] : nil }
    let first = units[start]

    if first == 0x23 {  // #
      var end = start
      while at(end) == 0x23 { end += 1 }
      if end - start <= 6, at(end) == 0x20 { return block(.heading(end - start), end + 1) }
      return plain
    }
    if first == 0x2D || first == 0x2A || first == 0x2B {  // - * +
      guard at(start + 1) == 0x20 else { return plain }
      let character = Character(UnicodeScalar(first) ?? "-")
      if at(start + 2) == 0x5B, let mark = at(start + 3), at(start + 4) == 0x5D,
        at(start + 5) == nil || at(start + 5) == 0x20,
        mark == 0x20 || mark == 0x78 || mark == 0x58
      {
        return block(.checkbox(done: mark != 0x20), min(start + 6, units.count), character)
      }
      return block(.bullet, start + 2, character)
    }
    if first >= 0x30, first <= 0x39 {  // 0-9
      var end = start
      var number = 0
      while let digit = at(end), digit >= 0x30, digit <= 0x39, end - start < 9 {
        number = number * 10 + Int(digit - 0x30)
        end += 1
      }
      if let separator = at(end), separator == 0x2E || separator == 0x29, at(end + 1) == 0x20 {
        return block(.numbered(number), end + 2, Character(UnicodeScalar(separator) ?? "."))
      }
      return plain
    }
    if first == 0x3E {  // >
      return block(.quote, at(start + 1) == 0x20 ? start + 2 : start + 1)
    }
    return plain
  }

  /// The text of the line after the indent and the marker.
  public func content(of line: String) -> String {
    (line as NSString).substring(from: min(markerLength, (line as NSString).length))
  }
}

/// Notes without their Markdown marks, for a title and a one-line preview.
public enum Markdown {
  private static let inlinePatterns: [(NSRegularExpression, String)] = {
    let patterns: [(String, String)] = [
      (#"!\[(.*?)\]\(.*?\)"#, "$1"),
      (#"\[(.+?)\]\(.*?\)"#, "$1"),
      (#"\*\*(.+?)\*\*"#, "$1"),
      (#"__(.+?)__"#, "$1"),
      (#"~~(.+?)~~"#, "$1"),
      (#"`(.+?)`"#, "$1"),
      (#"(?<!\*)\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?!\*)"#, "$1"),
      (#"(?<![_A-Za-z0-9])_(?=[^\s_])(.+?)(?<=[^\s_])_(?![_A-Za-z0-9])"#, "$1"),
    ]
    return patterns.compactMap { pattern, template in
      (try? NSRegularExpression(pattern: pattern)).map { ($0, template) }
    }
  }()

  /// One line without its marks: `## **Due** [Friday](https://x.test)` becomes `Due Friday`. With `decorated`, a list
  /// item keeps a symbol (`•`, `☐`, `☑`, `1.`) so that a preview still reads like a list.
  public static func plain(_ line: String, decorated: Bool = false) -> String {
    let block = MarkdownBlock.parse(line)
    var text = block.content(of: line)
    for (expression, template) in inlinePatterns {
      text = expression.stringByReplacingMatches(
        in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: template)
    }
    text = text.trimmingCharacters(in: .whitespaces)
    guard decorated else { return text }
    switch block.kind {
    case .bullet: return "• " + text
    case .checkbox(let done): return (done ? "☑ " : "☐ ") + text
    case .numbered(let number): return "\(number). " + text
    case .text, .heading, .quote: return text
    }
  }
}

/// The text and the selection after an edit.
public struct TextEdit: Equatable, Sendable {
  public var text: String
  public var selection: NSRange

  public init(text: String, selection: NSRange) {
    self.text = text
    self.selection = selection
  }
}

/// The edits that the buttons above the keyboard make to a note's Markdown. They work on UTF-16 offsets, the units a
/// text view reports its selection in, and know nothing about the view.
public enum MarkdownEditing {
  public enum LineStyle: Equatable, Sendable {
    case heading(Int)
    case bullet
    case numbered
    case checkbox
    case quote
  }

  // MARK: Inline marks

  /// Wraps the selection in `marker` (`**` for bold, `*` for italic, `` ` `` for code, `~~` for strike), or takes the
  /// marks off when the selection is already wrapped. With nothing selected it puts a pair down and the caret between.
  public static func toggleInline(_ marker: String, in text: String, selection: NSRange) -> TextEdit {
    let ns = text as NSString
    let selection = clamp(selection, to: ns.length)
    let length = (marker as NSString).length
    let before = ns.substring(to: selection.location)
    let after = ns.substring(from: NSMaxRange(selection))
    let selected = ns.substring(with: selection)

    // A single `*` is also half of a bold `**`, so it only counts when no second one is next to it.
    func isWrapped() -> Bool {
      guard before.hasSuffix(marker), after.hasPrefix(marker) else { return false }
      guard length == 1, let character = marker.first else { return true }
      return before.dropLast().last != character && after.dropFirst().first != character
    }

    if isWrapped() {
      let unwrapped = String(before.dropLast(marker.count)) + selected + String(after.dropFirst(marker.count))
      return TextEdit(
        text: unwrapped, selection: NSRange(location: selection.location - length, length: selection.length))
    }
    if selection.length >= 2 * length, selected.hasPrefix(marker), selected.hasSuffix(marker),
      !(length == 1 && selected.hasPrefix(marker + marker))
    {
      let inner = String(selected.dropFirst(marker.count).dropLast(marker.count))
      return TextEdit(
        text: before + inner + after,
        selection: NSRange(location: selection.location, length: (inner as NSString).length))
    }
    return TextEdit(
      text: before + marker + selected + marker + after,
      selection: NSRange(location: selection.location + length, length: selection.length))
  }

  // MARK: Line marks

  /// Gives every line the selection touches the marker of `style`, or takes it off when they all have it already.
  /// Another marker on a line is replaced.
  public static func toggleLine(_ style: LineStyle, in text: String, selection: NSRange) -> TextEdit {
    let ns = text as NSString
    let selection = clamp(selection, to: ns.length)
    let (range, lines) = lineInfo(text, selection)
    let blocks = lines.map { MarkdownBlock.parse($0.content) }
    let allHave = blocks.allSatisfy { matches($0.kind, style) }

    var result = ns
    var delta = 0
    var firstDelta = 0
    for (offset, entry) in lines.enumerated().reversed() {
      let block = blocks[offset]
      let rest = block.content(of: entry.content)
      let indent = String(entry.content.prefix(block.indentLength))
      let line: String
      if allHave {
        line = indent + rest
      } else if isHeading(style) || style == .quote {
        line = markerText(style, number: offset + 1) + rest
      } else {
        line = indent + markerText(style, number: offset + 1) + rest
      }
      result = result.replacingCharacters(in: entry.range, with: line) as NSString
      let change = (line as NSString).length - entry.range.length
      delta += change
      if offset == 0 { firstDelta = change }
    }

    let first = lines[0]
    if selection.length == 0 {
      // Keep the caret where it was in the text: after the marker if it was inside the old one.
      let oldMarker = blocks[0].markerLength
      let newMarker = oldMarker + firstDelta
      let relative = selection.location - first.range.location
      let newRelative = relative <= oldMarker ? newMarker : relative + firstDelta
      return TextEdit(
        text: result as String, selection: NSRange(location: first.range.location + newRelative, length: 0))
    }
    return TextEdit(
      text: result as String,
      selection: NSRange(location: first.range.location, length: NSMaxRange(range) - first.range.location + delta))
  }

  // MARK: Return and taps

  /// What pressing return does in a list: the next item starts with its own marker (a number goes up by one, a checkbox
  /// starts unchecked), and return on an item with nothing in it ends the list. Nil when the line is not a list item or
  /// the caret is in front of its marker, so that return does what it always does.
  public static func continueList(in text: String, at location: Int) -> TextEdit? {
    let ns = text as NSString
    guard location >= 0, location <= ns.length else { return nil }
    let (_, lines) = lineInfo(text, NSRange(location: location, length: 0))
    guard let entry = lines.first else { return nil }
    let block = MarkdownBlock.parse(entry.content)
    guard block.isList || block.kind == .quote, location - entry.range.location >= block.markerLength else {
      return nil
    }

    let rest = block.content(of: entry.content).trimmingCharacters(in: .whitespaces)
    if rest.isEmpty {
      let replaced = ns.replacingCharacters(in: entry.range, with: "")
      return TextEdit(text: replaced, selection: NSRange(location: entry.range.location, length: 0))
    }
    let indent = String(entry.content.prefix(block.indentLength))
    let next: String
    switch block.kind {
    case .bullet: next = "\(block.markerCharacter ?? "-") "
    case .checkbox: next = "\(block.markerCharacter ?? "-") [ ] "
    case .numbered(let number): next = "\(number + 1)\(block.markerCharacter ?? ".") "
    case .quote: next = "> "
    case .text, .heading: return nil
    }
    let insertion = "\n" + indent + next
    let replaced = ns.replacingCharacters(in: NSRange(location: location, length: 0), with: insertion)
    return TextEdit(text: replaced, selection: NSRange(location: location + (insertion as NSString).length, length: 0))
  }

  /// Checks or unchecks the checkbox on the line that holds `location`. Nil when that line has no checkbox.
  public static func toggleCheckbox(in text: String, at location: Int) -> TextEdit? {
    let ns = text as NSString
    guard location >= 0, location <= ns.length else { return nil }
    let (_, lines) = lineInfo(text, NSRange(location: location, length: 0))
    guard let entry = lines.first else { return nil }
    let block = MarkdownBlock.parse(entry.content)
    guard case .checkbox(let done) = block.kind else { return nil }
    let box = NSRange(location: entry.range.location + block.indentLength + 3, length: 1)
    let replaced = ns.replacingCharacters(in: box, with: done ? " " : "x")
    return TextEdit(text: replaced, selection: NSRange(location: location, length: 0))
  }

  /// The range of the `[ ]` of the checkbox on a line, so that a tap on it can be told from a tap on the text.
  public static func checkboxRange(inLine line: String, lineStart: Int) -> NSRange? {
    let block = MarkdownBlock.parse(line)
    guard case .checkbox = block.kind else { return nil }
    return NSRange(location: lineStart + block.indentLength + 2, length: 3)
  }

  // MARK: Helpers

  private static func isHeading(_ style: LineStyle) -> Bool {
    if case .heading = style { return true }
    return false
  }

  private static func matches(_ kind: MarkdownBlock.Kind, _ style: LineStyle) -> Bool {
    switch (kind, style) {
    case (.heading(let a), .heading(let b)): a == b
    case (.bullet, .bullet), (.numbered, .numbered), (.checkbox, .checkbox), (.quote, .quote): true
    default: false
    }
  }

  private static func markerText(_ style: LineStyle, number: Int) -> String {
    switch style {
    case .heading(let level): String(repeating: "#", count: max(1, min(level, 6))) + " "
    case .bullet: "- "
    case .numbered: "\(number). "
    case .checkbox: "- [ ] "
    case .quote: "> "
    }
  }

  private static func clamp(_ range: NSRange, to length: Int) -> NSRange {
    let location = max(0, min(range.location, length))
    return NSRange(location: location, length: max(0, min(range.length, length - location)))
  }

  /// The lines that a selection touches, each with its range (without the line break) and its text. A selection that
  /// ends just after a line break does not touch the next line.
  private static func lineInfo(
    _ text: String, _ selection: NSRange
  ) -> (range: NSRange, lines: [(range: NSRange, content: String)]) {
    let ns = text as NSString
    var probe = selection
    if probe.length > 0,
      let last = (ns.substring(with: NSRange(location: NSMaxRange(probe) - 1, length: 1))).unicodeScalars.first,
      CharacterSet.newlines.contains(last)
    {
      probe.length -= 1
    }
    let range = ns.lineRange(for: probe)
    var lines: [(range: NSRange, content: String)] = []
    ns.enumerateSubstrings(in: range, options: .byLines) { substring, substringRange, _, _ in
      lines.append((substringRange, substring ?? ""))
    }
    if lines.isEmpty { lines = [(NSRange(location: range.location, length: 0), "")] }
    let covered = NSRange(
      location: lines[0].range.location, length: NSMaxRange(lines[lines.count - 1].range) - lines[0].range.location)
    return (covered, lines)
  }
}
