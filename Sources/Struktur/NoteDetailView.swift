import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NoteDetailView: View {
  @EnvironmentObject private var store: WorkspaceStore
  let noteID: UUID
  @StateObject private var controller = NoteEditorController()
  @State private var error: String?
  @State private var reference: WorkspaceReference?
  @State private var showingLinks = false
  @State private var confirmingDelete = false
  @State private var showingHelp = false
  @State private var showingTextColors = false
  @State private var showingHighlights = false
  @FocusState private var titleFocused: Bool
  @Environment(\.colorScheme) private var colorScheme

  private var note: NoteDocument? { store.note(noteID) }
  private var preview: Bool { store.noteLibrary.preview }
  var body: some View {
    Group {
      if let note {
        VStack(alignment: .leading, spacing: 0) {
          heading(note).padding(22)
          Divider()
          if note.deletedAt != nil {
            HStack {
              Text("This note is in Recently deleted.").font(.caption)
              Spacer()
              Button("Restore note") { store.editNote(noteID) { $0.deletedAt = nil } }
                .buttonStyle(StrukturButtonStyle(primary: true, compact: true))
            }.padding(14).background(StrukturTheme.butter)
          } else {
            toolbar.padding(.horizontal, 16).padding(.vertical, 8)
          }
          GeometryReader { geometry in
            ZStack {
              NoteNativeEditor(
                note: note, preview: false, availableWidth: geometry.size.width,
                controller: controller,
                editingEnabled: !preview && note.deletedAt == nil,
                onText: { value in store.editNote(noteID) { $0.replaceMarkdown(value) } },
                onImage: insertImage, onLink: openLink
              )
              .opacity(preview || note.deletedAt != nil ? 0 : 1)
              .allowsHitTesting(!preview && note.deletedAt == nil)
              .accessibilityHidden(preview || note.deletedAt != nil)
              if preview || note.deletedAt != nil {
                NoteNativeEditor(
                  note: note, preview: true, availableWidth: geometry.size.width,
                  controller: controller,
                  onText: { _ in }, onImage: { _, _ in }, onLink: openLink)
              }
            }
          }
          Divider()
          HStack(spacing: 12) {
            Text("\(note.markdown.split(whereSeparator: \.isWhitespace).count) words")
            Text("·")
            Text(
              store.lastSaveError != nil
                ? "Could not save" : store.isSavePending ? "Saving…" : "Saved locally"
            )
            .accessibilityLabel("Note save status")
            Spacer()
            Button {
              showingHelp.toggle()
            } label: {
              Label("Markdown help", systemImage: "questionmark.circle")
            }
            .buttonStyle(.plain).popover(isPresented: $showingHelp) {
              VStack(alignment: .leading, spacing: 12) {
                Text("Write with Markdown").font(.strukturSerif(23))
                Text(
                  "Formatting appears as you type. Markdown markers stay visible and editable in Write. Select text to format it; Color and Highlight show a sample of every shade."
                )
                Text(
                  verbatim:
                    "# Heading\n**Bold** · *Italic* · ~~Strikethrough~~\n- Bullet list\n1. Numbered list\n- [ ] Checklist\n> Quote\n`Code` or fenced ``` code blocks\n[Label](https://example.com)"
                )
                .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                Text(
                  "⌘B / ⌘I format a selection. Return continues lists; Return on an empty item ends the list. Paste or drop an image into Write. Click checkboxes and links in Preview."
                )
                Text(
                  "Colors and highlights are saved with the workspace and PDF. Markdown export contains plain source and local image files. Remote images are shown as labels; tables, HTML, and advanced Markdown extensions remain source text."
                )
              }.font(.callout).padding(22).frame(width: 420)
            }
          }.font(.system(size: 10)).foregroundStyle(StrukturTheme.muted).padding(14)
        }.background(StrukturTheme.surface)
      } else {
        EmptyState(
          icon: "doc", title: "Note unavailable",
          message: "This note was removed or belongs to another workspace.")
      }
    }
    .sheet(isPresented: $showingLinks) {
      NoteLinkPicker { title, url in
        let safe = title.replacingOccurrences(of: "[", with: "(").replacingOccurrences(
          of: "]", with: ")")
        controller.insert("[\(safe)](\(url))")
      }
    }
    .sheet(item: $reference) { WorkspaceReferenceDestination(reference: $0) }
    .alert("Notes", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(error ?? "")
    }
    .alert("Delete this note permanently?", isPresented: $confirmingDelete) {
      Button("Cancel", role: .cancel) {}
      Button("Delete permanently", role: .destructive) { store.permanentlyDeleteNote(noteID) }
    } message: {
      Text("The note and its images will be removed from this workspace. This cannot be undone.")
    }
    .onAppear { titleFocused = note?.title == "Untitled note" && note?.markdown.isEmpty == true }
    .onChange(of: preview) { _, reading in
      if reading, let view = controller.textView, view.window?.firstResponder === view {
        view.window?.makeFirstResponder(nil)
      }
    }
    .onDisappear { store.saveNow() }
  }

  private func heading(_ note: NoteDocument) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 10) {
        SuitIcon(symbol: .diamond, size: 14)
        Text(store.noteFolderPath(note.folderID)).font(.system(size: 11)).foregroundStyle(
          StrukturTheme.muted
        )
        .lineLimit(2)
        Spacer()
        StrukturOptions(
          label: "Note mode",
          selection: Binding(
            get: { preview },
            set: { value in
              store.updateNoteLibrary { $0.preview = value }
            }), options: [false, true]
        ) { $0 ? "Preview" : "Write" }.frame(width: 150)
          .disabled(note.deletedAt != nil)
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
            Button("Delete permanently…", role: .destructive) { confirmingDelete = true }
          }
        } label: {
          Image(systemName: "ellipsis").frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Note actions")
      }
      TextField(
        "Untitled note",
        text: Binding(
          get: { store.note(noteID)?.title ?? "" },
          set: { title in
            store.editNote(noteID) { $0.title = title }
          })
      ).textFieldStyle(.plain).font(.strukturSerif(30))
        .accessibilityLabel("Note title").disabled(note.deletedAt != nil)
        .focused($titleFocused)
        .onSubmit { controller.textView?.window?.makeFirstResponder(controller.textView) }
    }
  }

  private var toolbar: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 9) {
        formatButtons
        Spacer(minLength: 2)
        insertMenu
      }
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 9) { formatButtons }
        insertMenu
      }
    }.disabled(preview)
  }
  @ViewBuilder private var formatButtons: some View {
    IconButton(icon: "bold", label: "Bold selection (⌘B)") {
      controller.wrap("**", placeholder: "bold text")
    }
    IconButton(icon: "italic", label: "Italic selection (⌘I)") {
      controller.wrap("*", placeholder: "italic text")
    }
    IconButton(icon: "strikethrough", label: "Strikethrough selection") {
      controller.wrap("~~", placeholder: "text")
    }
    IconButton(icon: "chevron.left.forwardslash.chevron.right", label: "Inline code") {
      controller.wrap("`", placeholder: "code")
    }
    Divider().frame(height: 17)
    decorationMenu(highlight: false)
    decorationMenu(highlight: true)
  }
  private func decorationMenu(highlight: Bool) -> some View {
    let presented = highlight ? $showingHighlights : $showingTextColors
    return Button {
      presented.wrappedValue.toggle()
    } label: {
      Label(
        highlight ? "Highlight" : "Color", systemImage: highlight ? "highlighter" : "paintpalette"
      )
      .font(.system(size: 11, weight: .medium)).padding(.horizontal, 5).frame(height: 28)
    }
    .buttonStyle(.plain)
    .disabled(!controller.hasSelection)
    .help("Select text, then choose a \(highlight ? "highlight" : "text color")")
    .accessibilityLabel(highlight ? "Highlight selection" : "Text color")
    .popover(isPresented: presented, arrowEdge: .bottom) {
      VStack(alignment: .leading, spacing: 6) {
        Text(highlight ? "Highlight" : "Text color").font(.strukturSerif(20)).padding(.bottom, 6)
        ForEach(NoteColor.allCases) { color in
          Button {
            decorate(color, highlight: highlight)
            presented.wrappedValue = false
          } label: {
            HStack(spacing: 12) {
              Text("Text").font(.system(size: 12, weight: .medium))
                .foregroundStyle(
                  highlight
                    ? StrukturTheme.ink
                    : Color(nsColor: color.foreground(dark: colorScheme == .dark))
                )
                .frame(width: 46, height: 28)
                .background(
                  highlight
                    ? Color(nsColor: color.background(dark: colorScheme == .dark))
                    : StrukturTheme.surface,
                  in: RoundedRectangle(cornerRadius: 5)
                )
                .overlay(
                  RoundedRectangle(cornerRadius: 5).strokeBorder(
                    StrukturTheme.hairline, lineWidth: 1))
              Text(color.title).font(.system(size: 12))
              Spacer()
            }.padding(4).contentShape(Rectangle())
          }.buttonStyle(.plain).accessibilityLabel(
            "\(color.title) \(highlight ? "highlight" : "text color")")
        }
        Divider().padding(.vertical, 4)
        Button(
          highlight ? "Remove highlight" : "Default text color", systemImage: "arrow.uturn.backward"
        ) {
          decorate(nil, highlight: highlight)
          presented.wrappedValue = false
        }.buttonStyle(.plain).font(.system(size: 12)).padding(6)
      }.padding(16).frame(width: 210).background(StrukturTheme.canvas)
    }
  }
  private var insertMenu: some View {
    Menu {
      Button("Heading 1") { controller.block("# ") }
      Button("Heading 2") { controller.block("## ") }
      Button("Heading 3") { controller.block("### ") }
      Divider()
      Button("Bullet list") { controller.block("- ") }
      Button("Numbered list") { controller.block("1. ") }
      Button("Checklist") { controller.block("- [ ] ") }
      Button("Quote") { controller.block("> ") }
      Button("Code block") {
        controller.insert("\n```\ncode\n```\n", selectOffset: 5, selectLength: 4)
      }
      Button("Divider") { controller.insert("\n\n---\n\n") }
      Divider()
      Button("Web link") {
        controller.insert("[Link title](https://example.com)", selectOffset: 13, selectLength: 19)
      }
      Button("Link to workspace item…") { showingLinks = true }
      Button("Image from file…", systemImage: "photo") { chooseImage() }
    } label: {
      Label("Insert", systemImage: "plus").font(.system(size: 11, weight: .medium))
    }
    .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Insert into note")
  }
  private func decorate(_ color: NoteColor?, highlight: Bool) {
    let selection = controller.selection
    if var note {
      guard selection.length > 0, Range(selection, in: note.markdown) != nil else { return }
      note.decorations = note.decorations.flatMap { item -> [NoteDecoration] in
        guard item.highlight == highlight, NSIntersectionRange(item.range, selection).length > 0
        else { return [item] }
        var pieces: [NoteDecoration] = []
        if item.location < selection.location {
          var left = item
          left.length = selection.location - item.location
          pieces.append(left)
        }
        if NSMaxRange(item.range) > NSMaxRange(selection) {
          var right = item
          right.location = NSMaxRange(selection)
          right.length = NSMaxRange(item.range) - right.location
          pieces.append(right)
        }
        return pieces
      }
      if let color {
        note.decorations.append(
          NoteDecoration(
            location: selection.location, length: selection.length, color: color,
            highlight: highlight))
      }
      controller.applyDecorations(note.decorations, store: store, noteID: noteID)
    }
  }
  private func openLink(_ url: URL) {
    if url.scheme == "struktur-check", let index = Int(url.lastPathComponent),
      note?.deletedAt == nil
    {
      store.editNote(noteID) {
        $0.replaceMarkdown(MarkdownChecklist.toggling(line: index, in: $0.markdown))
      }
    } else if url.scheme?.lowercased() == "struktur" {
      if let target = WorkspaceReference(url: url), store.contains(target) {
        reference = target
      } else {
        error = "This reference was deleted, is invalid, or belongs to another workspace."
      }
    } else if NoteRendering.allowed(url) {
      NSWorkspace.shared.open(url)
    }
  }
  private func chooseImage() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      insertImage(try NoteImages.read(url), url.deletingPathExtension().lastPathComponent)
    } catch { self.error = error.localizedDescription }
  }
  private func insertImage(_ data: Data, _ name: String) {
    guard let note, note.deletedAt == nil, !preview else { return }
    do {
      let image = try NoteImages.attachment(data, name: name)
      guard note.attachments.count < 100,
        note.attachments.reduce(0, { $0 + $1.data.count }) + image.data.count <= 50_000_000
      else {
        throw WorkspaceValidationError.invalid(
          "This note has reached its image limit (100 images or 50 MB). Use another note for more images."
        )
      }
      store.editNote(noteID) { $0.attachments.append(image) }
      let alt = name.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
        .components(separatedBy: .newlines).joined(separator: " ")
      controller.insert("\n![\(alt)](\(image.markdownPath))\n")
    } catch { self.error = error.localizedDescription }
  }
  private func exportMarkdown(_ note: NoteDocument) {
    let panel = NSSavePanel()
    panel.title = "Export Markdown folder"
    panel.message = "Creates a new folder containing your .md file and any inserted images."
    panel.nameFieldStringValue = NoteExport.safeName(note.displayTitle)
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do { try NoteExport.markdown(note, to: url) } catch { self.error = error.localizedDescription }
  }
  private func exportPDF(_ note: NoteDocument) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.pdf]
    panel.nameFieldStringValue = NoteExport.safeName(note.displayTitle) + ".pdf"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do { try NoteExport.pdf(note).write(to: url, options: .atomic) } catch {
      self.error = error.localizedDescription
    }
  }
}

