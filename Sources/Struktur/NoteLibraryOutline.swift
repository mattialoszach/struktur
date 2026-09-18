import Foundation

/// A flat, lazy-list-friendly outline. Closed folders do not build any note rows.
enum NoteLibraryOutline {
  struct Row: Identifiable {
    var id: String
    var depth: Int
    var folder: NoteFolder?
    var note: NoteDocument?
  }

  static func sorted(_ notes: [NoteDocument]) -> [NoteDocument] {
    notes.sorted {
      if $0.isPinned != $1.isPinned { return $0.isPinned }
      let order = $0.displayTitle.localizedStandardCompare($1.displayTitle)
      return order == .orderedSame
        ? $0.id.uuidString < $1.id.uuidString : order == .orderedAscending
    }
  }

  static func rows(folders: [NoteFolder], notes: [NoteDocument], expanded: Set<UUID>) -> [Row] {
    let foldersByParent = Dictionary(grouping: folders, by: \.parentID)
    let notesByFolder = Dictionary(grouping: notes.filter { $0.deletedAt == nil }, by: \.folderID)
    var result: [Row] = []
    var visited: Set<UUID> = []
    func append(_ parent: UUID?, depth: Int) {
      let children = (foldersByParent[parent] ?? []).sorted {
        $0.name.localizedStandardCompare($1.name) == .orderedAscending
      }
      for folder in children where visited.insert(folder.id).inserted {
        result.append(Row(id: "folder-\(folder.id)", depth: depth, folder: folder))
        if expanded.contains(folder.id) {
          append(folder.id, depth: depth + 1)
        }
      }
      let documents = sorted(notesByFolder[parent] ?? [])
      for note in documents {
        result.append(Row(id: "note-\(note.id)", depth: depth, note: note))
      }
      if children.isEmpty && documents.isEmpty, let parent {
        result.append(Row(id: "empty-\(parent)", depth: depth))
      }
    }
    append(nil, depth: 0)
    return result
  }
}
