import AppKit

/// Live presentation over unchanged Markdown. Attribute edits do not participate
/// in text undo and all ranges remain the original UTF-16 source coordinates.
@MainActor final class NoteWriteStyle {
  private(set) var lastStyledLength = 0
  private(set) var index = NoteMarkupIndex()
  private var selection = NSRange(location: NSNotFound, length: 0)
  private var images: [UUID: (data: Data, image: NSImage)] = [:]
  private static var expressions: [String: NSRegularExpression] = [:]

  static func ink(dark: Bool) -> NSColor {
    dark
      ? NSColor(srgbRed: 0.91, green: 0.93, blue: 0.89, alpha: 1)
      : NSColor(srgbRed: 0.17, green: 0.20, blue: 0.18, alpha: 1)
  }
  static func attributes(dark: Bool) -> [NSAttributedString.Key: Any] {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 4
    paragraph.paragraphSpacing = 5
    return [
      .font: NSFont.systemFont(ofSize: 14), .foregroundColor: ink(dark: dark),
      .paragraphStyle: paragraph,
    ]
  }

  func apply(
    to storage: NSTextStorage, note: NoteDocument, dark: Bool,
    editedRange: NSRange? = nil, selection: NSRange = NSRange(location: NSNotFound, length: 0),
    width: CGFloat = 460, inheritedAttributes: [NSAttributedString.Key: Any]? = nil
  ) {
    self.selection = selection
    if editedRange == nil {
      images = images.filter { id, cached in
        note.attachments.contains { $0.id == id && $0.data == cached.data }
      }
    }
    let changed = index.update(storage.string as NSString, editedRange: editedRange)
    if let inheritedAttributes, let editedRange, note.decorations.isEmpty {
      lastStyledLength = editedRange.length
      if editedRange.length > 0 { storage.setAttributes(inheritedAttributes, range: editedRange) }
    } else {
      render(changed, to: storage, note: note, dark: dark, width: width)
    }
  }

  /// A plain edit cannot change Markdown structure when both edges are clear
  /// of delimiters. Reuse the existing run in oversized paragraphs; syntax,
  /// links, equations, IME and annotation edits use the normal parser path.
  func inheritedAttributes(in storage: NSTextStorage, range: NSRange, replacement: String)
    -> [NSAttributedString.Key: Any]?
  {
    let source = storage.string as NSString
    guard source.length > 0, !index.blocks.isEmpty, NSMaxRange(range) <= source.length,
      source.lineRange(for: range).length > 2048,
      replacement.unicodeScalars.allSatisfy({
        CharacterSet.alphanumerics.union(.whitespaces).contains($0)
      }),
      source.substring(with: range).unicodeScalars.allSatisfy({
        CharacterSet.alphanumerics.union(.whitespaces).contains($0)
      })
    else { return nil }
    let block = index.blocks[index.index(at: range.location)]
    guard block.fence == nil, block.afterFence == nil, block.math == nil else { return nil }
    let edge = NSRange(
      location: max(block.range.location, range.location - 2),
      length: min(source.length, NSMaxRange(range) + 2)
        - max(block.range.location, range.location - 2))
    let delimiters = CharacterSet(charactersIn: "*_$`~\\[]{}<>#!+-|\n\r")
    guard source.substring(with: edge).rangeOfCharacter(from: delimiters) == nil else { return nil }
    let first = source.substring(
      with: NSRange(location: block.range.location, length: min(3, block.range.length)))
    guard first.rangeOfCharacter(from: delimiters) == nil else { return nil }
    let attributes = storage.attributes(
      at: min(range.location, source.length - 1), effectiveRange: nil)
    guard attributes[.noteLiteral] == nil, attributes[.noteVisualSource] == nil,
      attributes[.noteHidden] == nil, attributes[.link] == nil
    else { return nil }
    return attributes
  }

  static func attributedForExport(_ note: NoteDocument, width: CGFloat) -> NSAttributedString {
    let storage = NSTextStorage(string: note.markdown)
    NoteWriteStyle().apply(to: storage, note: note, dark: false, width: width)
    let result = NSMutableAttributedString(attributedString: storage)
    var visuals: [(NSRange, NoteInlineVisual)] = []
    result.enumerateAttribute(.noteVisualSource, in: NSRange(location: 0, length: result.length)) {
      value, range, _ in
      if let visual = value as? NoteInlineVisual { visuals.append((range, visual)) }
    }
    for (range, visual) in visuals.reversed() {
      let attachment = NSTextAttachment()
      let image = visual.image.copy() as! NSImage
      image.size = visual.size
      attachment.attachmentCell = NSTextAttachmentCell(imageCell: image)
      result.replaceCharacters(in: range, with: NSAttributedString(attachment: attachment))
    }
    var hidden: [NSRange] = []
    result.enumerateAttribute(.noteHidden, in: NSRange(location: 0, length: result.length)) {
      value, range, _ in
      if value != nil { hidden.append(range) }
    }
    for range in hidden.reversed() { result.deleteCharacters(in: range) }
    return result
  }

