import AppKit
import PDFKit
import XCTest

@testable import Struktur

@MainActor final class NoteLibraryTests: XCTestCase {
  private func withStore(_ action: (WorkspaceStore, URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "struktur-notes-tests-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "workspace.json")
    let store = WorkspaceStore(fileURL: url)
    store.replaceWorkspace(Workspace())
    try action(store, url)
  }
  private func image() throws -> NoteAttachment {
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 180, pixelsHigh: 90,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0, bitsPerPixel: 0)!
    let pixels = bitmap.bitmapData!
    for y in 0..<90 {
      for x in 0..<180 {
        let index = y * bitmap.bytesPerRow + x * 4
        pixels[index] = x < 90 ? 110 : 180
        pixels[index + 1] = x < 90 ? 180 : 140
        pixels[index + 2] = x < 90 ? 130 : 210
        pixels[index + 3] = 255
      }
    }
    return try NoteImages.attachment(
      XCTUnwrap(bitmap.representation(using: .png, properties: [:])), name: "Two colors")
  }

  func testLegacyWorkspaceAndNotesRoundTripWithImagesAndPreferences() throws {
    try withStore { store, url in
      let original = store.workspace
      var legacy = try XCTUnwrap(
        JSONSerialization.jsonObject(with: store.exportData()) as? [String: Any])
      legacy.removeValue(forKey: "notes")
      legacy.removeValue(forKey: "noteFolders")
      legacy.removeValue(forKey: "noteLibrary")
      try store.importData(JSONSerialization.data(withJSONObject: legacy))
      XCTAssertTrue(store.notes.isEmpty)
      let parent = try XCTUnwrap(store.createNoteFolder(name: "Study"))
      let child = try XCTUnwrap(store.createNoteFolder(name: "Lecture", parentID: parent))
      let attachment = try image()
      let id = store.createNote(
        folderID: child, title: "Biology",
        markdown: "# Biology\n\n![Figure](\(attachment.markdownPath))")
      store.editNote(id) {
        $0.attachments = [attachment]
        $0.decorations = [NoteDecoration(location: 2, length: 7, color: .green, highlight: true)]
      }
      store.updateNoteLibrary {
        $0.folderID = child
        $0.expandedFolderIDs = [parent]
        $0.preview = true
      }
      store.saveNow()
      let restored = WorkspaceStore(fileURL: url)
      XCTAssertEqual(
        try JSONEncoder.struktur.encode(restored.notes),
        try JSONEncoder.struktur.encode(store.notes))
      XCTAssertEqual(restored.noteLibrary, store.noteLibrary)
      XCTAssertEqual(restored.noteFolderPath(child), "Study / Lecture")
      XCTAssertEqual(restored.workspace.scratchpad, original.scratchpad)
      XCTAssertEqual(restored.preferences, original.preferences)
      try restored.workspace.validate()
      let second = WorkspaceStore(
        fileURL: url.deletingLastPathComponent().appending(path: "other.json"))
      try second.importData(store.exportData())
      XCTAssertEqual(
        try JSONEncoder.struktur.encode(second.notes), try JSONEncoder.struktur.encode(store.notes))
      XCTAssertEqual(second.noteFolders, store.noteFolders)
    }
  }

  func testFoldersRejectCyclesAndRehomeContentsWithoutDeletion() throws {
    try withStore { store, _ in
      let root = try XCTUnwrap(store.createNoteFolder(name: "Root"))
      let child = try XCTUnwrap(store.createNoteFolder(name: "Child", parentID: root))
      let grandchild = try XCTUnwrap(store.createNoteFolder(name: "Grandchild", parentID: child))
      let note = store.createNote(folderID: child, markdown: "Keep this")
      XCTAssertFalse(store.updateNoteFolder(root, name: "Root", parentID: grandchild))
      XCTAssertNil(store.createNoteFolder(name: "Invalid", parentID: UUID()))
      XCTAssertNil(store.createNoteFolder(name: "  "))
      store.removeNoteFolder(child)
      XCTAssertEqual(store.note(note)?.markdown, "Keep this")
      XCTAssertEqual(store.note(note)?.folderID, root)
      XCTAssertEqual(store.noteFolders.first { $0.id == grandchild }?.parentID, root)
      store.removeNoteFolder(root)
      XCTAssertNil(store.note(note)?.folderID)
      try store.workspace.validate()
    }
  }