struct NoteLinkPicker: View {
  @EnvironmentObject private var store: WorkspaceStore
  @Environment(\.dismiss) private var dismiss
  var insert: (String, String) -> Void
  @State private var query = ""
  private struct Item: Identifiable {
    var id: String
    var title: String
    var kind: String
  }
  private var items: [Item] {
    (store.notes.filter { $0.deletedAt == nil }.map {
      Item(id: "struktur://note/\($0.id)", title: $0.displayTitle, kind: "Note")
    }
      + store.tasks.map { Item(id: "struktur://task/\($0.id)", title: $0.title, kind: "Task") }
      + store.entries.map { Item(id: "struktur://event/\($0.id)", title: $0.title, kind: "Event") }
      + store.projects.map { Item(id: "struktur://space/\($0.id)", title: $0.name, kind: "Space") }
      + store.goals.map { Item(id: "struktur://goal/\($0.id)", title: $0.title, kind: "Goal") })
      .filter { query.isEmpty || ($0.title + $0.kind + $0.id).localizedStandardContains(query) }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Link to your workspace").font(.strukturSerif(25))
      TextField("Search notes, tasks, events, spaces, and goals", text: $query).textFieldStyle(
        .roundedBorder)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 6) {
          ForEach(items) { item in
            Button {
              insert(item.title, item.id)
              dismiss()
            } label: {
              HStack {
                Text(item.title)
                Spacer()
                Text(item.kind).foregroundStyle(StrukturTheme.muted)
              }
              .padding(9).contentShape(Rectangle())
            }.buttonStyle(.plain)
          }
        }
      }
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
      }
    }.padding(24).frame(width: 530, height: 480).background(StrukturTheme.canvas)
  }
}

struct WorkspaceReferenceDestination: View {
  @EnvironmentObject private var store: WorkspaceStore
  @Environment(\.dismiss) private var dismiss
  let reference: WorkspaceReference
  var body: some View {
    switch reference.kind {
    case .note:
      VStack(spacing: 0) {
        HStack {
          Spacer()
          Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
        }.padding(12)
        NoteDetailView(noteID: reference.id)
      }.frame(width: 780, height: 620)
    case .task:
      if let task = store.tasks.first(where: { $0.id == reference.id }) {
        TaskEditorSheet(task: task)
      }
    case .event:
      if let entry = store.resolveEntry(reference.id) { EventEditorSheet(entry: entry) }
    case .goal:
      if let goal = store.goals.first(where: { $0.id == reference.id }) {
        GoalEditorSheet(goal: goal)
      }
    case .space:
      if let project = store.project(reference.id) { ProjectEditorSheet(project: project) }
    }
  }
}