  func resize(in storage: NSTextStorage, note: NoteDocument, dark: Bool, width: CGFloat) {
    lastStyledLength = 0
    var affected = Set<Int>()
    storage.enumerateAttribute(
      .noteWidthSensitive, in: NSRange(location: 0, length: storage.length)
    ) { value, range, _ in
      if value != nil { affected.insert(index.index(at: range.location)) }
    }
    for block in affected.sorted() {
      render(block..<(block + 1), to: storage, note: note, dark: dark, width: width)
    }
  }

  func select(
    _ selection: NSRange, in storage: NSTextStorage, note: NoteDocument, dark: Bool, width: CGFloat
  ) {
    guard selection != self.selection, !index.blocks.isEmpty else { return }
    let old = self.selection
    self.selection = selection
    var affected = Set<Int>()
    for range in [old, selection] where range.location != NSNotFound {
      let first = index.index(at: range.location)
      let last = index.index(at: NSMaxRange(range))
      // Large selections need no syntax expansion: copy still returns the exact source.
      if last - first < 8 { affected.formUnion(first...last) }
    }
    for block in affected.sorted() {
      render(block..<(block + 1), to: storage, note: note, dark: dark, width: width)
    }
  }

  private func render(
    _ changed: Range<Int>, to storage: NSTextStorage, note: NoteDocument, dark: Bool, width: CGFloat
  ) {
    lastStyledLength = 0
    let source = storage.string as NSString
    storage.beginEditing()
    for i in changed where index.blocks.indices.contains(i) {
      let block = index.blocks[i]
      let raw = source.substring(with: block.range)
      let text = NSMutableAttributedString(string: raw, attributes: Self.attributes(dark: dark))
      let localSelection =
        selection.location == NSNotFound
        ? selection
        : NSRange(
          location: max(0, selection.location - min(selection.location, block.range.location)),
          length: selection.length)
      let isSelected =
        selection.location != NSNotFound && selection.location >= block.range.location
        && selection.location < NSMaxRange(block.range)
      let caret = isSelected ? localSelection : NSRange(location: NSNotFound, length: 0)
      if let delimiter = block.math {
        styleMath(
          text, range: NSRange(location: 0, length: text.length - (raw.hasSuffix("\n") ? 1 : 0)),
          delimiter: delimiter, closed: block.closedMath, display: true, selection: caret,
          dark: dark, width: width)
      } else if block.fence != nil || block.afterFence != nil {
        let range = NSRange(location: 0, length: text.length)
        text.addAttributes(
          [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .backgroundColor: Self.ink(dark: dark).withAlphaComponent(0.055), .noteLiteral: true,
          ], range: range)
        if block.fence != block.afterFence {
          if caret.location == NSNotFound {
            let fenceRange = NSRange(
              location: 0, length: raw.trimmingCharacters(in: .newlines).utf16.count)
            syntax(text, range: fenceRange, reveal: false)
            let spacing = NSMutableParagraphStyle()
            spacing.minimumLineHeight = 3
            spacing.maximumLineHeight = 3
            text.addAttribute(.paragraphStyle, value: spacing, range: range)
          } else {
            text.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
          }
        }
      } else {
        markup(text, note: note, selection: caret, dark: dark, width: width)
      }
      for item in note.decorations {
        let overlap = NSIntersectionRange(item.range, block.range)
        guard overlap.length > 0 else { continue }
        let local = NSRange(
          location: overlap.location - block.range.location, length: overlap.length)
        text.enumerateAttribute(.noteHidden, in: local) { hidden, range, _ in
          guard hidden == nil else { return }
          text.addAttribute(
            item.highlight ? .backgroundColor : .foregroundColor,
            value: item.highlight
              ? item.color.background(dark: dark) : item.color.foreground(dark: dark), range: range)
        }
      }
      var customParagraphs = Set<Int>()
      var widthSensitive = false
      text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attrs, range, _ in
        if attrs[.noteVisual] != nil || attrs[.noteMathPreview] != nil {
          if let visual = (attrs[.noteVisual] ?? attrs[.noteMathPreview]) as? NoteInlineVisual,
            visual.kind == .math || visual.kind == .image
          {
            widthSensitive = true
          }
          customParagraphs.insert(
            (raw as NSString).lineRange(for: NSRange(location: range.location, length: 0)).location)
        }
      }
      if widthSensitive {
        text.addAttribute(.noteWidthSensitive, value: true, range: NSRange(location: 0, length: 1))
      }
      for start in customParagraphs {
        text.addAttribute(
          .noteCustomLayout, value: true, range: NSRange(location: start, length: 1))
      }
      text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attrs, range, _ in
        storage.setAttributes(
          attrs,
          range: NSRange(location: block.range.location + range.location, length: range.length))
      }
      lastStyledLength += block.range.length
    }
    storage.endEditing()
  }

  private func markup(
    _ text: NSMutableAttributedString, note: NoteDocument, selection: NSRange, dark: Bool,
    width: CGFloat
  ) {
    let raw = text.string
    let full = NSRange(location: 0, length: text.length)
    if let heading = Self.matches(#"^(#{1,6})[ \t]+"#, raw).first {
      let size = CGFloat([34, 27, 22, 19, 16, 14][heading.range(at: 1).length - 1])
      text.addAttribute(
        .font, value: NSFont(name: "Georgia", size: size) ?? NSFont.systemFont(ofSize: size),
        range: full)
      syntax(text, range: heading.range, reveal: selection.location <= NSMaxRange(heading.range))
    } else if let check = MarkdownChecklist.item(in: raw) {
      let range = NSRange(check.markerRange, in: raw)
      let visual = NoteInlineVisual(
        image: Self.checkbox(checked: check.isChecked, dark: dark), width: 18, kind: .checkbox)
      embed(visual, in: text, range: range)
      text.addAttribute(.noteCheckbox, value: true, range: range)
      if check.isChecked {
        let body = NSRange(location: NSMaxRange(range), length: text.length - NSMaxRange(range))
        text.addAttributes(
          [.foregroundColor: NSColor.secondaryLabelColor, .strikethroughStyle: 1], range: body)
      }
    } else if let bullet = Self.matches(#"^[ \t]*[-*+](?=[ \t])"#, raw).first {
      let marker = NSRange(location: NSMaxRange(bullet.range) - 1, length: 1)
      let visual = NoteInlineVisual(image: Self.symbol("•", dark: dark), width: 10, kind: .bullet)
      embed(visual, in: text, range: marker)
    } else if let quote = Self.matches(#"^[ \t]*>[ \t]?"#, raw).first {
      text.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: full)
      text.addAttribute(
        .font,
        value: NSFontManager.shared.convert(
          NSFont.systemFont(ofSize: 14), toHaveTrait: .italicFontMask), range: full)
      if selection.location <= NSMaxRange(quote.range) {
        syntax(text, range: quote.range, reveal: true)
      } else {
        embed(
          NoteInlineVisual(image: Self.symbol("▎", dark: dark), width: 10, kind: .bullet), in: text,
          range: quote.range)
      }
    }
    if ["---", "***", "___"].contains(raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
      if selection.location == NSNotFound {
        let image = NSImage(size: NSSize(width: max(80, width - 12), height: 16), flipped: false) {
          rect in
          Self.ink(dark: dark).withAlphaComponent(0.2).setFill()
          NSRect(x: 0, y: 8, width: rect.width, height: 1).fill()
          return true
        }
        embed(
          NoteInlineVisual(image: image, width: width, kind: .divider), in: text,
          range: NSRange(location: 0, length: raw.trimmingCharacters(in: .newlines).utf16.count))
      }
      return
    }
    // Inline code is literal, including dollars, escapes and Markdown within it.
    for match in Self.matches(#"(`+)([^`\n]+)\1"#, raw) {
      text.addAttributes(
        [
          .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
          .backgroundColor: Self.ink(dark: dark).withAlphaComponent(0.06), .noteLiteral: true,
        ], range: match.range)
      delimiters(text, match: match, content: match.range(at: 2), selection: selection)
    }
    // Match only paired inline delimiters. A dollar followed by whitespace is
    // prose (e.g. "costs $5 and $10"), and escaped dollars remain literal.
    for pattern in [
      #"(?<![\\$])\$(?![$\s])([^$\n]*?[^\s\\$])\$(?!\d|\$)"#,
      #"(?<!\\)\\\((.+?)\\\)"#, #"(?<![\\$])\$([^\s$])\$(?!\d|\$)"#,
    ] {
      for match in Self.matches(pattern, raw) where !literal(text, range: match.range) {
        let delimiter =
          (raw as NSString).substring(with: NSRange(location: match.range.location, length: 1))
            == "$" ? "$" : "\\("
        styleMath(
          text, range: match.range, delimiter: delimiter, closed: true, display: false,
          selection: selection, dark: dark, width: width)
      }
    }
    for match in Self.matches(#"\\([\\`*_{}\[\]()#+.!>~$-])"#, raw)
    where !literal(text, range: match.range) {
      text.addAttribute(.noteLiteral, value: true, range: match.range)
      syntax(
        text, range: NSRange(location: match.range.location, length: 1),
        reveal: editing(match.range, selection: selection))
    }
    for match in Self.matches(#"(!?)\[([^\]\n]*)\]\(([^\s)]+)\)"#, raw)
    where !literal(text, range: match.range) {
      let source = raw as NSString
      let path = source.substring(with: match.range(at: 3))
      if match.range(at: 1).length > 0 {
        if let asset = note.attachments.first(where: { $0.markdownPath == path }) {
          let image = images[asset.id]?.image ?? NSImage(data: asset.data)
          if let image {
            images[asset.id] = (asset.data, image)
            let maxWidth = min(
              width - 12, image.size.width * min(1, 320 / max(1, image.size.height)))
            let visual = NoteInlineVisual(image: image, width: maxWidth, kind: .image)
            if !editing(match.range, selection: selection) {
              embed(visual, in: text, range: match.range)
            }
          }
        }
        text.addAttribute(.noteLiteral, value: true, range: match.range)
      } else if let url = URL(string: path), NoteRendering.allowed(url) {
        text.addAttributes(
          [.link: url, .foregroundColor: NoteColor.blue.foreground(dark: dark)],
          range: match.range(at: 2))
        delimiters(text, match: match, content: match.range(at: 2), selection: selection)
        text.addAttribute(.noteLiteral, value: true, range: match.range(at: 3))
      }
    }
    for (pattern, kind) in [
      (#"\*\*\*([^\n]+?)\*\*\*"#, "both"), (#"\*\*([^\n]+?)\*\*"#, "bold"),
      (#"__([^\n]+?)__"#, "bold"), (#"~~([^\n]+?)~~"#, "strike"),
      (#"(?<!\*)\*([^*\n]+)\*(?!\*)"#, "italic"),
      (#"(?<![\w_])_([^_\n]+)_(?![\w_])"#, "italic"),
    ] {
      for match in Self.matches(pattern, raw) where !literal(text, range: match.range) {
        let range = match.range(at: 1)
        if kind == "strike" {
          text.addAttribute(.strikethroughStyle, value: 1, range: range)
        } else {
          text.enumerateAttribute(.font, in: range) { value, run, _ in
            let font = value as? NSFont ?? NSFont.systemFont(ofSize: 14)
            text.addAttribute(
              .font,
              value: NSFontManager.shared.convert(
                font,
                toHaveTrait: kind == "both"
                  ? [.boldFontMask, .italicFontMask]
                  : kind == "bold" ? .boldFontMask : .italicFontMask), range: run)
          }
        }
        delimiters(text, match: match, content: range, selection: selection)
        if kind == "both" { text.addAttribute(.noteLiteral, value: true, range: match.range) }
      }
    }
  }

  private func styleMath(
    _ text: NSMutableAttributedString, range: NSRange, delimiter: String,
    closed: Bool, display: Bool, selection: NSRange, dark: Bool, width: CGFloat
  ) {
    guard range.length >= delimiter.utf16.count else { return }
    let raw = (text.string as NSString).substring(with: range).trimmingCharacters(
      in: .whitespacesAndNewlines)
    var latex = String(raw.dropFirst(delimiter.count))
    if closed { latex = String(latex.dropLast(delimiter.count)) }
    let result = NoteMath.render(latex, display: display, dark: dark)
    text.addAttributes(
      [.noteLiteral: true, .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)],
      range: range)
    let active = !closed || editing(range, selection: selection)
    if let image = result.image {
      let visual = NoteInlineVisual(image: image, width: width - 12, kind: .math)
      if active {
        text.addAttribute(
          .foregroundColor, value: NoteColor.purple.foreground(dark: dark), range: range)
        text.addAttribute(
          .noteMathPreview, value: visual,
          range: NSRange(location: NSMaxRange(range) - 1, length: 1))
      } else {
        embed(visual, in: text, range: range)
      }
    } else if closed {
      text.addAttribute(.toolTip, value: result.error ?? "Incomplete equation", range: range)
      text.addAttribute(
        .foregroundColor, value: NoteColor.purple.foreground(dark: dark), range: range)
    }
  }

  private func embed(_ visual: NoteInlineVisual, in text: NSMutableAttributedString, range: NSRange)
  {
    guard range.length > 0 else { return }
    syntax(text, range: range, reveal: false)
    text.addAttribute(.noteVisualSource, value: visual, range: range)
    let anchor = NSRange(location: range.location, length: 1)
    let font = NSFont.systemFont(ofSize: max(14, visual.size.height * 0.84))
    let character = (text.string as NSString).substring(with: anchor) as NSString
    let advance = character.size(withAttributes: [.font: font]).width
    text.addAttributes(
      [.noteVisual: visual, .font: font, .kern: visual.size.width - advance + 2], range: anchor)
    if (text.string as NSString).substring(with: range).contains("\n") {
      let firstLine = (text.string as NSString).lineRange(for: anchor)
      let tail = NSRange(
        location: NSMaxRange(firstLine), length: max(0, NSMaxRange(range) - NSMaxRange(firstLine)))
      if tail.length > 0 {
        let collapsed = NSMutableParagraphStyle()
        collapsed.minimumLineHeight = 0.1
        collapsed.maximumLineHeight = 0.1
        text.addAttribute(.paragraphStyle, value: collapsed, range: tail)
      }
    }
  }
  private func syntax(_ text: NSMutableAttributedString, range: NSRange, reveal: Bool) {
    guard range.length > 0 else { return }
    if reveal {
      text.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
    } else {
      text.addAttributes(
        [
          .font: NSFont.systemFont(ofSize: 0.1), .foregroundColor: NSColor.clear, .noteHidden: true,
          .kern: 0,
        ], range: range)
    }
  }
  private func delimiters(
    _ text: NSMutableAttributedString, match: NSTextCheckingResult, content: NSRange,
    selection: NSRange
  ) {
    let reveal = editing(match.range, selection: selection)
    syntax(
      text,
      range: NSRange(
        location: match.range.location, length: content.location - match.range.location),
      reveal: reveal)
    syntax(
      text,
      range: NSRange(
        location: NSMaxRange(content), length: NSMaxRange(match.range) - NSMaxRange(content)),
      reveal: reveal)
  }
  private func editing(_ range: NSRange, selection: NSRange) -> Bool {
    selection.location != NSNotFound && selection.length < 1024
      && selection.location > range.location && selection.location < NSMaxRange(range)
  }
  private func literal(_ text: NSAttributedString, range: NSRange) -> Bool {
    var found = false
    text.enumerateAttribute(.noteLiteral, in: range) { value, _, stop in
      if value != nil {
        found = true
        stop.pointee = true
      }
    }
    return found
  }
  private static func matches(_ pattern: String, _ text: String) -> [NSTextCheckingResult] {
    let regex: NSRegularExpression
    if let cached = expressions[pattern] {
      regex = cached
    } else {
      guard let compiled = try? NSRegularExpression(pattern: pattern) else { return [] }
      expressions[pattern] = compiled
      regex = compiled
    }
    return regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
  }
  private static func symbol(_ symbol: String, dark: Bool) -> NSImage {
    NSImage(size: NSSize(width: 10, height: 17), flipped: false) { _ in
      (symbol as NSString).draw(
        at: .zero,
        withAttributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: ink(dark: dark)])
      return true
    }
  }
  private static func checkbox(checked: Bool, dark: Bool) -> NSImage {
    NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
      let box = NSBezierPath(
        roundedRect: NSRect(x: 1, y: 1, width: 15, height: 15), xRadius: 3, yRadius: 3)
      (checked ? NoteColor.green.foreground(dark: dark) : ink(dark: dark).withAlphaComponent(0.45))
        .setStroke()
      box.lineWidth = 1.3
      box.stroke()
      if checked {
        NoteColor.green.background(dark: dark).setFill()
        box.fill()
        let check = NSBezierPath()
        check.move(to: CGPoint(x: 4, y: 8))
        check.line(to: CGPoint(x: 7, y: 5))
        check.line(to: CGPoint(x: 13, y: 12))
        check.lineWidth = 1.6
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        check.stroke()
      }
      return true
    }
  }
}
