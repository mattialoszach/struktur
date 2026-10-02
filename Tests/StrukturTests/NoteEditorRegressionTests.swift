import AppKit
import Combine
import SwiftUI
import XCTest

@testable import Struktur

@MainActor final class NoteEditorRegressionTests: XCTestCase {
  func testTitleTypingCoalescesWorkspaceRefreshAndExportsImmediately() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "workspace.json")
    let store = WorkspaceStore(fileURL: url)
    store.replaceWorkspace(Workspace())
    let id = store.createNote(markdown: "Keep this body 🌿")
    store.saveNow()
    var notifications = 0
    let observer = store.objectWillChange.sink { notifications += 1 }
    defer { observer.cancel() }
    for count in 1...20 { store.updateNoteTitle(id, title: String(repeating: "x", count: count)) }
    XCTAssertEqual(notifications, 0)
    let exported = try JSONDecoder.struktur.decode(Workspace.self, from: store.exportData())
    XCTAssertEqual(exported.notes?.first?.title, String(repeating: "x", count: 20))
    XCTAssertEqual(exported.notes?.first?.markdown, "Keep this body 🌿")
    store.saveNow()
    XCTAssertEqual(WorkspaceStore(fileURL: url).note(id)?.title, String(repeating: "x", count: 20))
  }

  func testToolbarWrapsTheSameControlsWithoutOverlap() {
    let sizes = [CGSize(width: 315, height: 28), CGSize(width: 78, height: 24)]
    let wide = NoteToolbarLayout.frames(width: 558, sizes: sizes)
    XCTAssertEqual(wide[1].maxX, 558)
    XCTAssertEqual(wide[0].midY, wide[1].midY)
    XCTAssertFalse(wide[0].intersects(wide[1]))
    let narrow = NoteToolbarLayout.frames(width: 350, sizes: sizes)
    XCTAssertGreaterThan(narrow[1].minY, narrow[0].maxY)
    XCTAssertLessThanOrEqual(narrow.map(\.maxX).max()!, 350)
  }

  func testEscapeLeavesNoteEditorAndHidesActiveEquationSource() throws {
    let source = "Inline $x^2$"
    let (window, view, coordinator) = nativeEditor(NoteDocument(markdown: source)) { _ in }
    defer { window.contentView = nil }
    let equation = (source as NSString).range(of: "$x^2$")
    view.setSelectedRange(NSRange(location: equation.location + 2, length: 0))
    XCTAssertNil(view.textStorage?.attribute(.noteVisualSource, at: equation.location,
      effectiveRange: nil))
    view.cancelOperation(nil)
    XCTAssertFalse(window.firstResponder === view)
    XCTAssertNotNil(view.textStorage?.attribute(.noteVisualSource, at: equation.location,
      effectiveRange: nil))
    XCTAssertEqual(view.string, source)
    window.makeFirstResponder(view)
    XCTAssertTrue(window.firstResponder === view)
    XCTAssertNil(view.textStorage?.attribute(.noteVisualSource, at: equation.location,
      effectiveRange: nil))
    _ = coordinator
  }

  func testNewNoteDoesNotStartEditingBeforeClick() throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = WorkspaceStore(fileURL: directory.appending(path: "workspace.json"))
    store.replaceWorkspace(Workspace())
    let id = store.createNote()
    let host = NSHostingView(rootView: NoteDetailView(noteID: id).environmentObject(store))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 780, height: 620),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    defer { window.contentView = nil }
    host.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    func descendants(_ view: NSView) -> [NSView] {
      [view] + view.subviews.flatMap(descendants)
    }
    let views = descendants(host)
    let title = try XCTUnwrap(views.compactMap { $0 as? NSTextField }
      .first { $0.accessibilityLabel() == "Note title" })
    let body = try XCTUnwrap(views.compactMap { $0 as? NoteTextView }.first)
    XCTAssertFalse(window.firstResponder === title)
    XCTAssertFalse(window.firstResponder === body)
  }

  func testNativeTypingPerformanceWithHighlightedLongNoteAndStore() throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = WorkspaceStore(fileURL: directory.appending(path: "workspace.json"))
    var note = NoteDocument(
      markdown: (0..<5000).map {
        "Paragraph \($0) with **bold** text and café 🌿.\n"
      }.joined())
    note.decorations = [NoteDecoration(location: 10, length: 4, color: .gold, highlight: true)]
    var workspace = Workspace()
    workspace.notes = [note]
    store.replaceWorkspace(workspace)
    var notifications = 0
    let observer = store.objectWillChange.sink { notifications += 1 }
    defer { observer.cancel() }
    let controller = NoteEditorController()
    let coordinator = NoteNativeEditor.Coordinator(
      NoteNativeEditor(
        note: note, readOnly: false, availableWidth: 600, controller: controller,
        onText: { store.updateNoteText($0) },
        onImage: { _, _ in }, onLink: { _ in }))
    let view = NoteTextView(usingTextLayoutManager: true)
    view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
    view.isRichText = false
    view.delegate = coordinator
    coordinator.synchronize(view, dark: false)
    let middle = (view.string as NSString).range(of: "Paragraph 2500").location
    view.setSelectedRange(NSRange(location: middle, length: 0))
    var samples: [TimeInterval] = []
    for _ in 0..<100 {
      let start = Date()
      view.insertText("x", replacementRange: view.selectedRange())
      samples.append(Date().timeIntervalSince(start))
      XCTAssertLessThan(coordinator.styler.lastStyledLength, 300)
    }
    XCTAssertEqual(store.note(note.id)?.markdown, view.string)
    XCTAssertEqual(notifications, 0, "Typing and saving status must not invalidate the workspace")
    print(
      "Notes native typing + store, 5,000 paragraphs with one highlight: total=\(samples.reduce(0, +))s p95=\(samples.sorted()[94] * 1000)ms notifications=\(notifications)"
    )
    store.saveNow()
    XCTAssertEqual(
      WorkspaceStore(fileURL: directory.appending(path: "workspace.json")).note(note.id)?.markdown,
      view.string)
  }

  func testExactNativeRangesMoveHighlightsThroughRepeatedUnicodeAndUndo() throws {
    var note = NoteDocument(markdown: "🌿🌿🌿 **bold**\n")
    note.decorations = [NoteDecoration(location: 0, length: 2, color: .gold, highlight: true)]
    let (window, view, coordinator) = nativeEditor(note) { note = $0 }
    defer { window.contentView = nil }
    let undo = try XCTUnwrap(view.undoManager)
    undo.groupsByEvent = false
    view.setSelectedRange(NSRange(location: 0, length: 0))
    undo.beginUndoGrouping()
    view.insertText("🌿", replacementRange: view.selectedRange())
    undo.endUndoGrouping()
    XCTAssertEqual(note.decorations.first?.range, NSRange(location: 2, length: 2))
    let selection = view.selectedRange()
    coordinator.parent = NoteNativeEditor(
      note: note, readOnly: false, availableWidth: 400,
      controller: coordinator.parent.controller, onText: coordinator.parent.onText,
      onImage: { _, _ in }, onLink: { _ in })
    coordinator.synchronize(view, dark: false)
    XCTAssertEqual(view.selectedRange(), selection)
    XCTAssertTrue(undo.canUndo)
    undo.undo()
    XCTAssertEqual(note.markdown, "🌿🌿🌿 **bold**\n")
    XCTAssertEqual(note.decorations.first?.range, NSRange(location: 0, length: 2))
    undo.redo()
    XCTAssertEqual(note.decorations.first?.range, NSRange(location: 2, length: 2))
    // An equal-length replacement also uses the exact native range.
    undo.beginUndoGrouping()
    view.insertText("🍀", replacementRange: NSRange(location: 2, length: 2))
    undo.endUndoGrouping()
    XCTAssertEqual(note.decorations.first?.range, NSRange(location: 2, length: 2))
    XCTAssertEqual((note.markdown as NSString).substring(with: note.decorations[0].range), "🍀")
    try note.validateContent(folderIDs: [])
  }

  func testMarkedTextPreservesCompositionAndRestylesOnCommit() throws {
    var note = NoteDocument(markdown: "**bold** 🌿")
    note.decorations = [NoteDecoration(location: 9, length: 2, color: .blue, highlight: false)]
    let (window, view, coordinator) = nativeEditor(note) { note = $0 }
    defer { window.contentView = nil }
    view.setSelectedRange(NSRange(location: 0, length: 0))
    view.setMarkedText(
      "n", selectedRange: NSRange(location: 1, length: 0), replacementRange: view.selectedRange())
    XCTAssertTrue(view.hasMarkedText())
    coordinator.synchronize(view, dark: false)
    XCTAssertTrue(view.hasMarkedText())
    view.setMarkedText(
      "ni", selectedRange: NSRange(location: 2, length: 0),
      replacementRange: NSRange(location: NSNotFound, length: 0))
    view.insertText("你", replacementRange: NSRange(location: NSNotFound, length: 0))
    XCTAssertFalse(view.hasMarkedText())
    XCTAssertEqual(note.markdown, "你**bold** 🌿")
    XCTAssertEqual(note.decorations.first?.range, NSRange(location: 10, length: 2))
    let fresh = NSTextStorage(string: note.markdown)
    NoteWriteStyle().apply(to: fresh, note: note, dark: false)
    let actual = NSMutableAttributedString(attributedString: try XCTUnwrap(view.textStorage))
    let expected = NSMutableAttributedString(attributedString: fresh)
    // TextKit 2 resolves CJK/emoji fallback fonts lazily at layout time.
    for location in [0, 3, 10] {
      XCTAssertEqual(
        (actual.attribute(.font, at: location, effectiveRange: nil) as? NSFont)?.pointSize, 14)
    }
    actual.removeAttribute(.font, range: NSRange(location: 0, length: actual.length))
    expected.removeAttribute(.font, range: NSRange(location: 0, length: expected.length))
    XCTAssertTrue(actual.isEqual(to: expected))
    try note.validateContent(folderIDs: [])
  }

  func testHighlightedTypingRequestsNativeRedrawBeforeAnyWorkspaceRefresh() throws {
    var note = NoteDocument(markdown: "Highlight")
    note.decorations = [NoteDecoration(location: 0, length: 9, color: .gold, highlight: true)]
    let (window, view, coordinator) = nativeEditor(note) { note = $0 }
    defer { window.contentView = nil }
    view.needsDisplay = false
    view.insertText("x", replacementRange: NSRange(location: 3, length: 0))
    XCTAssertEqual(view.string, "Higxhlight")
    XCTAssertEqual(note.markdown, view.string)
    XCTAssertTrue(
      view.needsDisplay, "Color edits must request paint without waiting for autosave/SwiftUI")
    XCTAssertNotNil(view.textLayoutManager)
    XCTAssertLessThan(coordinator.styler.lastStyledLength, 300)
    XCTAssertEqual(note.decorations[0].length, 10)
    XCTAssertEqual(
      view.textStorage?.attribute(.backgroundColor, at: 3, effectiveRange: nil) as? NSColor,
      NoteColor.gold.background(dark: false))
  }

  func testDelayedViewRefreshCannotRestoreAnOlderTypingSnapshot() throws {
    var note = NoteDocument(markdown: "Before ")
    let (window, view, coordinator) = nativeEditor(note) { note = $0 }
    defer { window.contentView = nil }
    coordinator.parent.currentNote = { note }
    let undo = try XCTUnwrap(view.undoManager)
    undo.groupsByEvent = false
    view.setSelectedRange(NSRange(location: 7, length: 0))
    undo.beginUndoGrouping()
    view.insertText("latest 🌿", replacementRange: view.selectedRange())
    undo.endUndoGrouping()
    // Geometry/environment updates can reuse a SwiftUI value captured before
    // typing. They must read the current model before replacing native text.
    XCTAssertEqual(coordinator.parent.note.markdown, "Before ")
    coordinator.synchronize(view, dark: true)
    XCTAssertEqual(view.string, "Before latest 🌿")
    XCTAssertEqual(note.markdown, view.string)
    XCTAssertEqual(view.selectedRange(), NSRange(location: 16, length: 0))
    XCTAssertTrue(undo.canUndo)
    undo.undo()
    XCTAssertEqual(view.string, "Before ")
    XCTAssertEqual(note.markdown, "Before ")
    note.replaceMarkdown("External replacement")
    coordinator.synchronize(view, dark: true)
    XCTAssertEqual(view.string, "External replacement")
    XCTAssertFalse(undo.canUndo, "A real external replacement invalidates old text undo")
  }

  func testTypingExportsImmediatelyMergesMetadataAndAutosavesAfterIdle() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "workspace.json")
    let store = WorkspaceStore(fileURL: url)
    store.replaceWorkspace(Workspace())
    let id = store.createNote(title: "Original")
    store.saveNow()
    var draft = try XCTUnwrap(store.note(id))
    draft.replaceMarkdown("Latest typing")
    store.updateNoteText(draft)
    XCTAssertTrue(store.isSavePending)
    let exported = try JSONDecoder.struktur.decode(Workspace.self, from: store.exportData())
    XCTAssertEqual(exported.notes?.first?.markdown, draft.markdown)
    store.editNote(id) {
      $0.title = "Renamed"
      $0.isPinned = true
    }
    draft.replaceMarkdown("Latest typing, continued")
    store.updateNoteText(draft)
    XCTAssertEqual(store.note(id)?.title, "Renamed")
    XCTAssertTrue(store.note(id)?.isPinned == true)
    for _ in 0..<40 where store.isSavePending {
      try await Task.sleep(for: .milliseconds(50))
    }
    XCTAssertFalse(store.isSavePending)
    XCTAssertNil(store.lastSaveError)
    let reopened = WorkspaceStore(fileURL: url)
    XCTAssertEqual(reopened.note(id)?.markdown, draft.markdown)
    XCTAssertEqual(reopened.note(id)?.title, "Renamed")
    // A stale editor must not recreate a note after permanent deletion.
    store.editNote(id) { $0.deletedAt = Date() }
    store.permanentlyDeleteNote(id)
    store.updateNoteText(draft)
    XCTAssertNil(store.note(id))
  }

  private func nativeEditor(_ note: NoteDocument, onText: @escaping (NoteDocument) -> Void)
    -> (NSWindow, NoteTextView, NoteNativeEditor.Coordinator)
  {
    _ = NSApplication.shared
    let coordinator = NoteNativeEditor.Coordinator(
      NoteNativeEditor(
        note: note, readOnly: false, availableWidth: 400, controller: NoteEditorController(),
        onText: onText, onImage: { _, _ in }, onLink: { _ in }))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
      styleMask: [.titled], backing: .buffered, defer: false)
    let view = NoteTextView(usingTextLayoutManager: true)
    view.isRichText = false
    view.allowsUndo = true
    view.delegate = coordinator
    window.contentView = view
    window.makeFirstResponder(view)
    coordinator.synchronize(view, dark: false)
    return (window, view, coordinator)
  }

  func testHostedEditorKeepsUndoAcrossAutosaveAndLegacyPreferences() throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = WorkspaceStore(fileURL: directory.appending(path: "workspace.json"))
    store.replaceWorkspace(Workspace())
    let id = store.createNote(markdown: "Before ")
    let host = NSHostingView(rootView: NoteDetailView(noteID: id).environmentObject(store))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 780, height: 620),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    defer { window.contentView = nil }
    func settle() {
      host.layoutSubtreeIfNeeded()
      RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    func editors(_ view: NSView) -> [NoteTextView] {
      if let text = view as? NoteTextView { return [text] }
      return view.subviews.flatMap(editors)
    }
    settle()
    let editor = try XCTUnwrap(editors(host).first)
    window.makeFirstResponder(editor)
    let undo = try XCTUnwrap(editor.undoManager)
    editor.setSelectedRange(NSRange(location: 7, length: 0))
    editor.insertText("**bold**", replacementRange: editor.selectedRange())
    settle()
    store.saveNow()
    settle()
    XCTAssertTrue(undo.canUndo)
    store.updateNoteLibrary { $0.preview = true }
    settle()
    store.updateNoteLibrary { $0.preview = false }
    settle()
    XCTAssertTrue(editors(host).contains { $0 === editor })
    XCTAssertTrue(undo.canUndo)
    window.makeFirstResponder(editor)
    undo.undo()
    settle()
    XCTAssertEqual(editor.string, "Before ")
    XCTAssertEqual(store.note(id)?.markdown, "Before ")
  }

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

  func testMarkdownRenderingPreservesSourceAndStylesCompletedMarkdown() throws {
    let source =
      "# A **bold heading**\n**bold** *italic* _also italic_ ~~removed~~ `code`\n\\*literal*\n"
    let rendered = NSTextStorage(string: source)
    NoteWriteStyle().apply(to: rendered, note: NoteDocument(markdown: source), dark: false)
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

  func testWriteAttributesMatchFreshStylingAcrossUnicodeAndMultilineEdits() throws {
    var note = NoteDocument(
      markdown: "# Heading\nHello 👩🏽‍💻 **world**\n```swift\nlet x = 1\n```\nTail *italic*\n")
    let storage = NSTextStorage(string: note.markdown)
    let styler = NoteWriteStyle()
    styler.apply(to: storage, note: note, dark: false)
    func replace(_ needle: String, with replacement: String) throws {
      let range = (storage.string as NSString).range(of: needle)
      XCTAssertNotEqual(range.location, NSNotFound)
      guard range.location != NSNotFound else { return }
      storage.replaceCharacters(in: range, with: replacement)
      note.replaceMarkdown(storage.string)
      styler.apply(
        to: storage, note: note, dark: false,
        editedRange: NSRange(location: range.location, length: replacement.utf16.count))
      let fresh = NSTextStorage(string: note.markdown)
      NoteWriteStyle().apply(to: fresh, note: note, dark: false)
      XCTAssertTrue(storage.isEqual(to: fresh), "Incremental differs after replacing \(needle)")
    }
    try replace("world", with: "bold 🌿")
    try replace("👩🏽‍💻", with: "\n## Second heading\n")
    try replace("```swift", with: "~~~swift")  // fence markers remain plain source in Write
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
      editedRange: NSRange(location: 0, length: 7))
    let fresh = NSTextStorage(string: note.markdown)
    NoteWriteStyle().apply(to: fresh, note: note, dark: true)
    XCTAssertTrue(storage.isEqual(to: fresh))
  }

  func testLongNoteEditsStyleOnlyAffectedParagraphs() {
    var note = NoteDocument(
      markdown: (0..<5000).map { "Paragraph \($0) with **bold** text.\n" }.joined())
    let storage = NSTextStorage(string: note.markdown)
    let styler = NoteWriteStyle()
    styler.apply(to: storage, note: note, dark: false)
    let start = Date()
    for _ in 0..<100 {
      let range = (storage.string as NSString).range(of: "Paragraph 2500")
      let insertion = NSRange(location: NSMaxRange(range), length: 0)
      storage.replaceCharacters(in: insertion, with: "x")
      note.replaceMarkdown(storage.string)
      styler.apply(
        to: storage, note: note, dark: false,
        editedRange: NSRange(location: insertion.location, length: 1))
      XCTAssertLessThan(styler.lastStyledLength, 300)
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
      note: note, readOnly: false, availableWidth: 400,
      controller: controller, onText: { saved = $0.markdown }, onImage: { _, _ in },
      onLink: { _ in })
    let coordinator = NoteNativeEditor.Coordinator(editor)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
      styleMask: [.titled], backing: .buffered, defer: false)
    let view = NoteTextView(usingTextLayoutManager: true)
    view.isRichText = false
    view.allowsUndo = true
    view.delegate = coordinator
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
    XCTAssertEqual(font.pointSize, 14)
    XCTAssertTrue(undo.canUndo)
    view.isEditable = false
    view.isEditable = true
    XCTAssertTrue(undo.canUndo, "Switching between Preview and Write must preserve text undo")
    undo.undo()
    XCTAssertEqual(view.string, "Before ")
    XCTAssertEqual(saved, "Before ")
    undo.redo()
    XCTAssertEqual(view.string, "Before **bold**")
    XCTAssertEqual(saved, "Before **bold**")
  }

  func testFormatCommandsToggleAndReplaceBlockStyle() {
    let view = NoteTextView(usingTextLayoutManager: true)
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
