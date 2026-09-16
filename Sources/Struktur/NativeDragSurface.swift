import AppKit
import SwiftUI

/// A small native hit target. Handles first-click drags without fighting scroll-view gestures.
struct NativeDragSurface: NSViewRepresentable {
  var changed: (CGSize) -> Void = { _ in }
  var ended: (CGSize, CGPoint) -> Void
  var cursor: NSCursor = .openHand

  func makeNSView(context: Context) -> DragView { DragView() }
  func updateNSView(_ view: DragView, context: Context) {
    view.changed = changed
    view.ended = ended
    view.dragCursor = cursor
  }

  final class DragView: NSView {
    var changed: (CGSize) -> Void = { _ in }
    var ended: (CGSize, CGPoint) -> Void = { _, _ in }
    var dragCursor: NSCursor = .openHand
    private var origin: CGPoint?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: dragCursor) }
    override func mouseDown(with event: NSEvent) {
      if origin != nil { cancelOperation(nil) }
      origin = convert(event.locationInWindow, from: nil)
      window?.makeFirstResponder(self)
      NSCursor.closedHand.push()
    }
    override func mouseDragged(with event: NSEvent) {
      guard let origin else { return }
      let current = convert(event.locationInWindow, from: nil)
      changed(CGSize(width: current.x - origin.x, height: current.y - origin.y))
    }
    override func mouseUp(with event: NSEvent) {
      guard let origin else { return }
      let current = convert(event.locationInWindow, from: nil)
      self.origin = nil
      NSCursor.pop()
      ended(CGSize(width: current.x - origin.x, height: current.y - origin.y), current)
    }
    override func cancelOperation(_ sender: Any?) {
      guard origin != nil else { return }
      origin = nil
      NSCursor.pop()
      changed(.zero)
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
      if newWindow == nil { cancelOperation(nil) }
      super.viewWillMove(toWindow: newWindow)
    }
  }
}
