import AppKit
import SwiftUI

struct MarkdownContent: View {
  @Binding var text: String
  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { index, raw in
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
          let checked = !line.hasPrefix("- [ ] ")
          HStack(alignment: .top, spacing: 7) {
            Button {
              text = MarkdownChecklist.toggling(line: index, in: text)
            } label: {
              Image(systemName: checked ? "checkmark.square.fill" : "square")
                .foregroundStyle(checked ? AccentToken.mint.color : StrukturTheme.muted)
            }.buttonStyle(.plain).accessibilityLabel(
              "\(checked ? "Uncheck" : "Check") \(String(line.dropFirst(6)))")
            Text(inline(String(line.dropFirst(6)))).strikethrough(checked).foregroundStyle(
              checked ? StrukturTheme.muted : StrukturTheme.ink)
          }
        } else if line.hasPrefix("# ") {
          Text(inline(String(line.dropFirst(2)))).font(.strukturSerif(23)).padding(.top, 5)
        } else if line.hasPrefix("## ") {
          Text(inline(String(line.dropFirst(3)))).font(.strukturSerif(19)).padding(.top, 4)
        } else if line.hasPrefix("### ") {
          Text(inline(String(line.dropFirst(4)))).font(.system(size: 14, weight: .semibold))
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
          HStack(alignment: .top, spacing: 7) {
            Text("•").foregroundStyle(StrukturTheme.muted)
            Text(inline(String(line.dropFirst(2))))
          }
        } else if line.hasPrefix("> ") {
          HStack {
            Rectangle().fill(AccentToken.lilac.color).frame(width: 2)
            Text(inline(String(line.dropFirst(2)))).italic()
          }.fixedSize(horizontal: false, vertical: true)
        } else if line.isEmpty {
          Color.clear.frame(height: 3)
        } else {
          Text(inline(line)).textSelection(.enabled)
        }
      }
    }.font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .topLeading)
      .tint(StrukturTheme.ink)
  }
  private func inline(_ value: String) -> AttributedString {
    (try? AttributedString(
      markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
      ?? AttributedString(value)
  }
}

enum MarkdownChecklist {
  static func toggling(line index: Int, in text: String) -> String {
    var lines = text.components(separatedBy: "\n")
    guard lines.indices.contains(index) else { return text }
    if let range = lines[index].range(of: "- [ ] ") {
      lines[index].replaceSubrange(range, with: "- [x] ")
    } else if let range = lines[index].range(of: "- [x] ", options: .caseInsensitive) {
      lines[index].replaceSubrange(range, with: "- [ ] ")
    }
    return lines.joined(separator: "\n")
  }
}

struct ItemReferenceRow: View {
  let kind: String
  let id: UUID
  @State private var copied = false
  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "link").font(.caption)
      Text("UID · \(id.uuidString.prefix(8).lowercased())").font(
        .system(size: 10, design: .monospaced)
      ).textSelection(.enabled)
      Spacer()
      Button(copied ? "Copied link" : "Copy reference") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("struktur://\(kind)/\(id.uuidString)", forType: .string)
        copied = true
      }.buttonStyle(StrukturButtonStyle(compact: true))
    }.foregroundStyle(StrukturTheme.muted)
  }
}
