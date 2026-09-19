import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NoteDetailView: View {
  @EnvironmentObject private var store: WorkspaceStore
  let noteID: UUID
  @State private var controller = NoteEditorController()
  @State private var error: String?
  @State private var reference: WorkspaceReference?
  @State private var showingLinks = false
  @State private var confirmingDelete = false
  @State private var showingHelp = false

  private var note: NoteDocument? { store.note(noteID) }
  private var preview: Bool { store.noteLibrary.preview }
  var body: some View {
    Group {
      if let note {
        VStack(alignment: .leading, spacing: 0) {
          NoteHeader(
            note: note, controller: controller,
            exportMarkdown: exportMarkdown, exportPDF: exportPDF,
            confirmDeletion: { confirmingDelete = true }
          ).padding(22)
          Divider()
          if note.deletedAt != nil {
            HStack {
              Text("This note is in Recently deleted.").font(.caption)
              Spacer()
              Button("Restore note") { store.editNote(noteID) { $0.deletedAt = nil } }
                .buttonStyle(StrukturButtonStyle(primary: true, compact: true))
            }.padding(14).background(StrukturTheme.butter)
          } else {
            NoteEditorToolbar(
              noteID: noteID, controller: controller,
              showLinks: { showingLinks = true }, chooseImage: chooseImage
            )
            .disabled(preview).padding(.horizontal, 16).padding(.vertical, 8)
          }
          GeometryReader { geometry in
            ZStack {
              NoteNativeEditor(
                note: note, preview: false, availableWidth: geometry.size.width,
                controller: controller,
                editingEnabled: !preview && note.deletedAt == nil,
                currentNote: { store.note(noteID) },
                onText: { store.updateNoteText($0) },
                onImage: insertImage, onLink: openLink
              )
              .opacity(preview || note.deletedAt != nil ? 0 : 1)
              .allowsHitTesting(!preview && note.deletedAt == nil)
              .accessibilityHidden(preview || note.deletedAt != nil)
              if preview || note.deletedAt != nil {
                NoteNativeEditor(
                  note: note, preview: true, availableWidth: geometry.size.width,
                  controller: controller,
                  currentNote: { store.note(noteID) },
                  onText: { _ in }, onImage: { _, _ in }, onLink: openLink)
              }
            }
          }
          Divider()
          HStack(spacing: 12) {
            NoteWordCount(note: note)
            Text("·")
            WorkspaceSaveIndicator(status: store.saveStatus, failed: store.lastSaveError != nil)
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
                  "Write uses plain text with stable line spacing. Markdown markers stay visible and editable; switch to Preview to see formatted headings, lists, and emphasis. Color and Highlight apply to selected text in both modes."
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
    .onChange(of: preview) { _, reading in
      if reading, let view = controller.textView, view.window?.firstResponder === view {
        view.window?.makeFirstResponder(nil)
      }
    }
    .onDisappear { store.saveNow() }
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

private struct NoteWordCount: View {
  let note: NoteDocument
  @State private var count: Int?

  var body: some View {
    Text(count.map { "\($0) words" } ?? "Counting words…")
      .task(id: note.updatedAt) {
        let source = note.markdown
        let task = Task.detached(priority: .utility) {
          var count = 0
          var inWord = false
          for character in source {
            if Task.isCancelled { return 0 }
            if character.isWhitespace {
              inWord = false
            } else if !inWord {
              count += 1
              inWord = true
            }
          }
          return count
        }
        let result = await withTaskCancellationHandler {
          await task.value
        } onCancel: {
          task.cancel()
        }
        if !Task.isCancelled { count = result }
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
