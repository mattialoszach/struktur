import AppKit
import XCTest

@testable import Struktur

@MainActor final class NoteEditorRegressionTests: XCTestCase {
  func testOutlineContainsNotesOnlyInsideExpandedFoldersAndKeepsStableOrder() {
    let root = NoteFolder(name: "Study")
    let child = NoteFolder(name: "Lectures", parentID: root.id)
    let a = NoteDocument(title: "Alpha", folderID: child.id)
    var b = NoteDocument(title: "Beta", folderID: child.id)
    let unfiled = NoteDocument(title: "Unfiled")
    let deleted = NoteDocument(title: "Deleted", folderID: root.id, deletedAt: Date())
    let folders = [root, child]
    let notes = [b, a, unfiled, deleted]
    let closed = NoteLibraryOutline.rows(folders: folders, notes: notes, expanded: [])
    XCTAssertEqual(closed.compactMap(\.folder?.id), [root.id])
    XCTAssertEqual(closed.compactMap(\.note?.id), [unfiled.id])
    let open = NoteLibraryOutline.rows(
      folders: folders, notes: notes, expanded: [root.id, child.id])
    XCTAssertEqual(open.compactMap(\.note?.id), [a.id, b.id, unfiled.id])
    XCTAssertEqual(open.first { $0.note?.id == a.id }?.depth, 2)
    b.replaceMarkdown("Typing changes the content and timestamp, not row order")
    XCTAssertEqual(
      NoteLibraryOutline.rows(
        folders: folders, notes: [b, a, unfiled],
        expanded: [root.id, child.id]
      ).map(\.id), open.map(\.id))
    let empty = NoteLibraryOutline.rows(folders: [root], notes: [], expanded: [root.id])
    XCTAssertEqual(empty.count, 2)
    XCTAssertNil(empty.last?.folder)
    XCTAssertNil(empty.last?.note)
  }

  func testLiveFormattingPreservesSourceAndStylesCompletedMarkdown() throws {
    let source =
      "# A **bold heading**\n**bold** *italic* _also italic_ ~~removed~~ `code`\n\\*literal*\n"
    let rendered = NoteRendering.attributed(
      NoteDocument(markdown: source), preview: false, dark: false)
    XCTAssertEqual(rendered.string, source)
    func font(_ text: String) throws -> NSFont {
      try XCTUnwrap(
        rendered.attribute(
          .font, at: (source as NSString).range(of: text).location,
          effectiveRange: nil) as? NSFont)
    }
    XCTAssertGreaterThan(try font("bold heading").pointSize, 20)
    XCTAssertTrue(NSFontManager.shared.traits(of: try font("bold heading")).contains(.boldFontMask))
    XCTAssertTrue(NSFontManager.shared.traits(of: try font("italic")).contains(.italicFontMask))
    XCTAssertTrue(
      NSFontManager.shared.traits(of: try font("also italic")).contains(.italicFontMask))
    XCTAssertEqual(
      rendered.attribute(
        .strikethroughStyle,
        at: (source as NSString).range(of: "removed").location, effectiveRange: nil) as? Int, 1)
    XCTAssertTrue(try font("code").isFixedPitch)
    XCTAssertFalse(NSFontManager.shared.traits(of: try font("literal")).contains(.italicFontMask))
  }

