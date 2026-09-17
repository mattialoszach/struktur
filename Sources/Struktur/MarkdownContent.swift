import AppKit
import SwiftUI

struct MarkdownContent: View {
  @Binding var text: String
  @EnvironmentObject private var store: WorkspaceStore
  @State private var reference: WorkspaceReference?
  @State private var referenceNotFound = false
  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { index, raw in
        let line = raw.trimmingCharacters(in: .whitespaces)
        if let item = MarkdownChecklist.item(in: raw) {
          let checked = item.isChecked
          HStack(alignment: .top, spacing: 7) {
            Button {
              text = MarkdownChecklist.toggling(line: index, in: text)
            } label: {
              Image(systemName: checked ? "checkmark.square.fill" : "square")
                .foregroundStyle(checked ? AccentToken.mint.color : StrukturTheme.muted)
                .frame(width: 22, height: 22).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(
              "\(checked ? "Uncheck" : "Check") \(item.title.isEmpty ? "checklist item" : item.title)")
              .accessibilityValue(checked ? "Checked" : "Unchecked")
            Text(inline(item.title)).strikethrough(checked).foregroundStyle(
              checked ? StrukturTheme.muted : StrukturTheme.ink).padding(.top, 3)
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
      .environment(\.openURL, OpenURLAction { url in
        guard url.scheme?.lowercased() == "struktur" else { return .systemAction }
        if let target = WorkspaceReference(url: url), store.contains(target) {
          reference = target
        } else {
          referenceNotFound = true
        }
        return .handled
      })
      .sheet(item: $reference) { target in
        switch target.kind {
        case .task:
          if let task = store.tasks.first(where: { $0.id == target.id }) {
            TaskEditorSheet(task: task)
          }
        case .event:
          if let entry = store.resolveEntry(target.id) { EventEditorSheet(entry: entry) }
        case .goal:
          if let goal = store.goals.first(where: { $0.id == target.id }) {
            GoalEditorSheet(goal: goal)
          }
        case .space:
          if let project = store.project(target.id) { ProjectEditorSheet(project: project) }
        }
      }
      .alert("Reference not found", isPresented: $referenceNotFound) {
        Button("OK", role: .cancel) {}
      } message: {
        Text("This link is invalid, was deleted, or belongs to another workspace. Use Copy reference on an existing item to get its link.")
      }
  }
  private func inline(_ value: String) -> AttributedString {
    (try? AttributedString(
      markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
      ?? AttributedString(value)
  }
}

enum MarkdownChecklist {
  struct Item {
    let isChecked: Bool
    let title: String
    let markerRange: Range<String.Index>
  }

  static func item(in raw: String) -> Item? {
    let body = raw.drop(while: { $0.isWhitespace })
    for marker in ["- [ ]", "- []", "- [x]", "- [X]"] where body.hasPrefix(marker) {
      let end = body.index(body.startIndex, offsetBy: marker.count)
      let remainder = body[end...]
      guard remainder.isEmpty || remainder.first?.isWhitespace == true else { continue }
      return Item(isChecked: marker.lowercased() == "- [x]",
        title: remainder.trimmingCharacters(in: .whitespaces),
        markerRange: body.startIndex..<end)
    }
    return nil
  }

  static func toggling(line index: Int, in text: String) -> String {
    var lines = text.components(separatedBy: "\n")
    guard lines.indices.contains(index), let item = item(in: lines[index]) else { return text }
    lines[index].replaceSubrange(item.markerRange, with: item.isChecked ? "- [ ]" : "- [x]")
    return lines.joined(separator: "\n")
  }
}

struct WorkspaceReference: Identifiable, Equatable {
  enum Kind: String { case task, event, goal, space }
  let kind: Kind
  let id: UUID

  init?(url: URL) {
    guard url.scheme?.lowercased() == "struktur", let host = url.host,
      let kind = Kind(rawValue: host.lowercased()),
      url.pathComponents.count == 2, let id = UUID(uuidString: url.lastPathComponent),
      url.user == nil, url.password == nil, url.port == nil,
      url.query == nil, url.fragment == nil
    else { return nil }
    self.kind = kind
    self.id = id
  }
}

extension WorkspaceStore {
  func contains(_ reference: WorkspaceReference) -> Bool {
    switch reference.kind {
    case .task: tasks.contains { $0.id == reference.id }
    case .event: resolveEntry(reference.id) != nil
    case .goal: goals.contains { $0.id == reference.id }
    case .space: project(reference.id) != nil
    }
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
