import KitbagCore
import SwiftUI
import UIKit

extension NSAttributedString.Key {
  /// The address that a link in a note opens when it is tapped outside editing.
  static let kitbagLink = NSAttributedString.Key("dev.kosuke.kitbag.link")
}

/// A text view for notes written in Markdown. The marks stay in the text but the text is drawn the way it reads: headings
/// large, `**bold**` bold, a checklist item with a box that a tap checks. A bar above the keyboard applies the marks.
struct MarkdownEditor: UIViewRepresentable {
  @Binding var text: String
  /// Open with the keyboard up (for a note that has just been created).
  var autofocus = false
  var onPhoto: () -> Void
  var onFile: () -> Void

  @Environment(\.palette) private var palette
  @Environment(\.titleDesign) private var titleDesign

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeUIView(context: Context) -> NoteTextView {
    let view = NoteTextView()
    let coordinator = context.coordinator
    coordinator.textView = view
    view.delegate = coordinator
    view.backgroundColor = .clear
    view.alwaysBounceVertical = true
    view.keyboardDismissMode = .interactive
    view.textContainerInset = UIEdgeInsets(top: 14, left: 12, bottom: 24, right: 12)
    view.adjustsFontForContentSizeCategory = true
    view.smartDashesType = .no
    view.autocapitalizationType = .sentences
    view.inputAccessoryView = coordinator.makeBar()
    view.onContentSizeCategoryChange = { [weak coordinator] in coordinator?.restyle() }

    let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.tapped(_:)))
    tap.delegate = coordinator
    view.addGestureRecognizer(tap)

    coordinator.style = coordinator.currentStyle()
    view.text = text
    coordinator.restyle()
    if autofocus && text.isEmpty {
      DispatchQueue.main.async { view.becomeFirstResponder() }
    }
    return view
  }

  func updateUIView(_ view: NoteTextView, context: Context) {
    let coordinator = context.coordinator
    coordinator.parent = self
    let style = coordinator.currentStyle()
    let restyleNeeded = style != coordinator.style
    coordinator.style = style
    if view.text != text, view.markedTextRange == nil, !coordinator.isApplyingEdit {
      view.text = text
      coordinator.restyle()
    } else if restyleNeeded {
      coordinator.restyle()
    }
  }

  /// What the styling depends on besides the text. Colours made from SwiftUI's are never equal, so `key` stands for the
  /// accent colour.
  struct Style: Equatable {
    var accent: UIColor
    var key: String
    var design: UIFontDescriptor.SystemDesign

    static func == (lhs: Style, rhs: Style) -> Bool {
      lhs.key == rhs.key && lhs.design == rhs.design
    }
  }

  @MainActor
  final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
    var parent: MarkdownEditor
    weak var textView: NoteTextView?
    var style = Style(accent: .tintColor, key: "", design: .default)
    var isApplyingEdit = false
    /// Set while a touch that lands on a checkbox or a link is being handled, so that it does not start editing.
    private var touchHitsTarget = false

    init(_ parent: MarkdownEditor) {
      self.parent = parent
    }

    func currentStyle() -> Style {
      let design: UIFontDescriptor.SystemDesign
      switch parent.titleDesign {
      case .serif: design = .serif
      case .rounded: design = .rounded
      case .monospaced: design = .monospaced
      default: design = .default
      }
      return Style(
        accent: UIColor(parent.palette.accent), key: String(describing: parent.palette.accent), design: design)
    }

    // MARK: Delegate

    func textViewDidChange(_ textView: UITextView) {
      sync()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
      textView.typingAttributes = typingAttributes(at: textView.selectedRange.location)
    }

    func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
      !touchHitsTarget
    }

    func textView(
      _ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String
    ) -> Bool {
      guard !isApplyingEdit, replacement == "\n", range.length == 0, textView.markedTextRange == nil else {
        return true
      }
      if let edit = MarkdownEditing.continueList(in: textView.text, at: range.location) {
        apply(edit)
        return false
      }
      return true
    }

    /// Passes the text on to SwiftUI and draws the marks again.
    func sync() {
      guard let textView else { return }
      if parent.text != textView.text { parent.text = textView.text }
      restyle()
    }

    // MARK: Edits

    /// Replaces only what changed between the text now and `edit.text`, so that the text view's undo keeps working.
    func apply(_ edit: TextEdit) {
      guard let textView else { return }
      let old = textView.text as NSString
      let new = edit.text as NSString
      let shortest = min(old.length, new.length)
      var prefix = 0
      while prefix < shortest, old.character(at: prefix) == new.character(at: prefix) { prefix += 1 }
      var suffix = 0
      while suffix < shortest - prefix,
        old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix)
      {
        suffix += 1
      }
      let replaced = NSRange(location: prefix, length: old.length - prefix - suffix)
      let replacement = new.substring(with: NSRange(location: prefix, length: new.length - prefix - suffix))
      isApplyingEdit = true
      if replaced.length > 0 || !replacement.isEmpty,
        let start = textView.position(from: textView.beginningOfDocument, offset: replaced.location),
        let end = textView.position(from: start, offset: replaced.length),
        let range = textView.textRange(from: start, to: end)
      {
        textView.replace(range, withText: replacement)
      }
      textView.selectedRange = edit.selection
      isApplyingEdit = false
      sync()
      textView.scrollRangeToVisible(textView.selectedRange)
    }

    private func perform(_ edit: (String, NSRange) -> TextEdit) {
      guard let textView else { return }
      apply(edit(textView.text, textView.selectedRange))
    }

    func toggleInline(_ marker: String) {
      perform { MarkdownEditing.toggleInline(marker, in: $0, selection: $1) }
    }

    func toggleLine(_ style: MarkdownEditing.LineStyle) {
      perform { MarkdownEditing.toggleLine(style, in: $0, selection: $1) }
    }

    // MARK: Taps on checkboxes and links

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    )
      -> Bool
    {
      true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
      guard let textView else { return false }
      let point = touch.location(in: textView)
      touchHitsTarget = target(at: point) != nil
      return true
    }

    private enum Target {
      case checkbox(Int)
      case link(URL)
    }

    /// A checkbox or a link under the point. Links only count while the text is not being edited, because while it is
    /// a tap places the caret.
    private func target(at point: CGPoint) -> Target? {
      guard let textView, let index = characterIndex(at: point, in: textView) else { return nil }
      let ns = textView.text as NSString
      let line = ns.lineRange(for: NSRange(location: index, length: 0))
      let content = ns.substring(with: line).trimmingCharacters(in: .newlines)
      let block = MarkdownBlock.parse(content)
      if case .checkbox = block.kind, index >= line.location + block.indentLength,
        index < line.location + block.indentLength + 5
      {
        return .checkbox(index)
      }
      if !textView.isFirstResponder,
        let url = textView.textStorage.attribute(.kitbagLink, at: index, effectiveRange: nil) as? URL
      {
        return .link(url)
      }
      return nil
    }

    /// The character whose box holds the point, if any (a tap in empty space beside the text is not on a character).
    private func characterIndex(at point: CGPoint, in textView: UITextView) -> Int? {
      guard let position = textView.closestPosition(to: point) else { return nil }
      let offset = textView.offset(from: textView.beginningOfDocument, to: position)
      let length = (textView.text as NSString).length
      for candidate in [offset, offset - 1] where candidate >= 0 && candidate < length {
        guard let start = textView.position(from: textView.beginningOfDocument, offset: candidate),
          let end = textView.position(from: start, offset: 1),
          let range = textView.textRange(from: start, to: end)
        else { continue }
        if textView.selectionRects(for: range).contains(where: { $0.rect.insetBy(dx: -8, dy: -6).contains(point) }) {
          return candidate
        }
      }
      return nil
    }

    @objc func tapped(_ gesture: UITapGestureRecognizer) {
      // The text view decides whether to begin editing around the same moment, so the flag is cleared a beat later.
      defer { DispatchQueue.main.async { self.touchHitsTarget = false } }
      guard let textView, gesture.state == .ended else { return }
      switch target(at: gesture.location(in: textView)) {
      case .checkbox(let index):
        if let edit = MarkdownEditing.toggleCheckbox(in: textView.text, at: index) {
          var kept = edit
          kept.selection = textView.selectedRange
          apply(kept)
        }
      case .link(let url):
        UIApplication.shared.open(url)
      case nil:
        break
      }
    }

    // MARK: Looks

    private var bodyFont: UIFont { .preferredFont(forTextStyle: .body) }

    private func headingFont(_ level: Int) -> UIFont {
      let textStyle: UIFont.TextStyle = [.title1, .title2, .title3][min(max(level, 1), 3) - 1]
      var descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: level > 3 ? .headline : textStyle)
      if let designed = descriptor.withDesign(style.design) { descriptor = designed }
      if let bold = descriptor.withSymbolicTraits(.traitBold) { descriptor = bold }
      return UIFont(descriptor: descriptor, size: 0)
    }

    private var baseAttributes: [NSAttributedString.Key: Any] {
      [.font: bodyFont, .foregroundColor: UIColor.label]
    }

    private func typingAttributes(at location: Int) -> [NSAttributedString.Key: Any] {
      guard let textView else { return baseAttributes }
      let ns = textView.text as NSString
      let probe = NSRange(location: min(location, ns.length), length: 0)
      let line = ns.substring(with: ns.lineRange(for: probe)).trimmingCharacters(in: .newlines)
      var attributes = baseAttributes
      if case .heading(let level) = MarkdownBlock.parse(line).kind { attributes[.font] = headingFont(level) }
      return attributes
    }

    /// Draws every line the way it reads. Skipped while the keyboard is composing (Japanese, for example), because
    /// changing the text's attributes then ends the composition.
    func restyle() {
      guard let textView, textView.markedTextRange == nil else { return }
      let storage = textView.textStorage
      let string = storage.string as NSString
      let full = NSRange(location: 0, length: string.length)
      let selection = textView.selectedRange
      storage.beginEditing()
      storage.setAttributes(baseAttributes, range: full)
      string.enumerateSubstrings(in: full, options: .byParagraphs) { line, range, _, _ in
        if let line { self.styleLine(line, range: range, in: storage) }
      }
      storage.endEditing()
      if textView.selectedRange != selection { textView.selectedRange = selection }
      textView.typingAttributes = typingAttributes(at: selection.location)
    }

    private func styleLine(_ line: String, range: NSRange, in storage: NSTextStorage) {
      let block = MarkdownBlock.parse(line)
      let markerRange = NSRange(location: range.location, length: block.markerLength)
      let content = NSRange(location: range.location + block.markerLength, length: range.length - block.markerLength)
      let dim = UIColor.tertiaryLabel
      let accent = style.accent

      func hang() {
        let width = (line as NSString).substring(to: block.markerLength).size(withAttributes: [.font: bodyFont]).width
        let paragraph = NSMutableParagraphStyle()
        paragraph.headIndent = width
        paragraph.paragraphSpacing = 2
        storage.addAttribute(.paragraphStyle, value: paragraph, range: range)
      }

      switch block.kind {
      case .text:
        break
      case .heading(let level):
        storage.addAttribute(.font, value: headingFont(level), range: range)
        storage.addAttribute(.foregroundColor, value: dim, range: markerRange)
      case .bullet, .numbered:
        hang()
        storage.addAttribute(.foregroundColor, value: accent, range: markerRange)
      case .checkbox(let done):
        hang()
        storage.addAttribute(.foregroundColor, value: dim, range: markerRange)
        let box = NSRange(
          location: range.location + block.indentLength + 2,
          length: min(3, block.markerLength - block.indentLength - 2))
        if box.length > 0 {
          storage.addAttributes([.foregroundColor: accent, .font: bodyFont.withTraits(.traitBold)], range: box)
        }
        if done, content.length > 0 {
          storage.addAttributes(
            [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: UIColor.secondaryLabel],
            range: content)
        }
      case .quote:
        hang()
        storage.addAttribute(.foregroundColor, value: accent.withAlphaComponent(0.6), range: markerRange)
        if content.length > 0 {
          storage.addAttributes(
            [.foregroundColor: UIColor.secondaryLabel, .font: bodyFont.withTraits(.traitItalic)], range: content)
        }
      }
      if content.length > 0 { styleInline(in: storage, range: content) }
    }

    private static let rules: [(NSRegularExpression, Inline)] = {
      let table: [(String, Inline)] = [
        (#"\*\*(?=\S)(.+?)(?<=\S)\*\*"#, .bold(2)),
        (#"__(?=\S)(.+?)(?<=\S)__"#, .bold(2)),
        (#"~~(?=\S)(.+?)(?<=\S)~~"#, .strike),
        (#"(?<!\*)\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?!\*)"#, .italic),
        (#"(?<![_A-Za-z0-9])_(?=[^\s_])(.+?)(?<=[^\s_])_(?![_A-Za-z0-9])"#, .italic),
        (#"\[([^\]\n]+)\]\(([^)\s]+)\)"#, .link),
        (#"https?://[^\s)>\]]+"#, .bareLink),
        (#"`([^`\n]+)`"#, .code),
      ]
      return table.compactMap { pattern, kind in (try? NSRegularExpression(pattern: pattern)).map { ($0, kind) } }
    }()

    private enum Inline {
      case bold(Int)
      case italic
      case strike
      case code
      case link
      case bareLink
    }

    private func styleInline(in storage: NSTextStorage, range: NSRange) {
      let string = storage.string as NSString
      let dim = UIColor.tertiaryLabel
      let accent = style.accent

      func addTrait(_ traits: UIFontDescriptor.SymbolicTraits, _ target: NSRange) {
        storage.enumerateAttribute(.font, in: target) { value, run, _ in
          if let font = value as? UIFont { storage.addAttribute(.font, value: font.withTraits(traits), range: run) }
        }
      }

      for (expression, kind) in Self.rules {
        expression.enumerateMatches(in: string as String, range: range) { match, _, _ in
          guard let match else { return }
          let whole = match.range
          switch kind {
          case .bold(let width):
            addTrait(.traitBold, whole)
            storage.addAttribute(.foregroundColor, value: dim, range: NSRange(location: whole.location, length: width))
            storage.addAttribute(
              .foregroundColor, value: dim, range: NSRange(location: NSMaxRange(whole) - width, length: width))
          case .italic:
            addTrait(.traitItalic, whole)
            storage.addAttribute(.foregroundColor, value: dim, range: NSRange(location: whole.location, length: 1))
            storage.addAttribute(
              .foregroundColor, value: dim, range: NSRange(location: NSMaxRange(whole) - 1, length: 1))
          case .strike:
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: whole)
            storage.addAttribute(.foregroundColor, value: dim, range: NSRange(location: whole.location, length: 2))
            storage.addAttribute(
              .foregroundColor, value: dim, range: NSRange(location: NSMaxRange(whole) - 2, length: 2))
          case .code:
            let size = bodyFont.pointSize * 0.92
            storage.addAttributes(
              [
                .font: UIFont.monospacedSystemFont(ofSize: size, weight: .regular),
                .backgroundColor: UIColor.secondarySystemFill,
              ], range: whole)
            storage.addAttribute(.foregroundColor, value: dim, range: NSRange(location: whole.location, length: 1))
            storage.addAttribute(
              .foregroundColor, value: dim, range: NSRange(location: NSMaxRange(whole) - 1, length: 1))
          case .link:
            let title = match.range(at: 1)
            let address = string.substring(with: match.range(at: 2))
            storage.addAttribute(.foregroundColor, value: dim, range: whole)
            storage.addAttributes(
              [.foregroundColor: accent, .underlineStyle: NSUnderlineStyle.single.rawValue], range: title)
            if let url = URL(string: address) { storage.addAttribute(.kitbagLink, value: url, range: whole) }
          case .bareLink:
            if storage.attribute(.kitbagLink, at: whole.location, effectiveRange: nil) != nil { return }
            storage.addAttributes(
              [.foregroundColor: accent, .underlineStyle: NSUnderlineStyle.single.rawValue], range: whole)
            if let url = URL(string: string.substring(with: whole)) {
              storage.addAttribute(.kitbagLink, value: url, range: whole)
            }
          }
        }
      }
    }

    // MARK: The bar above the keyboard

    func makeBar() -> UIView {
      let bar = UIInputView(frame: CGRect(x: 0, y: 0, width: 320, height: 46), inputViewStyle: .keyboard)
      bar.allowsSelfSizing = true
      bar.autoresizingMask = .flexibleWidth

      let stack = UIStackView()
      stack.axis = .horizontal
      stack.spacing = 0
      stack.alignment = .center
      stack.translatesAutoresizingMaskIntoConstraints = false

      func button(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: symbol)
        configuration.baseForegroundColor = .label
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8)
        let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
        button.accessibilityLabel = label
        return button
      }

      let headings = UIMenu(
        children: (1...3).map { level in
          UIAction(
            title: String(localized: "Heading \(level)", table: "Notes"), image: UIImage(systemName: "\(level).circle")
          ) {
            [weak self] _ in self?.toggleLine(.heading(level))
          }
        })
      let headingButton = button("textformat.size", String(localized: "Heading", table: "Notes")) {}
      headingButton.menu = headings
      headingButton.showsMenuAsPrimaryAction = true

      let bold = button("bold", String(localized: "Bold", table: "Notes")) { [weak self] in self?.toggleInline("**") }
      let italic = button("italic", String(localized: "Italic", table: "Notes")) { [weak self] in
        self?.toggleInline("*")
      }
      let strike = button("strikethrough", String(localized: "Strikethrough", table: "Notes")) { [weak self] in
        self?.toggleInline("~~")
      }
      let code = button("chevron.left.forwardslash.chevron.right", String(localized: "Code", table: "Notes")) {
        [weak self] in self?.toggleInline("`")
      }
      let bullets = button("list.bullet", String(localized: "Bulleted list", table: "Notes")) { [weak self] in
        self?.toggleLine(.bullet)
      }
      let numbers = button("list.number", String(localized: "Numbered list", table: "Notes")) { [weak self] in
        self?.toggleLine(.numbered)
      }
      let checks = button("checklist", String(localized: "Checklist", table: "Notes")) { [weak self] in
        self?.toggleLine(.checkbox)
      }
      let quote = button("text.quote", String(localized: "Quote", table: "Notes")) { [weak self] in
        self?.toggleLine(.quote)
      }
      let photo = button("photo", String(localized: "Add a photo", table: "Notes")) { [weak self] in
        self?.parent.onPhoto()
      }
      let file = button("paperclip", String(localized: "Attach a file", table: "Notes")) { [weak self] in
        self?.parent.onFile()
      }
      // The ones used most come first; the bar scrolls for the rest.
      let items: [UIView] = [bold, italic, headingButton, bullets, checks, numbers, photo, file, strike, code, quote]
      items.forEach(stack.addArrangedSubview)

      let scroll = UIScrollView()
      scroll.showsHorizontalScrollIndicator = false
      scroll.translatesAutoresizingMaskIntoConstraints = false
      scroll.addSubview(stack)

      let hide = button("keyboard.chevron.compact.down", String(localized: "Hide the keyboard", table: "Notes")) {
        [weak self] in
        self?.textView?.resignFirstResponder()
      }
      hide.translatesAutoresizingMaskIntoConstraints = false

      bar.addSubview(scroll)
      bar.addSubview(hide)
      NSLayoutConstraint.activate([
        hide.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -4),
        hide.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        scroll.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 4),
        scroll.trailingAnchor.constraint(equalTo: hide.leadingAnchor),
        scroll.topAnchor.constraint(equalTo: bar.topAnchor),
        scroll.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
        stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
        stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
        stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
        stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
        stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        bar.heightAnchor.constraint(equalToConstant: 46),
      ])
      return bar
    }
  }
}

/// A text view that says when the text size setting changes, so that the fonts of the marks can be chosen again.
final class NoteTextView: UITextView {
  var onContentSizeCategoryChange: (() -> Void)?

  init() {
    super.init(frame: .zero, textContainer: nil)
    registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: NoteTextView, _) in
      view.onContentSizeCategoryChange?()
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

}

extension UIFont {
  /// This font with more traits (bold, italic) added to the ones it has.
  fileprivate func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
    guard let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(traits)) else {
      return self
    }
    return UIFont(descriptor: descriptor, size: pointSize)
  }
}
