import AppKit

/// Keeps TextKit's character storage, selection and undo history intact. A normal
/// keystroke restyles one paragraph; fence edits propagate only as far as needed.
@MainActor final class NoteLiveStyler {
  private struct Block {
    var range: NSRange
    var before: NoteCodeFence?
    var after: NoteCodeFence?
  }
  private var source: NSString = ""
  private var blocks: [Block] = []
  private(set) var lastStyledLength = 0

  func apply(
    to storage: NSTextStorage, note: NoteDocument, dark: Bool,
    editedRange: NSRange? = nil, changeInLength: Int = 0
  ) {
    let current = storage.string as NSString
    var start = 0
    var boundary = current.length
    var prefix: [Block] = []
    var suffix: [Block] = []
    if let editedRange, !blocks.isEmpty,
      source.length + changeInLength == current.length,
      editedRange.length >= changeInLength,
      editedRange.location <= source.length
    {
      let oldEdit = NSRange(
        location: editedRange.location,
        length: editedRange.length - changeInLength)
      if NSMaxRange(oldEdit) <= source.length {
        let affected = source.lineRange(for: oldEdit)
        start = affected.location
        boundary = NSMaxRange(affected) + changeInLength
        prefix = blocks.filter { NSMaxRange($0.range) <= start }
        suffix = blocks.filter {
          $0.range.location >= NSMaxRange(affected) && $0.range.location >= start
        }
        .map { block in
          var shifted = block
          shifted.range.location += changeInLength
          return shifted
        }
      }
    }
    if start == 0 && prefix.isEmpty && suffix.isEmpty {
      let rendered = NoteRendering.attributed(note, preview: false, dark: dark)
      storage.beginEditing()
      rendered.enumerateAttributes(in: NSRange(location: 0, length: rendered.length)) {
        attributes, range, _ in
        storage.setAttributes(attributes, range: range)
      }
      storage.endEditing()
      blocks = []
      var cursor = 0
      var fence: NoteCodeFence?
      while cursor < current.length {
        let range = current.lineRange(for: NSRange(location: cursor, length: 0))
        let after = NoteCodeFence.after(current.substring(with: range), starting: fence)
        blocks.append(Block(range: range, before: fence, after: after))
        fence = after
        cursor = NSMaxRange(range)
      }
      source = current.copy() as! NSString
      lastStyledLength = current.length
      return
    }
    var updated = prefix
    var fence = prefix.last?.after
    var cursor = start
    var suffixIndex = 0
    lastStyledLength = 0
    storage.beginEditing()
    while cursor < current.length {
      while suffixIndex < suffix.count && suffix[suffixIndex].range.location < cursor {
        suffixIndex += 1
      }
      if cursor >= boundary, suffixIndex < suffix.count,
        suffix[suffixIndex].range.location == cursor, suffix[suffixIndex].before == fence
      {
        updated.append(contentsOf: suffix[suffixIndex...])
        break
      }
      let range = current.lineRange(for: NSRange(location: cursor, length: 0))
      let raw = current.substring(with: range)
      var paragraph = NoteDocument(markdown: raw)
      paragraph.decorations = note.decorations.compactMap { decoration in
        let overlap = NSIntersectionRange(decoration.range, range)
        guard overlap.length > 0 else { return nil }
        var local = decoration
        local.location = overlap.location - range.location
        local.length = overlap.length
        return local
      }
      let rendered = NoteRendering.attributed(
        paragraph, preview: false, dark: dark, startingFence: fence)
      rendered.enumerateAttributes(in: NSRange(location: 0, length: rendered.length)) {
        attributes, local, _ in
        storage.setAttributes(
          attributes,
          range: NSRange(location: range.location + local.location, length: local.length))
      }
      let after = NoteCodeFence.after(raw, starting: fence)
      updated.append(Block(range: range, before: fence, after: after))
      fence = after
      cursor = NSMaxRange(range)
      lastStyledLength += range.length
    }
    storage.endEditing()
    blocks = updated
    // NSTextStorage can vend its mutable backing NSString through `string`.
    // Keep an actual snapshot so the next edit cannot mutate our old ranges.
    source = current.copy() as! NSString
  }
}
