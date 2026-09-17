import AppKit
import SwiftUI

/// A small native hit target. Handles first-click drags without fighting scroll-view gestures.
struct NativeDragSurface: NSViewRepresentable {
  var began: (CGPoint) -> Void = { _ in }
  var changed: (CGSize) -> Void = { _ in }
  var ended: (CGSize, CGPoint) -> Void
  var cancelled: () -> Void = {}
  var cursor: NSCursor = .openHand

  func makeNSView(context: Context) -> DragView { DragView() }
  func updateNSView(_ view: DragView, context: Context) {
    view.began = began
    view.changed = changed
    view.ended = ended
    view.cancelled = cancelled
    view.dragCursor = cursor
  }

  final class DragView: NSView {
    var began: (CGPoint) -> Void = { _ in }
    var changed: (CGSize) -> Void = { _ in }
    var ended: (CGSize, CGPoint) -> Void = { _, _ in }
    var cancelled: () -> Void = {}
    var dragCursor: NSCursor = .openHand
    private var origin: CGPoint?
    private var localOrigin = CGPoint.zero
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: dragCursor) }
    override func mouseDown(with event: NSEvent) {
      if origin != nil { cancelOperation(nil) }
      // Window coordinates remain stable when SwiftUI moves or resizes this view.
      origin = event.locationInWindow
      localOrigin = convert(event.locationInWindow, from: nil)
      window?.makeFirstResponder(self)
      (dragCursor == .openHand ? NSCursor.closedHand : dragCursor).push()
      began(localOrigin)
    }
    override func mouseDragged(with event: NSEvent) {
      guard let origin else { return }
      changed(Self.translation(from: origin, to: event.locationInWindow))
    }
    override func mouseUp(with event: NSEvent) {
      guard let origin else { return }
      let delta = Self.translation(from: origin, to: event.locationInWindow)
      self.origin = nil
      NSCursor.pop()
      ended(delta, CGPoint(x: localOrigin.x + delta.width, y: localOrigin.y + delta.height))
    }
    override func cancelOperation(_ sender: Any?) {
      guard origin != nil else { return }
      origin = nil
      NSCursor.pop()
      cancelled()
    }
    override func keyDown(with event: NSEvent) {
      if event.keyCode == 53 { cancelOperation(nil) } else { super.keyDown(with: event) }
    }
    override func resignFirstResponder() -> Bool {
      cancelOperation(nil)
      return super.resignFirstResponder()
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
      if newWindow == nil { cancelOperation(nil) }
      super.viewWillMove(toWindow: newWindow)
    }
    static func translation(from origin: CGPoint, to current: CGPoint) -> CGSize {
      CGSize(width: current.x - origin.x, height: origin.y - current.y)
    }
  }
}
