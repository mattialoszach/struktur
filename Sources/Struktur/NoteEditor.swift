import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@MainActor final class NoteEditorController: ObservableObject {
  weak var textView: NoteTextView?
  @Published private(set) var hasSelection = false
  var selection = NSRange(location: 0, length: 0) {
    didSet {
      if hasSelection != (selection.length > 0) { hasSelection = selection.length > 0 }
    }
  }

  func insert(_ text: String, selectOffset: Int? = nil, selectLength: Int = 0) {
    guard let view = textView else { return }
    let range = view.selectedRange()
    view.window?.makeFirstResponder(view)
    // Toolbar commands are discrete edits, not a continuation of native typing.
    view.breakUndoCoalescing()
    view.insertText(text, replacementRange: range)
    view.breakUndoCoalescing()
    if let offset = selectOffset {
      view.setSelectedRange(NSRange(location: range.location + offset, length: selectLength))
    }
  }
  func wrap(_ marker: String, placeholder: String) {
    guard let view = textView else { return }
    let range = view.selectedRange()
    let value = range.length > 0 ? (view.string as NSString).substring(with: range) : placeholder
    let source = view.string as NSString
    let count = marker.utf16.count
    if range.location >= count, NSMaxRange(range) + count <= source.length,
      source.substring(with: NSRange(location: range.location - count, length: count)) == marker,
      source.substring(with: NSRange(location: NSMaxRange(range), length: count)) == marker
    {
      view.setSelectedRange(
        NSRange(location: range.location - count, length: range.length + count * 2))
      insert(value, selectOffset: 0, selectLength: value.utf16.count)
      return
    }
    insert(
      marker + value + marker, selectOffset: marker.utf16.count, selectLength: value.utf16.count)
  }
  func applyDecorations(_ decorations: [NoteDecoration], store: WorkspaceStore, noteID: UUID) {
    guard let previous = store.note(noteID)?.decorations else { return }
    textView?.undoManager?.registerUndo(withTarget: self) { controller in
      MainActor.assumeIsolated {
        controller.applyDecorations(previous, store: store, noteID: noteID)
      }
    }
    textView?.undoManager?.setActionName("Text color or highlight")
    store.editNote(noteID) { $0.decorations = decorations }
  }
  func block(_ prefix: String) {
    guard let view = textView else { return }
    let range = (view.string as NSString).lineRange(for: view.selectedRange())
    let raw = (view.string as NSString).substring(with: range)
    let value = raw.components(separatedBy: "\n").enumerated().map { index, line in
      if line.isEmpty && index > 0 { return line }
      let content = line.replacingOccurrences(
        of: #"^(?:#{1,6}\s+|>\s?|[-*+] \[(?: |x|X)?\] |[-*+] |\d+\. )"#,
        with: "", options: .regularExpression)
      return (prefix == "1. " ? "\(index + 1). " : prefix) + content
    }.joined(separator: "\n")
    view.setSelectedRange(range)
    insert(value)
  }
}

