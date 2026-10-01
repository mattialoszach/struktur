import AppKit
import SwiftUI

/// The same live native surface in Focus, task/event drafts and dashboard notes.
/// Bindings retain their owner's save/cancel/autosave semantics.
struct LiveMarkdownField: View {
  @Binding var text: String
  var editorLabel = "Notes editor"
  var controller: NoteEditorController
  @EnvironmentObject private var store: WorkspaceStore
  @State private var id = UUID()
  @State private var reference: WorkspaceReference?
  @State private var referenceNotFound = false

  var body: some View {
    GeometryReader { geometry in
      NoteNativeEditor(
        note: NoteDocument(id: id, markdown: text), readOnly: false,
        availableWidth: geometry.size.width, controller: controller,
        acceptsImages: false, accessibilityLabel: editorLabel,
        currentNote: { NoteDocument(id: id, markdown: text) },
        onText: { text = $0.markdown }, onImage: { _, _ in }, onLink: openLink)
    }
    .sheet(item: $reference) { WorkspaceReferenceDestination(reference: $0) }
    .alert("Reference not found", isPresented: $referenceNotFound) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("This reference was deleted, is invalid, or belongs to another workspace.")
    }
  }
  private func openLink(_ url: URL) {
    if url.scheme?.lowercased() == "struktur" {
      if let target = WorkspaceReference(url: url), store.contains(target) {
        reference = target
      } else {
        referenceNotFound = true
      }
    } else if NoteRendering.allowed(url) {
      NSWorkspace.shared.open(url)
    }
  }
}

struct MarkdownComposer: View {
  @Binding var text: String
  var title = "Notes"
  var editorHeight: CGFloat = 160
  var showsHelp = true
  var editorLabel = "Notes editor"
  @State private var controller = NoteEditorController()

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        if !title.isEmpty {
          Label(title, systemImage: "text.alignleft").font(.caption.weight(.semibold))
        }
        Spacer()
        IconButton(icon: "bold", label: "Bold selection (⌘B)") {
          controller.wrap("**", placeholder: "text")
        }
        IconButton(icon: "italic", label: "Italic selection (⌘I)") {
          controller.wrap("*", placeholder: "text")
        }
        IconButton(icon: "function", label: "Insert equation") {
          controller.insert("$x^2$", selectOffset: 1, selectLength: 3)
        }
      }
      LiveMarkdownField(text: $text, editorLabel: editorLabel, controller: controller)
        .frame(height: editorHeight)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
      if showsHelp {
        Text(
          verbatim:
            "Markdown formats as you type. **Bold**, # headings, - [ ] checklists, $x^2$ equations."
        )
        .font(.caption2).foregroundStyle(StrukturTheme.muted)
        Text("Click checkboxes to toggle them. ⌘Click a link to open it.")
          .font(.caption2).foregroundStyle(StrukturTheme.muted)
      }
    }
  }
}
