import AppKit
import SwiftUI
import XCTest

@testable import Struktur

@MainActor final class NoteLiveEditorTests: XCTestCase {
  private func styled(
    _ source: String, selection: NSRange = NSRange(location: NSNotFound, length: 0)
  ) -> NSTextStorage {
    let storage = NSTextStorage(string: source)
    NoteWriteStyle().apply(
      to: storage, note: NoteDocument(markdown: source), dark: false, selection: selection)
    return storage
  }

  func testLiveTypographyAndSourceArePreserved() throws {
    let source = "# Heading\n**bold** *italic* ~~gone~~ `literal $x$`\n\\$5 and $10\n- [ ] A task\n"
    let text = styled(source)
    XCTAssertEqual(text.string, source)
    func at(_ needle: String, _ key: NSAttributedString.Key) -> Any? {
      text.attribute(key, at: (source as NSString).range(of: needle).location, effectiveRange: nil)
    }
    XCTAssertGreaterThan(try XCTUnwrap(at("Heading", .font) as? NSFont).pointSize, 20)
    XCTAssertTrue(
      NSFontManager.shared.traits(of: try XCTUnwrap(at("bold", .font) as? NSFont)).contains(
        .boldFontMask))
    XCTAssertTrue(
      NSFontManager.shared.traits(of: try XCTUnwrap(at("italic", .font) as? NSFont)).contains(
        .italicFontMask))
    XCTAssertEqual(at("gone", .strikethroughStyle) as? Int, 1)
    XCTAssertNotNil(at("**", .noteHidden))
    XCTAssertNil(at("$x$", .noteVisualSource))
    XCTAssertNil(at("$5", .noteVisualSource))
    XCTAssertNotNil(at("- [ ]", .noteCheckbox))
  }

  func testHeadingLevelsHaveClearSizeSteps() throws {
    let source = "# One\n## Two\n### Three\n#### Four\n##### Five\n###### Six\nBody"
    let text = styled(source)
    let sizes = ["One", "Two", "Three", "Four", "Five", "Six", "Body"].map { word in
      (text.attribute(.font, at: (source as NSString).range(of: word).location,
        effectiveRange: nil) as? NSFont)?.pointSize ?? 0
    }
    XCTAssertEqual(sizes, [34, 27, 22, 19, 16, 14, 14])
    XCTAssertEqual(text.string, source)
  }

  func testFormulaPickerExamplesRenderOffline() {
    for source in [
      #"\frac{a}{b}"#, #"\sqrt{x}"#, "x^{n}", #"\alpha"#,
      #"\sum_{i=1}^{n} i"#, #"\int_{a}^{b} f(x)\,dx"#,
      #"\lim_{x \to a} f(x)"#,
      #"x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}"#,
    ] {
      XCTAssertNotNil(NoteMath.render(source, display: true, dark: false).image, source)
    }
  }

  func testMathRendersCachesAndRevealsSourceWhileEditing() throws {
    let source = #"Inline $\frac{a}{b}$ and \(x^2\)."#
    let storage = styled(source)
    let start = (source as NSString).range(of: "$\\frac").location
    let visual = try XCTUnwrap(
      storage.attribute(.noteVisual, at: start, effectiveRange: nil) as? NoteInlineVisual)
    XCTAssertGreaterThan(visual.size.height, 15)
    XCTAssertEqual(storage.string, source)
    let before = NoteMath.renderCount
    _ = styled(source)
    XCTAssertEqual(NoteMath.renderCount, before)
    let active = styled(source, selection: NSRange(location: start + 5, length: 0))
    XCTAssertNil(active.attribute(.noteVisual, at: start, effectiveRange: nil))
    XCTAssertNil(active.attribute(.noteHidden, at: start, effectiveRange: nil))
    var previews = 0
    active.enumerateAttribute(.noteMathPreview, in: NSRange(location: 0, length: active.length)) {
      value, _, _ in
      if value != nil { previews += 1 }
    }
    XCTAssertEqual(previews, 1, "Editing LaTeX keeps its result live on the same surface")
    XCTAssertEqual(active.string, source)
  }

