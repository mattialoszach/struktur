import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NotesPage: View {
  @EnvironmentObject private var store: WorkspaceStore
  @State private var query = ""
  @State private var trash = false
  @State private var folderEditor: FolderDraft?
  @State private var folderToRemove: NoteFolder?

  var body: some View {
    HStack(spacing: 0) {
      library.frame(width: 238)
      Divider()
      if let note = store.note(store.noteLibrary.selectedNoteID) {
        NoteDetailView(noteID: note.id).id(note.id)
      } else {
        VStack(spacing: 14) {
          EmptyState(
            icon: "book.closed", title: "Room for your ideas",
            message: "Open a note in the library, or start a new page."
          )
          .frame(maxHeight: 240)
          Button("New note", systemImage: "square.and.pencil") { createNote() }
            .buttonStyle(StrukturButtonStyle(primary: true))
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .background(StrukturTheme.canvas)
    .sheet(item: $folderEditor) { draft in NoteFolderSheet(draft: draft) }
    .alert(
      "Remove folder?",
      isPresented: Binding(get: { folderToRemove != nil }, set: { if !$0 { folderToRemove = nil } })
    ) {
      Button("Cancel", role: .cancel) { folderToRemove = nil }
      Button("Remove folder", role: .destructive) {
        if let folder = folderToRemove { store.removeNoteFolder(folder.id) }
        folderToRemove = nil
      }
    } message: {
      Text("Its notes and subfolders will move to the parent folder.")
    }
    .onDisappear { store.saveNow() }
  }

  private var library: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("Notes").font(.strukturSerif(28))
        Spacer()
        Menu {
          Button("New note", systemImage: "square.and.pencil") { createNote() }
          Button("New folder", systemImage: "folder.badge.plus") { folderEditor = FolderDraft() }
          if let folder = store.noteFolders.first(where: { $0.id == store.noteLibrary.folderID }) {
            Button("New subfolder in \(folder.name)") {
              folderEditor = FolderDraft(parentID: folder.id)
            }
            Button("Edit selected folder…") { folderEditor = FolderDraft(folder: folder) }
          }
          Divider()
          Button("Save focus notepad as note", systemImage: "timer") {
            trash = false
            query = ""
            store.createNote(title: "Focus notes", markdown: store.scratchpad)
          }
        } label: {
          Image(systemName: "plus").frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Add to notes")
      }
      TextField("Search notes", text: $query).strukturInput(compact: true)
        .accessibilityLabel("Search notes")
      HStack {
        scopeRow("Library", icon: "books.vertical", selected: !trash) {
          trash = false
          query = ""
          store.updateNoteLibrary { $0.folderID = nil }
        }
        scopeRow("Trash", icon: "trash", selected: trash) {
          trash = true
          query = ""
        }
        .accessibilityLabel("Recently deleted")
      }
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 3) {
          if trash || !search.isEmpty {
            Eyebrow(text: trash ? "Recently deleted" : "Search results").padding(.vertical, 8)
            ForEach(searchResults) { note in noteRow(note, depth: 0, showPath: true) }
            if searchResults.isEmpty {
              Text(trash ? "Deleted notes can be restored here." : "No notes match your search.")
                .font(.caption).foregroundStyle(StrukturTheme.muted).padding(.vertical, 12)
            }
          } else {
            HStack {
              Eyebrow(text: "Folders & notes")
              Spacer()
              IconButton(icon: "folder.badge.plus", label: "New note folder") {
                folderEditor = FolderDraft()
              }
            }.padding(.bottom, 6)
            ForEach(
              NoteLibraryOutline.rows(
                folders: store.noteFolders, notes: store.notes,
                expanded: Set(store.noteLibrary.expandedFolderIDs))
            ) { row in
              if let folder = row.folder {
                folderRow(folder, depth: row.depth)
              } else if let note = row.note {
                noteRow(note, depth: row.depth)
              } else {
                Text("Empty folder").font(.system(size: 11)).foregroundStyle(StrukturTheme.muted)
                  .padding(.leading, indent(row.depth) + 27).padding(.vertical, 5)
              }
            }
            if store.noteFolders.isEmpty && store.notes.allSatisfy({ $0.deletedAt != nil }) {
              Text("Give your ideas a home. Create a note or a folder to get started.")
                .font(.caption).foregroundStyle(StrukturTheme.muted).padding(.vertical, 12)
            }
          }
        }
      }
      Divider()
      Button("New note", systemImage: "square.and.pencil") { createNote() }
        .buttonStyle(StrukturButtonStyle(primary: true)).frame(maxWidth: .infinity)
      if let folder = store.noteFolders.first(where: { $0.id == store.noteLibrary.folderID }),
        !trash
      {
        Label("In \(folder.name)", systemImage: "folder").font(.system(size: 10))
          .foregroundStyle(StrukturTheme.muted).lineLimit(1).help(store.noteFolderPath(folder.id))
      }
    }.padding(16).background(StrukturTheme.sidebar.opacity(0.5))
      .dropDestination(for: String.self) { ids, _ in moveNotes(ids, to: nil) }
  }

  private var search: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var searchResults: [NoteDocument] {
    NoteLibraryOutline.sorted(
      store.notes.filter {
        ($0.deletedAt != nil) == trash
          && (search.isEmpty
            || ($0.title + "\n" + $0.markdown + "\n" + $0.id.uuidString).localizedStandardContains(
              search))
      })
  }
  private func createNote() {
    let folder = trash ? nil : store.noteLibrary.folderID
    trash = false
    query = ""
    store.createNote(folderID: folder)
  }
  private func indent(_ depth: Int) -> CGFloat { CGFloat(min(depth, 8)) * 12 }
  private func scopeRow(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      Label(title, systemImage: icon).font(
        .system(size: 11, weight: selected ? .semibold : .regular)
      )
      .padding(8).frame(maxWidth: .infinity, alignment: .leading)
      .background(
        selected ? StrukturTheme.hairline.opacity(0.6) : .clear,
        in: RoundedRectangle(cornerRadius: 7)
      ).contentShape(Rectangle())
    }.buttonStyle(.plain)
  }
  private func noteRow(_ note: NoteDocument, depth: Int, showPath: Bool = false) -> some View {
    Button {
      if note.deletedAt == nil {
        store.revealNote(note.id)
      } else {
        store.updateNoteLibrary { $0.selectedNoteID = note.id }
      }
    } label: {
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: note.isPinned ? "pin.fill" : "doc.text")
          .font(.system(size: 11)).frame(width: 16).padding(.top, 2)
          .foregroundStyle(StrukturTheme.muted)
        VStack(alignment: .leading, spacing: 4) {
          Text(note.displayTitle).font(.system(size: 12, weight: .medium))
            .fixedSize(horizontal: false, vertical: true)
          if showPath {
            Text(store.noteFolderPath(note.folderID)).font(.system(size: 10))
              .foregroundStyle(StrukturTheme.muted)
          }
        }
        Spacer(minLength: 0)
      }.padding(.vertical, 8).padding(.trailing, 6).padding(.leading, indent(depth) + 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          store.noteLibrary.selectedNoteID == note.id ? StrukturTheme.surface : .clear,
          in: RoundedRectangle(cornerRadius: 7)
        ).contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityLabel("Open note \(note.displayTitle)")
      .draggable(note.id.uuidString)
      .contextMenu {
        if note.deletedAt == nil {
          Button(note.isPinned ? "Unpin note" : "Pin note", systemImage: "pin") {
            store.editNote(note.id) { $0.isPinned.toggle() }
          }
          Menu("Move to folder") {
            Button("Unfiled") { moveNote(note.id, to: nil) }
            ForEach(store.noteFolders) { folder in
              Button(store.noteFolderPath(folder.id)) { moveNote(note.id, to: folder.id) }
            }
          }
          Button("Move to Recently deleted", systemImage: "trash", role: .destructive) {
            store.editNote(note.id) { $0.deletedAt = Date() }
          }
        } else {
          Button("Restore note") { store.editNote(note.id) { $0.deletedAt = nil } }
        }
      }
  }
  private func folderRow(_ folder: NoteFolder, depth: Int) -> some View {
    let expanded = store.noteLibrary.expandedFolderIDs.contains(folder.id)
    return HStack(spacing: 0) {
      Button {
        trash = false
        store.updateNoteLibrary {
          $0.folderID = folder.id
          if expanded {
            $0.expandedFolderIDs.removeAll { $0 == folder.id }
          } else {
            $0.expandedFolderIDs.append(folder.id)
          }
        }
      } label: {
        HStack(spacing: 6) {
          Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 9))
            .frame(width: 10)
          Image(systemName: expanded ? "folder.fill" : "folder").font(.system(size: 12))
            .foregroundStyle(StrukturTheme.muted)
          Text(folder.name).font(.system(size: 12, weight: .medium))
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 0)
        }.padding(.vertical, 8).contentShape(Rectangle())
      }.buttonStyle(.plain).accessibilityLabel("\(expanded ? "Collapse" : "Expand") \(folder.name)")
      Menu {
        Button("New note") {
          query = ""
          trash = false
          store.createNote(folderID: folder.id)
        }
        Button("New subfolder") { folderEditor = FolderDraft(parentID: folder.id) }
        Button("Rename or move…") { folderEditor = FolderDraft(folder: folder) }
        Button("Remove folder…", role: .destructive) { folderToRemove = folder }
      } label: {
        Image(systemName: "ellipsis").font(.system(size: 10)).frame(width: 20, height: 26)
      }
      .menuStyle(.borderlessButton).fixedSize().accessibilityLabel(
        "Actions for folder \(folder.name)")
    }.padding(.leading, indent(depth) + 4).padding(.trailing, 4)
      .background(
        store.noteLibrary.folderID == folder.id ? StrukturTheme.hairline.opacity(0.4) : .clear,
        in: RoundedRectangle(cornerRadius: 7)
      )
      .dropDestination(for: String.self) { ids, _ in moveNotes(ids, to: folder.id) }
  }
  private func moveNote(_ id: UUID, to folderID: UUID?) {
    store.editNote(id) { $0.folderID = folderID }
    store.revealNote(id)
  }
  private func moveNotes(_ ids: [String], to folderID: UUID?) -> Bool {
    let notes = ids.compactMap(UUID.init(uuidString:)).filter {
      store.note($0)?.deletedAt == nil && store.note($0) != nil
    }
    for id in notes { moveNote(id, to: folderID) }
    return !notes.isEmpty
  }
}

