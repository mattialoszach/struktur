import AppKit

/// Write is ordinary native text. Markdown parsing and document typography belong
/// to Preview; changing paragraph fonts/layout while handling a key delays paint.
@MainActor final class NoteWriteStyle {
  private(set) var lastStyledLength = 0

  static func attributes(dark: Bool) -> [NSAttributedString.Key: Any] {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 4
    return [
      .font: NSFont.systemFont(ofSize: 14),
      .foregroundColor: dark ? NSColor.white : NSColor.labelColor,
      .paragraphStyle: paragraph,
    ]
  }

  func apply(
    to storage: NSTextStorage, note: NoteDocument, dark: Bool,
    editedRange: NSRange? = nil
  ) {
    let range = editedRange ?? NSRange(location: 0, length: storage.length)
    lastStyledLength = range.length
    guard range.length > 0 else { return }
    storage.beginEditing()
    storage.setAttributes(Self.attributes(dark: dark), range: range)
    for item in note.decorations {
      let overlap = NSIntersectionRange(item.range, range)
      if overlap.length > 0 {
        storage.addAttribute(
          item.highlight ? .backgroundColor : .foregroundColor,
          value: item.highlight
            ? item.color.background(dark: dark) : item.color.foreground(dark: dark),
          range: overlap)
      }
    }
    storage.endEditing()
  }
}