  func testDisplayMathFencesAndInvalidMathRemainEditable() {
    let source =
      "$$\n\\sum_{i=1}^{n} i = \\frac{n(n+1)}{2}\n$$\nAfter **bold**\n```latex\n$x^2$\n```\n"
    let storage = styled(source)
    XCTAssertNotNil(storage.attribute(.noteVisual, at: 0, effectiveRange: nil))
    let code = (source as NSString).range(of: "$x^2$").location
    XCTAssertNil(storage.attribute(.noteVisual, at: code, effectiveRange: nil))
    XCTAssertEqual(storage.string, source)
    for expression in [
      #"\frac{"#, #"\unknowncommand{x}"#, String(repeating: "{", count: 40),
      String(repeating: "x", count: 5000),
    ] {
      let text = styled("$\(expression)$")
      XCTAssertNil(text.attribute(.noteVisual, at: 0, effectiveRange: nil))
      XCTAssertEqual(text.string, "$\(expression)$")
    }
    let unclosed = styled("$$\nx^2\n")
    XCTAssertEqual(unclosed.string, "$$\nx^2\n")
    XCTAssertNil(unclosed.attribute(.noteHidden, at: 0, effectiveRange: nil))
  }

  func testIndexConvergesAcrossStructuralEditsAndBoundsOrdinaryWork() {
    let prefix = String(repeating: "A **paragraph**.\n", count: 2500)
    let suffix = String(repeating: "Another paragraph.\n", count: 2500)
    var source = prefix + "$$\nx^2\n$$\n```swift\nlet x = 1\n```\n" + suffix
    var index = NoteMarkupIndex()
    _ = index.update(source as NSString, editedRange: nil)
    for (needle, replacement) in [
      ("x^2", "\\frac{a}{b}"), ("```swift", "~~~swift"),
      ("```\n", "~~~\n"), ("$$\n", ""), ("$$\n", ""), ("let x = 1", "let x = 2\nlet y = 3"),
    ] {
      let range = (source as NSString).range(of: needle)
      source = (source as NSString).replacingCharacters(in: range, with: replacement)
      _ = index.update(
        source as NSString,
        editedRange: NSRange(location: range.location, length: replacement.utf16.count))
      var fresh = NoteMarkupIndex()
      _ = fresh.update(source as NSString, editedRange: nil)
      XCTAssertEqual(index.blocks.map(\.range), fresh.blocks.map(\.range))
      XCTAssertEqual(index.blocks.map(\.fence), fresh.blocks.map(\.fence))
      XCTAssertEqual(index.blocks.map(\.math), fresh.blocks.map(\.math))
    }
    let range = (source as NSString).range(of: "Another")
    source = (source as NSString).replacingCharacters(in: range, with: "Changed")
    _ = index.update(source as NSString, editedRange: NSRange(location: range.location, length: 7))
    XCTAssertLessThan(index.lastParsedLength, 100)
  }