  func testRevealingNoteFromSearchRestoresItsFolderContext() throws {
    try withStore { store, _ in
      let root = try XCTUnwrap(store.createNoteFolder(name: "Root"))
      let child = try XCTUnwrap(store.createNoteFolder(name: "Child", parentID: root))
      let note = store.createNote(folderID: child)
      store.updateNoteLibrary {
        $0.selectedNoteID = nil
        $0.folderID = nil
        $0.preview = true
      }
      store.revealNote(note)
      XCTAssertEqual(store.noteLibrary.selectedNoteID, note)
      XCTAssertEqual(store.noteLibrary.folderID, child)
      XCTAssertTrue(store.noteLibrary.expandedFolderIDs.contains(root))
      XCTAssertTrue(store.noteLibrary.preview)
      let preferences = store.noteLibrary
      store.revealNote(UUID())
      XCTAssertEqual(store.noteLibrary, preferences)
    }
  }

  func testTrashRestorePermanentDeleteAndStaleEdits() throws {
    try withStore { store, url in
      let id = store.createNote(markdown: "Keep until confirmed")
      let reference = try XCTUnwrap(WorkspaceReference(url: URL(string: "struktur://note/\(id)")!))
      XCTAssertTrue(store.contains(reference))
      store.permanentlyDeleteNote(id)
      XCTAssertNotNil(store.note(id))
      store.editNote(id) { $0.deletedAt = Date() }
      XCTAssertFalse(store.contains(reference))
      store.editNote(id) { $0.deletedAt = nil }
      XCTAssertTrue(store.contains(reference))
      store.editNote(id) { $0.deletedAt = Date() }
      store.permanentlyDeleteNote(id)
      store.editNote(id) { $0.title = "Stale editor" }
      XCTAssertNil(WorkspaceStore(fileURL: url).note(id))
    }
  }

  func testDecorationsFollowUnicodeEditsAndPartialDeletion() throws {
    var note = NoteDocument(markdown: "👩🏽‍💻 hello world")
    let selected = (note.markdown as NSString).range(of: "hello")
    note.decorations = [
      NoteDecoration(
        location: selected.location, length: selected.length, color: .blue, highlight: false)
    ]
    note.replaceMarkdown("Before " + note.markdown)
    XCTAssertEqual((note.markdown as NSString).substring(with: note.decorations[0].range), "hello")
    note.replaceMarkdown(note.markdown.replacingOccurrences(of: "hello", with: "hey"))
    XCTAssertEqual((note.markdown as NSString).substring(with: note.decorations[0].range), "hey")
    note.replaceMarkdown("")
    XCTAssertTrue(note.decorations.isEmpty)
  }

  func testInvalidNoteImportsLeaveOriginalFileUntouched() throws {
    try withStore { store, url in
      store.createNote(markdown: "Original")
      store.saveNow()
      let saved = try Data(contentsOf: url)
      var invalid = store.workspace
      invalid.noteFolders = [NoteFolder(name: "Loop")]
      let folderID = invalid.noteFolders?[0].id
      invalid.noteFolders?[0].parentID = folderID
      XCTAssertThrowsError(try store.importData(JSONEncoder.struktur.encode(invalid)))
      invalid = store.workspace
      invalid.notes?[0].decorations = [
        NoteDecoration(location: Int.max, length: Int.max, color: .gold, highlight: true)
      ]
      XCTAssertThrowsError(try store.importData(JSONEncoder.struktur.encode(invalid)))
      invalid = store.workspace
      let duplicate = invalid.notes![0]
      invalid.notes?.append(duplicate)
      XCTAssertThrowsError(try store.importData(JSONEncoder.struktur.encode(invalid)))
      XCTAssertEqual(try Data(contentsOf: url), saved)
    }
  }

