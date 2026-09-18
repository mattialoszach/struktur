import Foundation
import ImageIO

struct NoteFolder: Identifiable, Codable, Equatable {
  var id = UUID()
  var name: String
  var parentID: UUID?
}

enum NoteColor: String, Codable, CaseIterable, Identifiable {
  case rose, gold, green, blue, purple
  var id: String { rawValue }
  var title: String { rawValue.capitalized }
}

struct NoteDecoration: Codable, Equatable {
  var location: Int
  var length: Int
  var color: NoteColor
  var highlight: Bool
  var range: NSRange { NSRange(location: location, length: length) }
}

struct NoteAttachment: Identifiable, Codable, Equatable {
  var id = UUID()
  var name: String
  var data: Data
  var isValidImage: Bool {
    guard !data.isEmpty, data.count <= 10_000_000,
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int
    else { return false }
    return (1...2000).contains(width) && (1...2000).contains(height)
  }
  var markdownPath: String { "assets/\(id.uuidString.lowercased()).png" }
}

struct NoteDocument: Identifiable, Codable, Equatable {
  var id = UUID()
  var title = "Untitled note"
  var markdown = ""
  var folderID: UUID?
  var createdAt = Date()
  var updatedAt = Date()
  var decorations: [NoteDecoration] = []
  var attachments: [NoteAttachment] = []
  var isPinned = false
  var deletedAt: Date?
  var displayTitle: String {
    title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled note" : title
  }

  /// Preserve annotation anchors using UTF-16 offsets, matching AppKit's text selections.
  mutating func replaceMarkdown(_ value: String) {
    guard value != markdown else { return }
    // Most notes have no range annotations. Avoid allocating two arrays of every
    // grapheme in a long document on every keystroke in that common case.
    guard !decorations.isEmpty else {
      markdown = value
      updatedAt = Date()
      return
    }
    let old = Array(markdown)
    let new = Array(value)
    var prefix = 0
    while prefix < min(old.count, new.count), old[prefix] == new[prefix] { prefix += 1 }
    var suffix = 0
    while suffix < min(old.count, new.count) - prefix,
      old[old.count - 1 - suffix] == new[new.count - 1 - suffix]
    { suffix += 1 }
    let start = String(old.prefix(prefix)).utf16.count
    let removed = String(old[prefix..<(old.count - suffix)]).utf16.count
    let inserted = String(new[prefix..<(new.count - suffix)]).utf16.count
    let end = start + removed
    let delta = inserted - removed
    decorations = decorations.compactMap { decoration in
      var item = decoration
      let upper = item.location + item.length
      if upper <= start { return item }
      if item.location >= end {
        item.location += delta
        return item
      }
      let lower = min(item.location, start)
      let newUpper = upper >= end ? upper + delta : start + inserted
      item.location = lower
      item.length = max(0, newUpper - lower)
      return item.length > 0 ? item : nil
    }
    markdown = value
    updatedAt = Date()
  }

  func validateContent(folderIDs: Set<UUID>, checkImages: Bool = true) throws {
    let length = markdown.utf16.count
    guard folderID.map(folderIDs.contains) ?? true,
      Set(attachments.map(\.id)).count == attachments.count,
      attachments.count <= 100,
      !checkImages || attachments.allSatisfy(\.isValidImage),
      attachments.reduce(0, { $0 + $1.data.count }) <= 50_000_000,
      decorations.allSatisfy({
        $0.location >= 0 && $0.length > 0 && $0.location <= length
          && $0.length <= length - $0.location && Range($0.range, in: markdown) != nil
      })
    else {
      throw WorkspaceValidationError.invalid(
        "A note contains an invalid folder, image, or text decoration.")
    }
  }
}

struct NoteLibraryPreferences: Codable, Equatable {
  var selectedNoteID: UUID?
  var folderID: UUID?
  var expandedFolderIDs: [UUID] = []
  var preview = false
}

extension Workspace {
  func validateNotes() throws {
    let folders = noteFolders ?? []
    let documents = notes ?? []
    let folderIDs = Set(folders.map(\.id))
    guard folderIDs.count == folders.count, Set(documents.map(\.id)).count == documents.count,
      folders.count <= 10_000, documents.count <= 100_000
    else {
      throw WorkspaceValidationError.invalid(
        "Notes contain duplicate identifiers or too many items.")
    }
    let parents = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0.parentID) })
    for folder in folders {
      guard !folder.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw WorkspaceValidationError.invalid("A note folder has an empty name.")
      }
      var visited: Set<UUID> = [folder.id]
      var cursor = folder.parentID
      while let id = cursor {
        guard folderIDs.contains(id), visited.insert(id).inserted, visited.count <= 32 else {
          throw WorkspaceValidationError.invalid(
            "Note folders contain a missing parent, cycle, or more than 32 levels.")
        }
        cursor = parents[id] ?? nil
      }
    }
    for note in documents {
      try note.validateContent(folderIDs: folderIDs)
    }
  }
}
