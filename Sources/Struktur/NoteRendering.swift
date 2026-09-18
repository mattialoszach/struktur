import AppKit
import SwiftUI

struct NoteCodeFence: Equatable {
  var marker: Character
  var length: Int

  static func after(_ line: String, starting current: Self?) -> Self? {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let marker = trimmed.first, marker == "`" || marker == "~" else { return current }
    let run = trimmed.prefix { $0 == marker }.count
    guard run >= 3 else { return current }
    if let current {
      return marker == current.marker && run >= current.length
        && trimmed.dropFirst(run).trimmingCharacters(in: .whitespaces).isEmpty ? nil : current
    }
    return Self(marker: marker, length: run)
  }
}

extension NoteColor {
  func foreground(dark: Bool) -> NSColor {
    let hex: UInt32 =
      switch self {
      case .rose: dark ? 0xF4A5B8 : 0xA82F51
      case .gold: dark ? 0xEBD07E : 0x81600D
      case .green: dark ? 0xA1D4AE : 0x296742
      case .blue: dark ? 0xA5C6EF : 0x2C609C
      case .purple: dark ? 0xC7B4EC : 0x7350A4
      }
    return NSColor(
      srgbRed: CGFloat((hex >> 16) & 255) / 255,
      green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
  }
  func background(dark: Bool) -> NSColor {
    foreground(dark: dark).withAlphaComponent(dark ? 0.25 : 0.16)
  }
}

/// A deliberately small, native Markdown renderer. Source remains the canonical document.
@MainActor enum NoteRendering {
  static func attributed(
    _ note: NoteDocument, preview: Bool, dark: Bool,
    width: CGFloat = 460, startingFence: NoteCodeFence? = nil
  ) -> NSAttributedString {
    let ink =
      dark
      ? NSColor(srgbRed: 0.91, green: 0.93, blue: 0.89, alpha: 1)
      : NSColor(srgbRed: 0.17, green: 0.20, blue: 0.18, alpha: 1)
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 5
    paragraph.paragraphSpacing = 7
    let base: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 14),
      .foregroundColor: ink, .paragraphStyle: paragraph,
    ]
    let result = NSMutableAttributedString(string: "")
    var offset = 0
    var fence = startingFence
    let lines = note.markdown.components(separatedBy: "\n")
    for (index, raw) in lines.enumerated() {
      let line = NSMutableAttributedString(string: raw, attributes: base)
      let range = NSRange(location: 0, length: line.length)
      for item in note.decorations {
        let overlap = NSIntersectionRange(
          item.range, NSRange(location: offset, length: line.length))
        if overlap.length > 0 {
          line.addAttribute(
            item.highlight ? .backgroundColor : .foregroundColor,
            value: item.highlight
              ? item.color.background(dark: dark) : item.color.foreground(dark: dark),
            range: NSRange(location: overlap.location - offset, length: overlap.length))
        }
      }
      let trimmed = raw.trimmingCharacters(in: .whitespaces)
      let nextFence = NoteCodeFence.after(raw, starting: fence)
      if nextFence != fence {
        fence = nextFence
        line.addAttributes(
          [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
          ], range: range)
        if preview {
          offset += raw.utf16.count + 1
          continue
        }
      } else if fence != nil {
        line.addAttributes(
          [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .backgroundColor: ink.withAlphaComponent(0.06),
          ], range: range)
      } else {
        if let heading = match(#"^(#{1,6})\s+"#, in: raw) {
          let level = heading.range(at: 1).length
          line.addAttribute(
            .font,
            value: NSFont(name: "Georgia", size: CGFloat(max(15, 29 - level * 3)))
              ?? NSFont.systemFont(ofSize: 23), range: range)
          if preview {
            line.deleteCharacters(in: heading.range)
          } else {
            syntax(line, range: heading.range)
          }
        } else if preview, let item = MarkdownChecklist.item(in: raw) {
          let marker = NSRange(item.markerRange, in: raw)
          line.replaceCharacters(
            in: marker,
            with: NSAttributedString(
              string: item.isChecked ? "☑" : "☐",
              attributes: [
                .font: NSFont.systemFont(ofSize: 17), .foregroundColor: ink,
                .link: URL(string: "struktur-check://line/\(index)")!,
              ]))
        } else if preview, let bullet = match(#"^\s*[-*+]\s+"#, in: raw) {
          line.replaceCharacters(in: bullet.range, with: "• ")
        } else if let quote = match(#"^\s*>\s?"#, in: raw) {
          line.addAttribute(
            .font,
            value: NSFontManager.shared.convert(
              NSFont.systemFont(ofSize: 14), toHaveTrait: .italicFontMask), range: range)
          if preview {
            line.replaceCharacters(in: quote.range, with: "▎ ")
          } else {
            syntax(line, range: quote.range)
          }
        } else if preview, ["---", "***", "___"].contains(trimmed) {
          line.replaceCharacters(in: range, with: "────────────────────")
        }
        if !preview, let marker = match(#"^\s*(?:[-*+] \[(?: |x|X)?\] |[-*+] |\d+\. )"#, in: raw) {
          syntax(line, range: marker.range)
        }
        inline(line, note: note, preview: preview, dark: dark, width: width)
      }
      if !preview {
        for item in note.decorations {
          let overlap = NSIntersectionRange(
            item.range, NSRange(location: offset, length: line.length))
          if overlap.length > 0 {
            line.addAttribute(
              item.highlight ? .backgroundColor : .foregroundColor,
              value: item.highlight
                ? item.color.background(dark: dark) : item.color.foreground(dark: dark),
              range: NSRange(location: overlap.location - offset, length: overlap.length))
          }
        }
      }
      result.append(line)
      if index < lines.count - 1 {
        result.append(NSAttributedString(string: "\n", attributes: base))
      }
      offset += raw.utf16.count + 1
    }
    return result
  }

  private static let literal = NSAttributedString.Key("StrukturLiteral")
  private static var expressions: [String: NSRegularExpression] = [:]
  private static func expression(_ pattern: String) -> NSRegularExpression? {
    if let cached = expressions[pattern] { return cached }
    let regex = try? NSRegularExpression(pattern: pattern)
    expressions[pattern] = regex
    return regex
  }
  private static func syntax(_ text: NSMutableAttributedString, range: NSRange) {
    text.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
  }
  private static func inline(
    _ text: NSMutableAttributedString, note: NoteDocument,
    preview: Bool, dark: Bool, width: CGFloat
  ) {
    transform(#"\\([\\`*_{}\[\]()#+.!>~-])"#, in: text) { match in
      if preview {
        let content = NSMutableAttributedString(
          attributedString: text.attributedSubstring(from: match.range(at: 1)))
        content.addAttribute(
          literal, value: true, range: NSRange(location: 0, length: content.length))
        text.replaceCharacters(in: match.range, with: content)
      } else {
        text.addAttribute(literal, value: true, range: match.range)
      }
    }
    // Code is protected before parsing links/emphasis; HTML is always literal text.
    transform(#"`([^`\n]+)`"#, in: text) { match in
      let content = NSMutableAttributedString(
        attributedString: text.attributedSubstring(from: match.range(at: 1)))
      content.addAttributes(
        [
          .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
          literal: true,
        ], range: NSRange(location: 0, length: content.length))
      if preview {
        text.replaceCharacters(in: match.range, with: content)
      } else {
        text.addAttribute(literal, value: true, range: match.range)
        text.addAttributes(
          [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .backgroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.10),
          ], range: match.range)
        syntax(text, range: NSRange(location: match.range.location, length: 1))
        syntax(text, range: NSRange(location: NSMaxRange(match.range) - 1, length: 1))
      }
    }
    transform(#"(!?)\[([^\]\n]*)\]\(([^\s)]+)\)"#, in: text) { match in
      let source = text.string as NSString
      let path = source.substring(with: match.range(at: 3))
      let label = text.attributedSubstring(from: match.range(at: 2))
      if source.substring(with: match.range(at: 1)) == "!" {
        if preview, let asset = note.attachments.first(where: { $0.markdownPath == path }),
          let image = NSImage(data: asset.data), image.size.width > 0, image.size.height > 0
        {
          let scale = min(1, min(max(80, width - 12) / image.size.width, 380 / image.size.height))
          let attachment = NSTextAttachment()
          image.size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
          attachment.attachmentCell = NSTextAttachmentCell(imageCell: image)
          text.replaceCharacters(in: match.range, with: NSAttributedString(attachment: attachment))
        } else if preview {
          text.replaceCharacters(in: match.range, with: "[Image: \(label.string)]")
        }
      } else if let url = URL(string: path), allowed(url) {
        let replacement = NSMutableAttributedString(attributedString: label)
        replacement.addAttribute(
          .link, value: url, range: NSRange(location: 0, length: replacement.length))
        if preview {
          text.replaceCharacters(in: match.range, with: replacement)
        } else {
          text.addAttribute(
            .foregroundColor, value: NoteColor.blue.foreground(dark: dark), range: match.range)
          text.addAttribute(literal, value: true, range: match.range(at: 3))
        }
      }
    }
    for (pattern, kind) in [
      (#"\*\*\*(.+?)\*\*\*"#, "boldItalic"),
      (#"\*\*(.+?)\*\*"#, "bold"), (#"__(.+?)__"#, "bold"),
      (#"~~(.+?)~~"#, "strike"), (#"(?<!\*)\*([^*\n]+)\*(?!\*)"#, "italic"),
      (#"(?<![\w_])_([^_\n]+)_(?![\w_])"#, "italic"),
    ] {
      transform(pattern, in: text) { match in
        let content = NSMutableAttributedString(
          attributedString: text.attributedSubstring(from: match.range(at: 1)))
        let range = NSRange(location: 0, length: content.length)
        if kind == "strike" {
          content.addAttribute(.strikethroughStyle, value: 1, range: range)
        } else {
          content.enumerateAttribute(.font, in: range) { value, range, _ in
            let font = value as? NSFont ?? NSFont.systemFont(ofSize: 14)
            content.addAttribute(
              .font,
              value: NSFontManager.shared.convert(
                font,
                toHaveTrait: kind == "boldItalic"
                  ? [.boldFontMask, .italicFontMask]
                  : kind == "bold" ? .boldFontMask : .italicFontMask), range: range)
          }
        }
        if preview {
          text.replaceCharacters(in: match.range, with: content)
        } else {
          content.enumerateAttributes(in: range) { attributes, localRange, _ in
            text.addAttributes(
              attributes,
              range: NSRange(
                location: match.range(at: 1).location + localRange.location,
                length: localRange.length))
          }
          syntax(
            text,
            range: NSRange(
              location: match.range.location,
              length: match.range(at: 1).location - match.range.location))
          syntax(
            text,
            range: NSRange(
              location: NSMaxRange(match.range(at: 1)),
              length: NSMaxRange(match.range) - NSMaxRange(match.range(at: 1))))
        }
      }
    }
  }

  private static func transform(
    _ pattern: String, in text: NSMutableAttributedString,
    action: (NSTextCheckingResult) -> Void
  ) {
    guard let regex = expression(pattern) else { return }
    for match in regex.matches(in: text.string, range: NSRange(location: 0, length: text.length))
      .reversed()
    {
      guard text.attribute(literal, at: match.range.location, effectiveRange: nil) == nil else {
        continue
      }
      action(match)
    }
  }
  private static func match(_ pattern: String, in text: String) -> NSTextCheckingResult? {
    expression(pattern)?.firstMatch(
      in: text, range: NSRange(location: 0, length: text.utf16.count))
  }
  static func allowed(_ url: URL) -> Bool {
    ["http", "https", "mailto", "struktur"].contains(url.scheme?.lowercased() ?? "")
  }
}
