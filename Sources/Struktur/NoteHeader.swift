import AppKit
import SwiftUI

struct NoteHeader: View {
  @EnvironmentObject private var store: WorkspaceStore
  let note: NoteDocument
  let controller: NoteEditorController
  var exportMarkdown: (NoteDocument) -> Void
  var exportPDF: (NoteDocument) -> Void
  var confirmDeletion: () -> Void
  @State private var actionsHovered = false
  private var noteID: UUID { note.id }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 10) {
        SuitIcon(symbol: .diamond, size: 14)
        Text(store.noteFolderPath(note.folderID)).font(.system(size: 11)).foregroundStyle(
          StrukturTheme.muted
        )
        .lineLimit(2)
        Spacer()
        Menu {
          Button(note.isPinned ? "Unpin note" : "Pin note", systemImage: "pin") {
            store.editNote(noteID) { $0.isPinned.toggle() }
          }
          Menu("Move to folder") {
            Button("Unfiled") {
              store.editNote(noteID) { $0.folderID = nil }
              store.revealNote(noteID)
            }
            ForEach(
              store.noteFolders.sorted { store.noteFolderPath($0.id) < store.noteFolderPath($1.id) }
            ) { folder in
              Button(store.noteFolderPath(folder.id)) {
                store.editNote(noteID) { $0.folderID = folder.id }
                store.revealNote(noteID)
              }
            }
          }
          Button("Copy note reference", systemImage: "link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("struktur://note/\(noteID)", forType: .string)
          }
          Divider()
          Button("Export Markdown…", systemImage: "doc.plaintext") { exportMarkdown(note) }
          Button("Export PDF…", systemImage: "doc.richtext") { exportPDF(note) }
          Divider()
          if note.deletedAt == nil {
            Button("Move to Recently deleted", systemImage: "trash", role: .destructive) {
              store.editNote(noteID) { $0.deletedAt = Date() }
            }
          } else {
            Button("Restore note") { store.editNote(noteID) { $0.deletedAt = nil } }
            Button("Delete permanently…", role: .destructive) { confirmDeletion() }
          }
        } label: {
          Image(systemName: "ellipsis").frame(width: 24, height: 24)
            .background(
              actionsHovered ? StrukturTheme.hairline : .clear,
              in: RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Note actions")
        .onHover { actionsHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: actionsHovered)
      }
      NoteTitleField(
        note: note,
        currentTitle: { store.note(noteID)?.title },
        onTitle: { store.updateNoteTitle(noteID, title: $0) },
        onSubmit: { controller.textView?.window?.makeFirstResponder(controller.textView) }
      ).frame(height: 38)

    }
  }

}

/// Keep the native field editor in charge of typing. A SwiftUI text binding
/// invalidated window sizing as the title's intrinsic width changed on each key.
private struct NoteTitleField: NSViewRepresentable {
  let note: NoteDocument
  var currentTitle: () -> String?
  var onTitle: (String) -> Void
  var onSubmit: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> NoteTitleTextField {
    let field = NoteTitleTextField()
    field.cell = CenteredNoteTitleCell(textCell: "")
    field.isBordered = false
    field.isBezeled = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.font = NSFont(name: "Georgia", size: 30) ?? .systemFont(ofSize: 30)
    field.textColor = NSColor(StrukturTheme.ink)
    field.placeholderString = "Untitled note"
    field.usesSingleLineMode = true
    field.lineBreakMode = .byClipping
    field.delegate = context.coordinator
    field.setAccessibilityLabel("Note title")
    updateNSView(field, context: context)
    return field
  }
  func updateNSView(_ field: NoteTitleTextField, context: Context) {
    context.coordinator.parent = self
    field.isEditable = note.deletedAt == nil
    field.isSelectable = note.deletedAt == nil
    guard (field.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
    let value = currentTitle() ?? note.title
    if field.stringValue != value { field.stringValue = value }
  }
  func sizeThatFits(_ proposal: ProposedViewSize, nsView: NoteTitleTextField, context: Context)
    -> CGSize?
  {
    CGSize(width: proposal.width ?? 200, height: 38)
  }
  final class Coordinator: NSObject, NSTextFieldDelegate {
    var parent: NoteTitleField
    init(_ parent: NoteTitleField) { self.parent = parent }
    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSTextField else { return }
      parent.onTitle(field.stringValue)
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool
    {
      if selector == #selector(NSResponder.cancelOperation(_:)) {
        control.window?.makeFirstResponder(control.window)
        return true
      }
      guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
      parent.onSubmit()
      return true
    }
  }
}

private final class NoteTitleTextField: NSTextField {
  override var intrinsicContentSize: NSSize {
    NSSize(width: NSView.noIntrinsicMetric, height: 38)
  }
}

private final class CenteredNoteTitleCell: NSTextFieldCell {
  override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
    // AppKit paints an idle borderless field above its field editor. Align the
    // idle glyphs with the editor so clicking the title cannot move the text.
    let offset = (font?.pointSize ?? 30) / 2
    super.drawInterior(
      withFrame: cellFrame.offsetBy(dx: 0, dy: controlView.isFlipped ? offset : -offset),
      in: controlView)
  }
}