  func testUnreadableWorkspaceRemainsProtectedByNoteEdits() throws {
    try withStore { _, url in
      let unreadable = Data("not a workspace".utf8)
      try unreadable.write(to: url)
      let store = WorkspaceStore(fileURL: url)
      store.createNote(markdown: "A recovered draft")
      store.createNoteFolder(name: "Recovered")
      store.saveNow()
      XCTAssertEqual(try Data(contentsOf: url), unreadable)
      XCTAssertNotNil(store.lastSaveError)
    }
  }

  func testSpaceExportDoesNotLeakUnrelatedNoteLibrary() throws {
    try withStore { store, _ in
      let project = Project(name: "Selected", color: .mint)
      store.add(project)
      store.createNote(title: "Private research")
      store.createNoteFolder(name: "Personal")
      let subset = try JSONDecoder.struktur.decode(
        Workspace.self, from: store.exportData(projectID: project.id))
      XCTAssertNil(subset.notes)
      XCTAssertNil(subset.noteFolders)
      XCTAssertNil(subset.noteLibrary)
      XCTAssertEqual(subset.projects.count, 1)
    }
  }

  func testMarkdownExportKeepsExactSourceAndPortableAssetsAndDoesNotOverwrite() throws {
    let attachment = try image()
    var note = NoteDocument(
      title: "../Research: notes",
      markdown: "# Title\n\n**Important**\n![Two colors](\(attachment.markdownPath))\n")
    note.attachments = [attachment]
    note.decorations = [NoteDecoration(location: 2, length: 5, color: .gold, highlight: true)]
    let destination = FileManager.default.temporaryDirectory.appending(
      path: "struktur-export-test-\(UUID())")
    defer { try? FileManager.default.removeItem(at: destination) }
    try NoteExport.markdown(note, to: destination)
    let source = try String(
      contentsOf: destination.appending(path: "\(NoteExport.safeName(note.displayTitle)).md"),
      encoding: .utf8)
    XCTAssertEqual(source, note.markdown)
    XCTAssertEqual(
      try Data(contentsOf: destination.appending(path: attachment.markdownPath)), attachment.data)
    XCTAssertThrowsError(try NoteExport.markdown(note, to: destination))
    XCTAssertFalse(NoteExport.safeName(note.title).contains("/"))
  }