struct FolderDraft: Identifiable {
  var id = UUID()
  var folder: NoteFolder?
  var parentID: UUID?
}

struct NoteFolderSheet: View {
  @EnvironmentObject private var store: WorkspaceStore
  @Environment(\.dismiss) private var dismiss
  let draft: FolderDraft
  @State private var name = ""
  @State private var parentID: UUID?
  @State private var error = false
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(draft.folder == nil ? "New folder" : "Edit folder").font(.strukturSerif(26))
      TextField("Folder name", text: $name).strukturInput().accessibilityLabel(
        "Folder name")
      StrukturMenuPicker(
        title: "Inside", selection: $parentID,
        options: [StrukturMenuOption(value: UUID?.none, title: "Top level")]
          + store.noteFolders.filter { $0.id != draft.folder?.id }.sorted {
            store.noteFolderPath($0.id) < store.noteFolderPath($1.id)
          }.map {
            StrukturMenuOption(
              value: Optional($0.id), title: store.noteFolderPath($0.id))
          })
      if error {
        Text("Choose a different parent. Folders cannot contain themselves or exceed 32 levels.")
          .font(.caption).foregroundStyle(StrukturTheme.destructive)
      }
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Save folder") {
          let saved: Bool
          if let folder = draft.folder {
            saved = store.updateNoteFolder(folder.id, name: name, parentID: parentID)
          } else {
            saved = store.createNoteFolder(name: name, parentID: parentID) != nil
          }
          if saved {
            if let parentID {
              store.updateNoteLibrary {
                if !$0.expandedFolderIDs.contains(parentID) {
                  $0.expandedFolderIDs.append(parentID)
                }
              }
            }
            dismiss()
          } else {
            error = true
          }
        }.keyboardShortcut(.defaultAction).disabled(
          name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }.buttonStyle(StrukturButtonStyle())
    }.padding(26).frame(width: 440).background(StrukturTheme.canvas)
      .onAppear {
        name = draft.folder?.name ?? ""
        parentID = draft.folder?.parentID ?? draft.parentID
      }
  }
}
