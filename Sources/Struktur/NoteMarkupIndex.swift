import Foundation

/// A paragraph index with fence state checkpoints. Ordinary edits parse one
/// paragraph (and its neighbor), not the preceding or following document.
struct NoteMarkupIndex {
  struct Block {
    var range: NSRange
    var fence: NoteCodeFence?
    var afterFence: NoteCodeFence?
    var math: String?
    var closedMath = false
  }
  private(set) var blocks: [Block] = []
  private var length = 0
  private(set) var lastParsedLength = 0

  func index(at offset: Int) -> Int {
    var low = 0
    var high = blocks.count
    while low < high {
      let middle = (low + high) / 2
      if blocks[middle].range.location <= offset { low = middle + 1 } else { high = middle }
    }
    return max(0, low - 1)
  }

  mutating func update(_ source: NSString, editedRange: NSRange?) -> Range<Int> {
    let delta = source.length - length
    let old = blocks
    let startIndex = editedRange.map { max(0, index(at: $0.location) - 1) } ?? 0
    let start = old.indices.contains(startIndex) ? old[startIndex].range.location : 0
    var fence = old.indices.contains(startIndex) ? old[startIndex].fence : nil
    var cursor = min(start, source.length)
    var rebuilt: [Block] = []
    var suffix = old.count
    lastParsedLength = 0
    while cursor < source.length {
      // Once both offsets and parser state converge, reuse the untouched suffix.
      if let editedRange, cursor > NSMaxRange(editedRange), !rebuilt.isEmpty {
        let candidate = index(at: cursor - delta)
        if old.indices.contains(candidate), old[candidate].range.location == cursor - delta,
          old[candidate].fence == fence
        {
          suffix = candidate
          break
        }
      }
      let line = source.lineRange(for: NSRange(location: cursor, length: 0))
      let raw = source.substring(with: line)
      var block = Block(range: line, fence: fence, afterFence: fence)
      let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      if fence == nil, trimmed.hasPrefix("$$") || trimmed.hasPrefix("\\[") {
        let delimiter = trimmed.hasPrefix("$$") ? "$$" : "\\["
        let closing = delimiter == "$$" ? "$$" : "\\]"
        block.math = delimiter
        let remainder = String(trimmed.dropFirst(2))
        block.closedMath = remainder.hasSuffix(closing)
        var end = NSMaxRange(line)
        while !block.closedMath, end < source.length {
          let next = source.lineRange(for: NSRange(location: end, length: 0))
          block.closedMath = source.substring(with: next)
            .trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(closing)
          end = NSMaxRange(next)
        }
        block.range.length = end - cursor
      } else {
        block.afterFence = NoteCodeFence.after(raw, starting: fence)
        fence = block.afterFence
      }
      rebuilt.append(block)
      lastParsedLength += block.range.length
      cursor = NSMaxRange(block.range)
    }
    blocks = Array(old.prefix(startIndex)) + rebuilt
    if suffix < old.count {
      blocks += old[suffix...].map { block in
        var shifted = block
        shifted.range.location += delta
        return shifted
      }
    }
    length = source.length
    return startIndex..<(startIndex + rebuilt.count)
  }
}