  func testIncrementalStylingMatchesFreshRenderingAcrossUnicodeAndFenceEdits() throws {
    var note = NoteDocument(
      markdown: "# Heading\nHello 👩🏽‍💻 **world**\n```swift\nlet x = 1\n```\nTail *italic*\n")
    let storage = NSTextStorage(string: note.markdown)
    let styler = NoteLiveStyler()
    styler.apply(to: storage, note: note, dark: false)
    func replace(_ needle: String, with replacement: String) throws {
      let range = (storage.string as NSString).range(of: needle)
      XCTAssertNotEqual(range.location, NSNotFound)
      guard range.location != NSNotFound else { return }
      storage.replaceCharacters(in: range, with: replacement)
      note.replaceMarkdown(storage.string)
      styler.apply(
        to: storage, note: note, dark: false,
        editedRange: NSRange(location: range.location, length: replacement.utf16.count),
        changeInLength: replacement.utf16.count - range.length)
      let fresh = NSTextStorage(string: note.markdown)
      NoteLiveStyler().apply(to: fresh, note: note, dark: false)
      XCTAssertTrue(storage.isEqual(to: fresh), "Incremental differs after replacing \(needle)")
    }
    try replace("world", with: "bold 🌿")
    try replace("👩🏽‍💻", with: "\n## Second heading\n")
    try replace("```swift", with: "~~~swift")  // mismatched closing fence must remain code
    try replace("```\n", with: "~~~\n")
    try replace("~~~swift\n", with: "")
    try replace("~~~\n", with: "")
    try replace("Tail *italic*", with: "~~Finished~~\n\n")
    try replace("# Heading\nHello ", with: "")
    try replace(storage.string, with: "")
    storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "**New**")
    note.replaceMarkdown(storage.string)
    styler.apply(
      to: storage, note: note, dark: true,
      editedRange: NSRange(location: 0, length: 7), changeInLength: 7)
    XCTAssertTrue(storage.isEqual(to: NoteRendering.attributed(note, preview: false, dark: true)))
  }

  func testLongNoteEditsStyleOneParagraphInsteadOfWholeDocument() {
    var note = NoteDocument(
      markdown: (0..<5000).map { "Paragraph \($0) with **bold** text.\n" }.joined())
    let storage = NSTextStorage(string: note.markdown)
    let styler = NoteLiveStyler()
    styler.apply(to: storage, note: note, dark: false)
    let start = Date()
    for _ in 0..<100 {
      let range = (storage.string as NSString).range(of: "Paragraph 2500")
      let insertion = NSRange(location: NSMaxRange(range), length: 0)
      storage.replaceCharacters(in: insertion, with: "x")
      note.replaceMarkdown(storage.string)
      styler.apply(
        to: storage, note: note, dark: false,
        editedRange: NSRange(location: insertion.location, length: 1), changeInLength: 1)
      XCTAssertLessThan(styler.lastStyledLength, 150)
    }
    print(
      "Notes: 100 incremental edits in a 5,000-paragraph note: \(Date().timeIntervalSince(start))s")
    XCTAssertEqual(storage.string, note.markdown)
  }

  func testNativeTypingRendersImmediatelyAndKeepsSelectionUndoAndRedo() throws {
    _ = NSApplication.shared
    var saved = ""
    let note = NoteDocument(markdown: "Before ")
    let controller = NoteEditorController()
    let editor = NoteNativeEditor(
      note: note, preview: false, availableWidth: 400,
      controller: controller, onText: { saved = $0 }, onImage: { _, _ in }, onLink: { _ in })
    let coordinator = NoteNativeEditor.Coordinator(editor)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
      styleMask: [.titled], backing: .buffered, defer: false)
    let view = NoteTextView()
    view.isRichText = false
    view.allowsUndo = true
    view.delegate = coordinator
    view.textStorage?.delegate = coordinator
    window.contentView = view
    window.makeFirstResponder(view)
    coordinator.synchronize(view, dark: false)
    let undo = try XCTUnwrap(view.undoManager)
    undo.groupsByEvent = false
    view.setSelectedRange(NSRange(location: 7, length: 0))
    undo.beginUndoGrouping()
    view.insertText("**bold**", replacementRange: view.selectedRange())
    undo.endUndoGrouping()
    XCTAssertEqual(saved, "Before **bold**")
    XCTAssertEqual(view.selectedRange(), NSRange(location: 15, length: 0))
    let font = try XCTUnwrap(
      view.textStorage?.attribute(.font, at: 9, effectiveRange: nil) as? NSFont)
    XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
    XCTAssertTrue(undo.canUndo)
    undo.undo()
    XCTAssertEqual(view.string, "Before ")
    XCTAssertEqual(saved, "Before ")
    undo.redo()
    XCTAssertEqual(view.string, "Before **bold**")
    XCTAssertEqual(saved, "Before **bold**")
  }

  func testFormatCommandsToggleAndReplaceBlockStyle() {
    let view = NoteTextView()
    view.isRichText = false
    let controller = NoteEditorController()
    controller.textView = view
    view.string = "**Hello**"
    view.setSelectedRange(NSRange(location: 2, length: 5))
    controller.wrap("**", placeholder: "text")
    XCTAssertEqual(view.string, "Hello")
    XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: 5))
    view.string = "# Heading\n- [x] Checked\n"
    view.setSelectedRange(NSRange(location: 0, length: view.string.utf16.count))
    controller.block("1. ")
    XCTAssertEqual(view.string, "1. Heading\n2. Checked\n")
  }

  func testCreatingNoteRevealsEntireFolderPathAndRejectsInvalidImageEdits() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "workspace.json")
    let store = WorkspaceStore(fileURL: url)
    store.replaceWorkspace(Workspace())
    let root = try XCTUnwrap(store.createNoteFolder(name: "Root"))
    let child = try XCTUnwrap(store.createNoteFolder(name: "Child", parentID: root))
    let note = store.createNote(folderID: child)
    XCTAssertEqual(Set(store.noteLibrary.expandedFolderIDs), [root, child])
    XCTAssertEqual(store.noteLibrary.folderID, child)
    store.editNote(note) {
      $0.attachments.append(NoteAttachment(name: "Bad", data: Data([1, 2, 3])))
    }
    XCTAssertTrue(store.note(note)?.attachments.isEmpty == true)
    store.editNote(note) { $0.replaceMarkdown("Saved immediately in memory") }
    store.saveNow()
    let reopened = WorkspaceStore(fileURL: url)
    XCTAssertEqual(reopened.note(note)?.markdown, "Saved immediately in memory")
    XCTAssertEqual(reopened.noteLibrary, store.noteLibrary)
  }
}
