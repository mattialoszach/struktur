import AppKit
import Combine
import SwiftUI
import XCTest

@testable import Struktur

@MainActor final class NoteResponsivenessTests: XCTestCase {
  func testFullWindowOpeningAndTitleAndBodyTyping() throws {
    _ = NSApplication.shared
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WorkspaceStore(fileURL: folder.appending(path: "workspace.json"))
    store.replaceWorkspace(WorkspaceStore.sampleWorkspace())
    let id = store.createNote(title: "Title", markdown: "")
    store.saveNow()
    let start = ProcessInfo.processInfo.systemUptime
    let host = NSHostingView(rootView: RootView(initialSection: .notes).environmentObject(store))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1040, height: 740),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    defer { window.close() }
    func settle() {
      host.layoutSubtreeIfNeeded()
      RunLoop.current.run(until: Date().addingTimeInterval(0.01))
      window.displayIfNeeded()
    }
    settle()
    print(
      "Full Notes window first layout: \((ProcessInfo.processInfo.systemUptime - start) * 1000)ms")
    func findTitle(_ view: NSView) -> NSTextField? {
      if let field = view as? NSTextField, field.placeholderString == "Untitled note" {
        return field
      }
      return view.subviews.lazy.compactMap(findTitle).first
    }
    let field = try XCTUnwrap(findTitle(host))
    window.makeFirstResponder(field)
    let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
    editor.setSelectedRange(NSRange(location: 5, length: 0))
    var notifications = 0
    let observer = store.objectWillChange.sink { notifications += 1 }
    defer { observer.cancel() }
    var durations: [Double] = []
    for _ in 0..<12 {
      let start = ProcessInfo.processInfo.systemUptime
      editor.insertText("x", replacementRange: editor.selectedRange())
      settle()
      durations.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
    }
    XCTAssertEqual(store.note(id)?.title, "Title" + String(repeating: "x", count: 12))
    XCTAssertEqual(notifications, 0, "Title typing must stay local to its field")
    print("Full Notes title edit + run-loop/layout: p95=\(durations.sorted()[11])ms")
    func findBody(_ view: NSView) -> NoteTextView? {
      (view as? NoteTextView) ?? view.subviews.lazy.compactMap(findBody).first
    }
    let body = try XCTUnwrap(findBody(host))
    window.makeFirstResponder(body)
    durations = []
    for _ in 0..<12 {
      let start = ProcessInfo.processInfo.systemUptime
      let event = try XCTUnwrap(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: [], timestamp: start,
          windowNumber: window.windowNumber, context: nil, characters: "x",
          charactersIgnoringModifiers: "x", isARepeat: false, keyCode: 7))
      window.sendEvent(event)
      settle()
      durations.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
    }
    XCTAssertEqual(store.note(id)?.markdown, String(repeating: "x", count: 12))
    XCTAssertEqual(notifications, 0, "Body typing must not refresh the workspace either")
    print("Full Notes body key + run-loop/layout: p95=\(durations.sorted()[11])ms")
    store.saveNow()
    XCTAssertEqual(notifications, 1, "Pending library/title updates must publish when flushed")
  }

  func testHostedTypingAndDisplayForShortAndSingleParagraphNotes() throws {
    _ = NSApplication.shared
    for (name, source) in [
      ("short", "# A note\n\nSome **bold** text and café 🌿.\n"),
      ("single paragraph", String(repeating: "Some **bold** text and café 🌿. ", count: 1000)),
    ] {
      let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: folder) }
      let store = WorkspaceStore(fileURL: folder.appending(path: "workspace.json"))
      store.replaceWorkspace(Workspace())
      let id = store.createNote(title: "Typing", markdown: source)
      let host = NSHostingView(rootView: NotesPage().environmentObject(store))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1040, height: 740),
        styleMask: [.titled], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = host
      window.orderFront(nil)
      defer { window.close() }
      RunLoop.current.run(until: Date().addingTimeInterval(0.1))
      func find(_ view: NSView) -> NoteTextView? {
        (view as? NoteTextView) ?? view.subviews.lazy.compactMap(find).first
      }
      let text = try XCTUnwrap(find(host))
      XCTAssertNotNil(text.textLayoutManager, "Write must retain TextKit 2 viewport layout")
      window.makeFirstResponder(text)
      text.setSelectedRange(NSRange(location: 0, length: 0))
      var samples: [Double] = []
      for _ in 0..<30 {
        let start = ProcessInfo.processInfo.systemUptime
        let event = try XCTUnwrap(
          NSEvent.keyEvent(
            with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: start, windowNumber: window.windowNumber,
            context: nil, characters: "x", charactersIgnoringModifiers: "x",
            isARepeat: false, keyCode: 7))
        text.keyDown(with: event)
        host.displayIfNeeded()
        samples.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
      }
      XCTAssertEqual(text.string, String(repeating: "x", count: 30) + source)
      XCTAssertEqual(store.note(id)?.markdown, text.string)
      XCTAssertNotNil(text.textLayoutManager, "Typing must not switch back to TextKit 1")
      print(
        "Notes hosted key handling + display (\(name)): p95=\(samples.sorted()[28])ms max=\(samples.max()!)ms"
      )
      store.saveNow()
    }
  }
}