  func testRenderingFormattingCodeImagesLinksAndDecorations() throws {
    let attachment = try image()
    var note = NoteDocument(
      markdown:
        "# Heading\n**Bold** and *italic*\n- [ ] Check\n`**literal**`\n```swift\n**also literal**\n```\n![Image](\(attachment.markdownPath))\n[Site](https://example.com)\n[Unsafe](file:///tmp/secret)"
    )
    note.attachments = [attachment]
    note.decorations = [NoteDecoration(location: 2, length: 7, color: .rose, highlight: true)]
    let text = NoteWriteStyle.attributedForExport(note, width: 460)
    XCTAssertTrue(text.string.contains("Heading\nBold and italic"))
    XCTAssertTrue(text.string.contains("**literal**"))
    XCTAssertTrue(text.string.contains("**also literal**"))
    XCTAssertTrue(text.string.contains("\u{fffc} Check"))
    XCTAssertNotNil(text.attribute(.backgroundColor, at: 0, effectiveRange: nil))
    let site = (text.string as NSString).range(of: "Site")
    XCTAssertEqual(
      text.attribute(.link, at: site.location, effectiveRange: nil) as? URL,
      URL(string: "https://example.com"))
    let unsafe = (text.string as NSString).range(of: "Unsafe")
    XCTAssertNil(text.attribute(.link, at: unsafe.location, effectiveRange: nil))
    var images = 0
    text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) {
      value, _, _ in if value != nil { images += 1 }
    }
    XCTAssertEqual(images, 2, "The checkbox and local image both render as attachments")
    let live = NSTextStorage(string: note.markdown)
    NoteWriteStyle().apply(to: live, note: note, dark: true)
    XCTAssertEqual(live.string, note.markdown)
  }

  func testNativeListContinuationAndSelectionFormatting() {
    let view = NoteTextView()
    view.isRichText = false
    view.allowsUndo = true
    view.string = "- [x] First"
    view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
    view.insertNewline(nil)
    XCTAssertEqual(view.string, "- [x] First\n- [ ] ")
    view.insertNewline(nil)
    XCTAssertEqual(view.string, "- [x] First\n")
    view.string = "3. Third"
    view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
    view.insertNewline(nil)
    XCTAssertEqual(view.string, "3. Third\n4. ")
    let controller = NoteEditorController()
    controller.textView = view
    view.string = "Hello 👋"
    view.setSelectedRange(NSRange(location: 0, length: 5))
    controller.wrap("**", placeholder: "text")
    XCTAssertEqual(view.string, "**Hello** 👋")
    XCTAssertEqual(view.selectedRange(), NSRange(location: 2, length: 5))
  }

  func testColorChangesSupportNativeUndoAndRedo() throws {
    _ = NSApplication.shared
    try withStore { store, _ in
      let id = store.createNote(markdown: "Hello")
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
        styleMask: [.titled], backing: .buffered, defer: false)
      let view = NoteTextView()
      view.allowsUndo = true
      window.contentView = view
      window.makeFirstResponder(view)
      let controller = NoteEditorController()
      controller.textView = view
      let undo = try XCTUnwrap(view.undoManager)
      undo.groupsByEvent = false
      undo.beginUndoGrouping()
      let decorations = [NoteDecoration(location: 0, length: 5, color: .blue, highlight: false)]
      controller.applyDecorations(decorations, store: store, noteID: id)
      undo.endUndoGrouping()
      XCTAssertEqual(store.note(id)?.decorations, decorations)
      undo.undo()
      XCTAssertEqual(store.note(id)?.decorations, [])
      undo.redo()
      XCTAssertEqual(store.note(id)?.decorations, decorations)
    }
  }

  func testImagePasteboardInsertionUsesOwnedImageData() throws {
    let asset = try image()
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    board.setData(asset.data, forType: .png)
    let view = NoteTextView()
    var inserted: Data?
    view.imageHandler = { data, _ in inserted = data }
    XCTAssertTrue(view.consumeImage(board))
    XCTAssertEqual(inserted, asset.data)
    board.clearContents()
    board.setString("Ordinary text", forType: .string)
    XCTAssertFalse(view.consumeImage(board))
  }

  func testImageValidationAndPDFPagination() throws {
    XCTAssertThrowsError(try NoteImages.attachment(Data("not an image".utf8), name: "Bad"))
    var invalid = Workspace()
    invalid.notes = [
      NoteDocument(attachments: [NoteAttachment(name: "Corrupt", data: Data("bad".utf8))])
    ]
    XCTAssertThrowsError(try invalid.validate())
    let attachment = try image()
    var note = NoteDocument(
      title: "Notes export verification",
      markdown:
        "# A clear heading\n\nA **bold idea**, *emphasis*, and [a web link](https://example.com).\n\n- [ ] Read the chapter\n- [x] Take notes\n\n![Two colors](\(attachment.markdownPath))\n\n## Long-form notes\n"
    )
    note.attachments = [attachment]
    note.decorations = [NoteDecoration(location: 2, length: 15, color: .gold, highlight: true)]
    note.markdown += (1...100).map {
      "Paragraph \($0): A readable note keeps its context, links, and ideas together. This is a pagination check with enough text to wrap naturally across lines.\n"
    }.joined()
    let data = try NoteExport.pdf(note)
    let pdf = try XCTUnwrap(PDFDocument(data: data))
    XCTAssertGreaterThan(pdf.pageCount, 2)
    let text = pdf.string ?? ""
    XCTAssertTrue(text.contains("Notes export verification"))
    XCTAssertTrue(text.contains("Paragraph 1:"))
    XCTAssertTrue(text.contains("Paragraph 100:"))
    XCTAssertTrue(
      (pdf.page(at: 0)?.annotations ?? []).contains { $0.url == URL(string: "https://example.com") }
    )
    if let path = ProcessInfo.processInfo.environment["STRUKTUR_NOTES_QA_PDF"] {
      try data.write(to: URL(fileURLWithPath: path))
      try attachment.data.write(
        to: URL(fileURLWithPath: path).deletingPathExtension().appendingPathExtension("png"))
    }
  }
}