struct NoteNativeEditor: NSViewRepresentable {
  let note: NoteDocument
  var readOnly: Bool
  var availableWidth: CGFloat
  let controller: NoteEditorController
  var editingEnabled = true
  var acceptsImages = true
  var accessibilityLabel = "Note editor"
  var currentNote: (() -> NoteDocument?)? = nil
  var onText: (NoteDocument) -> Void
  var onImage: (Data, String) -> Void
  var onLink: (URL) -> Void
  @Environment(\.colorScheme) private var colorScheme

  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSScrollView()
    scroll.wantsLayer = true
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = false
    let text = NoteTextView(usingTextLayoutManager: true)
    text.wantsLayer = true
    text.isRichText = false
    text.allowsUndo = true
    text.isAutomaticQuoteSubstitutionEnabled = false
    text.isAutomaticDashSubstitutionEnabled = false
    text.isAutomaticLinkDetectionEnabled = false
    text.isAutomaticTextReplacementEnabled = false
    text.isAutomaticSpellingCorrectionEnabled = false
    text.isAutomaticTextCompletionEnabled = false
    text.writingToolsBehavior = .none
    text.isContinuousSpellCheckingEnabled = true
    text.drawsBackground = false
    text.textContainerInset = NSSize(width: 20, height: 20)
    text.isVerticallyResizable = true
    text.isHorizontallyResizable = false
    text.autoresizingMask = [.width]
    text.textContainer?.widthTracksTextView = true
    text.usesFindBar = true
    text.isIncrementalSearchingEnabled = true
    text.textContainer?.containerSize = NSSize(width: 460, height: CGFloat.greatestFiniteMagnitude)
    text.minSize = .zero
    text.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    text.delegate = context.coordinator
    text.registerForDraggedTypes([.fileURL, .png, .tiff])
    scroll.documentView = text
    updateNSView(scroll, context: context)
    return scroll
  }
  func updateNSView(_ scroll: NSScrollView, context: Context) {
    guard let view = scroll.documentView as? NoteTextView else { return }
    context.coordinator.parent = self
    if !readOnly { controller.textView = view }
    view.imageHandler = readOnly || !acceptsImages ? nil : onImage
    view.isEditable = !readOnly && editingEnabled
    view.isSelectable = readOnly || editingEnabled
    view.setAccessibilityLabel(accessibilityLabel)
    view.setAccessibilityHelp(
      "Live Markdown and LaTeX. Click an equation to edit its source. Command-Return toggles a checklist item."
    )
    let dark = colorScheme == .dark
    view.insertionPointColor = dark ? .white : .black
    context.coordinator.synchronize(view, dark: dark)
  }
  @MainActor
  final class Coordinator: NSObject, NSTextViewDelegate, NSTextLayoutManagerDelegate {
    var parent: NoteNativeEditor
    var lastNote: NoteDocument?
    var lastDark = false
    var lastReadOnly = false
    var lastWidth: CGFloat = 0
    var applying = false
    let styler = NoteWriteStyle()
    var pendingEdit: (range: NSRange, delta: Int)?
    var inheritedAttributes: [NSAttributedString.Key: Any]?
    var multipleEdits = false
    var needsFullStyle = false
    weak var editingView: NoteTextView?
    private weak var observedStorage: NSTextStorage?
    init(_ parent: NoteNativeEditor) {
      self.parent = parent
      super.init()
      for name in [Notification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
        NotificationCenter.default.addObserver(
          self, selector: #selector(undoOrRedo(_:)), name: name, object: nil)
      }
    }

    @objc private func undoOrRedo(_ notification: Notification) {
      guard let view = editingView, let manager = notification.object as? UndoManager,
        manager === view.undoManager, pendingEdit != nil
      else { return }
      // AppKit may finish a text undo without a synchronous textDidChange.
      // Commit it before a SwiftUI update can restore the previous source.
      textDidChange(Notification(name: NSText.didChangeNotification, object: view))
    }

    func synchronize(_ view: NoteTextView, dark: Bool) {
      editingView = view
      view.textLayoutManager?.delegate = self
      if observedStorage !== view.textStorage {
        if let observedStorage {
          NotificationCenter.default.removeObserver(
            self, name: NSTextStorage.willProcessEditingNotification, object: observedStorage)
        }
        observedStorage = view.textStorage
        NotificationCenter.default.addObserver(
          self, selector: #selector(storageWillProcess(_:)),
          name: NSTextStorage.willProcessEditingNotification, object: view.textStorage)
      }
      guard !view.hasMarkedText() else { return }
      // A GeometryReader/environment update can deliver a captured SwiftUI
      // value after native typing has already advanced the canonical document.
      let note = parent.currentNote?() ?? parent.note
      let sameContent =
        lastNote?.id == note.id
        && (lastNote?.markdown as NSString?)?.isEqual(to: note.markdown) == true
        && lastNote?.decorations == note.decorations
        && lastNote?.attachments == note.attachments
      if sameContent, !needsFullStyle, lastDark == dark, lastReadOnly == parent.readOnly {
        if lastWidth != parent.availableWidth, let storage = view.textStorage {
          applying = true
          view.textContentStorage?.performEditingTransaction {
            styler.resize(
              in: storage, note: note, dark: dark, width: max(80, parent.availableWidth - 50))
          }
          resetTypingAttributes(view, dark: dark)
          view.needsDisplay = true
          applying = false
          lastWidth = parent.availableWidth
        }
        return
      }
      applying = true
      defer { applying = false }
      guard let storage = view.textStorage else { return }
      let selection = view.selectedRange()
      let scrollOrigin = view.enclosingScrollView?.contentView.bounds.origin
      if !(view.string as NSString).isEqual(to: note.markdown) {
        // Only external replacements invalidate text undo. Live presentation
        // never replaces, inserts or removes source characters.
        storage.replaceCharacters(
          in: NSRange(location: 0, length: storage.length), with: note.markdown)
        view.undoManager?.removeAllActions()
      }
      styler.apply(
        to: storage, note: note, dark: dark,
        selection: parent.readOnly || (view.window != nil && view.window?.firstResponder !== view)
          ? NSRange(location: NSNotFound, length: 0) : selection,
        width: max(80, parent.availableWidth - 50))
      resetTypingAttributes(view, dark: dark)
      let location = min(selection.location, storage.length)
      view.setSelectedRange(
        NSRange(location: location, length: min(selection.length, storage.length - location)))
      if let scrollOrigin { view.enclosingScrollView?.contentView.scroll(to: scrollOrigin) }
      lastNote = note
      lastDark = dark
      lastWidth = parent.availableWidth
      lastReadOnly = parent.readOnly
      pendingEdit = nil
      multipleEdits = false
      needsFullStyle = false
    }
    private func resetTypingAttributes(_ view: NSTextView, dark: Bool) {
      view.typingAttributes = NoteWriteStyle.attributes(dark: dark)
    }
    @objc private func storageWillProcess(_ notification: Notification) {
      guard !applying, let storage = notification.object as? NSTextStorage,
        storage.editedMask.contains(.editedCharacters)
      else { return }
      // Capture before AppKit fixes paragraph attributes: didProcessEditing's
      // range can include untouched text. A notification preserves TextKit 2's
      // own NSTextContentStorage delegate and its viewport layout updates.
      if pendingEdit != nil { multipleEdits = true }
      pendingEdit = (storage.editedRange, storage.changeInLength)
    }
    func textView(
      _ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
      replacementString: String?
    ) -> Bool {
      inheritedAttributes = nil
      if !textView.hasMarkedText(), lastNote?.decorations.isEmpty == true,
        let replacementString, let storage = textView.textStorage
      {
        inheritedAttributes = styler.inheritedAttributes(
          in: storage, range: affectedCharRange, replacement: replacementString)
      }
      return true
    }
    func textDidChange(_ notification: Notification) {
      guard !applying, let view = notification.object as? NoteTextView,
        let storage = view.textStorage
      else { return }
      var note = lastNote ?? parent.note
      note.replaceMarkdown(
        view.string, editedRange: multipleEdits ? nil : pendingEdit?.range,
        changeInLength: pendingEdit?.delta ?? 0)
      // Persist composition too, but leave its native marked-text attributes
      // untouched. Its accumulated style changes are applied after commit.
      if !view.hasMarkedText() {
        applying = true
        do {
          let range = multipleEdits || needsFullStyle ? nil : pendingEdit?.range
          if let content = view.textContentStorage {
            content.performEditingTransaction {
              styler.apply(
                to: storage, note: note, dark: lastDark, editedRange: range,
                selection: view.selectedRange(), width: max(80, parent.availableWidth - 50),
                inheritedAttributes: multipleEdits || needsFullStyle ? nil : inheritedAttributes)
            }
          } else {
            styler.apply(
              to: storage, note: note, dark: lastDark, editedRange: range,
              selection: view.selectedRange(), width: max(80, parent.availableWidth - 50),
              inheritedAttributes: multipleEdits || needsFullStyle ? nil : inheritedAttributes)
          }
          resetTypingAttributes(view, dark: lastDark)
          view.needsDisplay = true
        }
        applying = false
        needsFullStyle = false
      } else {
        needsFullStyle = true
      }
      lastNote = note
      pendingEdit = nil
      multipleEdits = false
      inheritedAttributes = nil
      parent.onText(note)
    }
    func textViewDidChangeSelection(_ notification: Notification) {
      guard !applying, !parent.readOnly, let view = notification.object as? NSTextView else {
        return
      }
      let range = view.selectedRange()
      if pendingEdit == nil, !view.hasMarkedText(), let storage = view.textStorage,
        let note = lastNote
      {
        applying = true
        view.textContentStorage?.performEditingTransaction {
          styler.select(
            view.window == nil || view.window?.firstResponder === view
              ? range : NSRange(location: NSNotFound, length: 0),
            in: storage, note: note, dark: lastDark,
            width: max(80, parent.availableWidth - 50))
        }
        resetTypingAttributes(view, dark: lastDark)
        applying = false
        view.needsDisplay = true
      }
      let controller = parent.controller
      DispatchQueue.main.async { if controller.selection != range { controller.selection = range } }
    }
    func textDidBeginEditing(_ notification: Notification) {
      if let view = notification.object as? NoteTextView, view.window != nil {
        focusChanged(view, active: true)
      }
    }
    func textDidEndEditing(_ notification: Notification) {
      if let view = notification.object as? NoteTextView, view.window != nil {
        focusChanged(view, active: false)
      }
    }
    func focusChanged(_ view: NoteTextView, active: Bool) {
      guard let storage = view.textStorage,
        let note = lastNote, !view.hasMarkedText()
      else { return }
      applying = true
      view.textContentStorage?.performEditingTransaction {
        styler.select(
          active ? view.selectedRange() : NSRange(location: NSNotFound, length: 0),
          in: storage, note: note, dark: lastDark,
          width: max(80, parent.availableWidth - 50))
      }
      resetTypingAttributes(view, dark: lastDark)
      applying = false
      view.needsDisplay = true
    }
    nonisolated func textLayoutManager(
      _ manager: NSTextLayoutManager,
      textLayoutFragmentFor location: any NSTextLocation, in element: NSTextElement
    ) -> NSTextLayoutFragment {
      if let paragraph = element as? NSTextParagraph, paragraph.attributedString.length > 0,
        paragraph.attributedString.attribute(.noteCustomLayout, at: 0, effectiveRange: nil) != nil
      {
        return NoteLayoutFragment(textElement: element, range: element.elementRange)
      }
      return NSTextLayoutFragment(textElement: element, range: element.elementRange)
    }
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
      if let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:)) {
        parent.onLink(url)
      }
      return true
    }
  }
}