  func testNativeCheckboxAndMathEditsKeepUndoAndExactSource() throws {
    _ = NSApplication.shared
    var note = NoteDocument(markdown: "- [ ] 🌿 Review\nInline $x^2$ end\n")
    let coordinator = NoteNativeEditor.Coordinator(
      NoteNativeEditor(
        note: note, readOnly: false, availableWidth: 500, controller: NoteEditorController(),
        onText: { note = $0 }, onImage: { _, _ in }, onLink: { _ in }))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 500, height: 300), styleMask: [.titled],
      backing: .buffered, defer: false)
    let view = NoteTextView(usingTextLayoutManager: true)
    view.isRichText = false
    view.allowsUndo = true
    view.delegate = coordinator
    window.contentView = view
    window.makeFirstResponder(view)
    defer { window.contentView = nil }
    coordinator.synchronize(view, dark: false)
    let undo = try XCTUnwrap(view.undoManager)
    undo.groupsByEvent = false
    undo.beginUndoGrouping()
    XCTAssertTrue(view.toggleChecklist(at: 0))
    undo.endUndoGrouping()
    XCTAssertTrue(note.markdown.hasPrefix("- [x]"))
    undo.undo()
    XCTAssertTrue(note.markdown.hasPrefix("- [ ]"))
    undo.redo()
    XCTAssertTrue(note.markdown.hasPrefix("- [x]"))
    let range = (view.string as NSString).range(of: "x^2")
    view.setSelectedRange(range)
    undo.beginUndoGrouping()
    view.insertText(#"\frac{a}{b}"#, replacementRange: range)
    undo.endUndoGrouping()
    XCTAssertEqual(note.markdown, "- [x] 🌿 Review\nInline $\\frac{a}{b}$ end\n")
    XCTAssertNotNil(view.textLayoutManager)
    undo.undo()
    XCTAssertEqual(note.markdown, "- [x] 🌿 Review\nInline $x^2$ end\n")
    undo.redo()
    XCTAssertTrue(note.markdown.contains(#"\frac{a}{b}"#))
  }

  func testExportUsesLiveFormattingAndIncludesEquationAttachments() throws {
    let note = NoteDocument(
      title: "Math", markdown: "# Heading\n**bold** and $x^2$\n$$\n\\frac{a}{b}\n$$\n")
    let attributed = NoteWriteStyle.attributedForExport(note, width: 480)
    XCTAssertTrue(attributed.string.contains("Heading\nbold and"))
    XCTAssertFalse(attributed.string.contains("$"))
    var attachments = 0
    attributed.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributed.length))
    { value, _, _ in
      if value != nil { attachments += 1 }
    }
    XCTAssertEqual(attachments, 2)
    XCTAssertTrue(try NoteExport.pdf(note).starts(with: Data("%PDF".utf8)))
  }

  func testLongParagraphPlainEditsReuseFormattingAndSyntaxEditsReparse() throws {
    _ = NSApplication.shared
    var note = NoteDocument(
      markdown: String(repeating: "Some **bold** text and café 🌿. ", count: 1000))
    let coordinator = NoteNativeEditor.Coordinator(
      NoteNativeEditor(
        note: note, readOnly: false, availableWidth: 600, controller: NoteEditorController(),
        onText: { note = $0 }, onImage: { _, _ in }, onLink: { _ in }))
    let view = NoteTextView(usingTextLayoutManager: true)
    view.delegate = coordinator
    coordinator.synchronize(view, dark: false)
    for _ in 0..<20 {
      view.insertText("x", replacementRange: view.selectedRange())
      XCTAssertEqual(coordinator.styler.lastStyledLength, 1)
    }
    view.insertText("# ", replacementRange: NSRange(location: 0, length: 0))
    XCTAssertGreaterThan(coordinator.styler.lastStyledLength, 1000)
    let font = try XCTUnwrap(
      view.textStorage?.attribute(.font, at: 3, effectiveRange: nil) as? NSFont)
    XCTAssertGreaterThan(font.pointSize, 20)
    XCTAssertEqual(view.string, note.markdown)
  }

  func testResizeOnlyRestylesWidthSensitiveBlocks() throws {
    let source =
      String(repeating: "A plain paragraph.\n", count: 5000)
      + "$$\n\\frac{a + b + c + d}{x + y}\n$$\n"
    let note = NoteDocument(markdown: source)
    let storage = NSTextStorage(string: source)
    let styler = NoteWriteStyle()
    styler.apply(to: storage, note: note, dark: false, width: 600)
    let start = (source as NSString).range(of: "$$").location
    styler.resize(in: storage, note: note, dark: false, width: 80)
    XCTAssertLessThan(styler.lastStyledLength, 60)
    let visual = try XCTUnwrap(
      storage.attribute(.noteVisual, at: start, effectiveRange: nil) as? NoteInlineVisual)
    XCTAssertLessThanOrEqual(visual.size.width, 68)
    XCTAssertEqual(storage.string, source)
  }

  func testToolbarUndoDoesNotConsumePrecedingTyping() throws {
    _ = NSApplication.shared
    var note = NoteDocument()
    let controller = NoteEditorController()
    let coordinator = NoteNativeEditor.Coordinator(
      NoteNativeEditor(
        note: note, readOnly: false, availableWidth: 500, controller: controller,
        onText: { note = $0 }, onImage: { _, _ in }, onLink: { _ in }))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
      styleMask: [.titled], backing: .buffered, defer: false)
    let view = NoteTextView(usingTextLayoutManager: true)
    view.isRichText = false
    view.allowsUndo = true
    view.delegate = coordinator
    controller.textView = view
    window.contentView = view
    window.makeFirstResponder(view)
    defer { window.contentView = nil }
    coordinator.synchronize(view, dark: false)
    view.insertText("A clear thought", replacementRange: NSRange(location: 0, length: 0))
    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    view.setSelectedRange(NSRange(location: 2, length: 13))
    controller.wrap("**", placeholder: "text")
    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    XCTAssertEqual(note.markdown, "A **clear thought**")
    let undo = try XCTUnwrap(view.undoManager)
    undo.undo()
    XCTAssertEqual(note.markdown, "A clear thought")
    undo.undo()
    XCTAssertEqual(note.markdown, "")
    undo.redo()
    undo.redo()
    XCTAssertEqual(note.markdown, "A **clear thought**")
  }

  func testSharedComposerKeepsFocusBindingAndUndo() throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = WorkspaceStore(fileURL: directory.appending(path: "workspace.json"))
    store.replaceWorkspace(Workspace())
    let host = NSHostingView(rootView: ScratchpadView().environmentObject(store))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 660, height: 460), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.contentView = host
    defer { window.contentView = nil }
    host.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.03))
    func find(_ view: NSView) -> NoteTextView? {
      (view as? NoteTextView) ?? view.subviews.lazy.compactMap(find).first
    }
    let editor = try XCTUnwrap(find(host))
    window.makeFirstResponder(editor)
    let original = editor.string
    editor.insertText(
      "**Focus** and $x^2$",
      replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
    XCTAssertEqual(store.scratchpad, "**Focus** and $x^2$")
    XCTAssertNotNil(editor.textLayoutManager)
    let undo = try XCTUnwrap(editor.undoManager)
    XCTAssertTrue(undo.canUndo)
    undo.undo()
    XCTAssertEqual(store.scratchpad, original)
    store.saveNow()
  }

  func testCompactLiveEditorInBothThemes() throws {
    _ = NSApplication.shared
    for dark in [false, true] {
      let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: directory) }
      let store = WorkspaceStore(fileURL: directory.appending(path: "workspace.json"))
      var workspace = WorkspaceStore.sampleWorkspace()
      workspace.preferences.appearance = dark ? .dark : .light
      store.replaceWorkspace(workspace)
      let source =
        "## A little clarity\n\nIdeas become **useful** when we write them down.\n- [ ] Review today's examples\n- [x] Collect the key ideas\n\nEnergy is $E = mc^2$ and a ratio is $\\frac{a}{b}$.\n\n$$\nx = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}\n$$\n\n> Leave room to explore.\n\n`let ideas = []`\n"
      let id = store.createNote(title: "Thinking on paper", markdown: source)
      let host = NSHostingView(
        rootView: RootView(initialSection: .notes).environmentObject(store).environment(
          \.colorScheme, dark ? .dark : .light))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1040, height: 740), styleMask: [.titled],
        backing: .buffered, defer: false)
      window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
      window.isReleasedWhenClosed = false
      window.contentView = host
      window.makeKeyAndOrderFront(nil)
      defer { window.close() }
      RunLoop.current.run(until: Date().addingTimeInterval(0.15))
      host.layoutSubtreeIfNeeded()
      func editor(_ view: NSView) -> NoteTextView? {
        (view as? NoteTextView) ?? view.subviews.lazy.compactMap(editor).first
      }
      let text = try XCTUnwrap(editor(host))
      text.setSelectedRange(NSRange(location: text.string.utf16.count, length: 0))
      window.displayIfNeeded()
      let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: rep)
      try rep.representation(using: .png, properties: [:])!.write(
        to: URL(fileURLWithPath: "/tmp/struktur-live-\(dark ? "dark" : "light").png"))
      window.makeFirstResponder(text)
      let manager = try XCTUnwrap(text.textLayoutManager)
      let content = try XCTUnwrap(text.textContentStorage)
      func clickSource(_ offset: Int) throws {
        let start = try XCTUnwrap(
          content.location(content.documentRange.location, offsetBy: offset))
        let end = try XCTUnwrap(content.location(start, offsetBy: 1))
        let range = try XCTUnwrap(NSTextRange(location: start, end: end))
        var frame: CGRect?
        manager.enumerateTextSegments(in: range, type: .standard, options: []) { _, rect, _, _ in
          frame = rect
          return false
        }
        let rect = try XCTUnwrap(frame)
        let local = CGPoint(
          x: rect.midX + text.textContainerOrigin.x, y: rect.midY + text.textContainerOrigin.y)
        let point = text.convert(local, to: nil)
        let event = try XCTUnwrap(
          NSEvent.mouseEvent(
            with: .leftMouseDown, location: point,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1))
        text.mouseDown(with: event)
      }
      let check = (text.string as NSString).range(of: "- [ ]").location
      try clickSource(check)
      XCTAssertTrue(store.note(id)?.markdown.contains("- [x] Review") == true)
      _ = text.toggleChecklist(at: check)
      let math = (text.string as NSString).range(of: "$E").location
      try clickSource(math)
      XCTAssertGreaterThan(text.selectedRange().location, math)
      XCTAssertLessThan(text.selectedRange().location, math + 12)
      XCTAssertNil(text.textStorage?.attribute(.noteVisual, at: math, effectiveRange: nil))
      host.layoutSubtreeIfNeeded()
      window.displayIfNeeded()
      let active = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: active)
      try active.representation(using: .png, properties: [:])!.write(
        to: URL(fileURLWithPath: "/tmp/struktur-live-active-\(dark ? "dark" : "light").png"))
      XCTAssertEqual(store.note(id)?.markdown, source)
      XCTAssertNotNil(text.textLayoutManager)
      store.saveNow()
    }
  }
}