final class NoteTextView: NSTextView {
  var imageHandler: ((Data, String) -> Void)?

  override func becomeFirstResponder() -> Bool {
    let accepted = super.becomeFirstResponder()
    if accepted, window != nil {
      (delegate as? NoteNativeEditor.Coordinator)?.focusChanged(self, active: true)
    }
    return accepted
  }

  override func resignFirstResponder() -> Bool {
    let accepted = super.resignFirstResponder()
    if accepted, window != nil {
      (delegate as? NoteNativeEditor.Coordinator)?.focusChanged(self, active: false)
    }
    return accepted
  }

  override func cancelOperation(_ sender: Any?) {
    window?.makeFirstResponder(window)
  }

  override func paste(_ sender: Any?) {
    if consumeImage(NSPasteboard.general) { return }
    // Keep copied rich text portable by accepting its plain text representation.
    if let text = NSPasteboard.general.string(forType: .string) {
      insertText(text, replacementRange: selectedRange())
    } else {
      super.paste(sender)
    }
  }
  override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    guard imageHandler != nil else { return [] }
    return sender.draggingPasteboard.canReadObject(
      forClasses: [NSURL.self, NSImage.self], options: nil) ? .copy : super.draggingEntered(sender)
  }
  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    if imageHandler != nil {
      let point = convert(sender.draggingLocation, from: nil)
      setSelectedRange(NSRange(location: characterIndexForInsertion(at: point), length: 0))
    }
    if consumeImage(sender.draggingPasteboard) { return true }
    return super.performDragOperation(sender)
  }
  func consumeImage(_ board: NSPasteboard) -> Bool {
    guard let imageHandler else { return false }
    if let urls = board.readObjects(
      forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
      let url = urls.first,
      let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image)
    {
      do {
        imageHandler(try NoteImages.read(url), url.deletingPathExtension().lastPathComponent)
      } catch { imageHandler(Data(), error.localizedDescription) }
      return true
    }
    if let data = board.data(forType: .png) ?? board.data(forType: .tiff) {
      imageHandler(data, "Pasted image")
      return true
    }
    return false
  }
  override func mouseDown(with event: NSEvent) {
    if isEditable, let storage = textStorage, storage.length > 0 {
      let point = convert(event.locationInWindow, from: nil)
      let index = min(characterIndexForInsertion(at: point), storage.length - 1)
      var range = NSRange()
      if let visual = storage.attribute(
        .noteVisualSource, at: index, longestEffectiveRange: &range,
        in: NSRange(location: 0, length: storage.length)) as? NoteInlineVisual
      {
        if visual.kind == .checkbox {
          window?.makeFirstResponder(self)
          toggleChecklist(at: range.location)
          return
        }
        if visual.kind == .math || visual.kind == .image {
          window?.makeFirstResponder(self)
          setSelectedRange(NSRange(location: min(range.location + 1, storage.length), length: 0))
          return
        }
      }
    }
    super.mouseDown(with: event)
  }

  @discardableResult func toggleChecklist(at location: Int? = nil) -> Bool {
    let source = string as NSString
    let line = source.lineRange(
      for: NSRange(location: min(location ?? selectedRange().location, source.length), length: 0))
    let raw = source.substring(with: line)
    guard let item = MarkdownChecklist.item(in: raw) else { return false }
    let marker = NSRange(item.markerRange, in: raw)
    let range = NSRange(location: line.location + marker.location, length: marker.length)
    let selection = selectedRange()
    let replacement = item.isChecked ? "- [ ]" : "- [x]"
    breakUndoCoalescing()
    insertText(replacement, replacementRange: range)
    breakUndoCoalescing()
    let delta = replacement.utf16.count - range.length
    let position =
      selection.location >= NSMaxRange(range) ? selection.location + delta : selection.location
    setSelectedRange(NSRange(location: min(position, (string as NSString).length), length: 0))
    undoManager?.setActionName("Toggle checklist")
    return true
  }

  override func keyDown(with event: NSEvent) {
    if event.modifierFlags.contains(.command), event.keyCode == 36, isEditable, toggleChecklist() {
      return
    }
    if event.modifierFlags.contains(.command), let key = event.charactersIgnoringModifiers,
      ["b", "i"].contains(key), isEditable
    {
      let controller = NoteEditorController()
      controller.textView = self
      controller.wrap(key == "b" ? "**" : "*", placeholder: "text")
      return
    }
    super.keyDown(with: event)
  }
  override func insertNewline(_ sender: Any?) {
    let selection = selectedRange()
    guard selection.length == 0 else {
      super.insertNewline(sender)
      return
    }
    let source = string as NSString
    let lineRange = source.lineRange(for: NSRange(location: selection.location, length: 0))
    let before = source.substring(
      with: NSRange(location: lineRange.location, length: selection.location - lineRange.location))
    let pattern = #"^(\s*)([-*+] \[(?: |x|X)?\] |[-*+] |(\d+)\. )(.*)$"#
    guard
      let match = (try? NSRegularExpression(pattern: pattern))?.firstMatch(
        in: before,
        range: NSRange(location: 0, length: before.utf16.count))
    else {
      super.insertNewline(sender)
      return
    }
    let raw = before as NSString
    if raw.substring(with: match.range(at: 4)).isEmpty {
      insertText(
        "", replacementRange: NSRange(location: lineRange.location, length: before.utf16.count))
      return
    }
    var marker = raw.substring(with: match.range(at: 2))
    if marker.contains("[") { marker = "- [ ] " }
    if match.range(at: 3).location != NSNotFound,
      let number = Int(raw.substring(with: match.range(at: 3))), number < Int.max
    {
      marker = "\(number + 1). "
    }
    insertText("\n" + raw.substring(with: match.range(at: 1)) + marker, replacementRange: selection)
  }
}

@MainActor enum NoteImages {
  static func read(_ url: URL) throws -> Data {
    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard size > 0, size <= 30_000_000 else {
      throw WorkspaceValidationError.invalid("Choose an image smaller than 30 MB.")
    }
    return try Data(contentsOf: url)
  }
  static func attachment(_ data: Data, name: String) throws -> NoteAttachment {
    guard !data.isEmpty, data.count <= 30_000_000,
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: 2000,
        ] as CFDictionary),
      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
      png.count <= 10_000_000
    else {
      throw WorkspaceValidationError.invalid(
        "This image could not be inserted. Choose a PNG, JPEG, HEIC, GIF, or TIFF under 30 MB.")
    }
    return NoteAttachment(name: name, data: png)
  }
}
