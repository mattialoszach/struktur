import AppKit
import XCTest

@testable import Struktur

@MainActor
final class WidgetInteractionTests: XCTestCase {
  func testShortMonthCalendarScrollsInsteadOfCollapsingDateRows() {
    for rows in [4, 5, 6] {
      for height: CGFloat in [0, 40, 100, 196, 408, 620] {
        let rowHeight = MonthCalendarGeometry.rowHeight(availableHeight: height, rows: rows)
        XCTAssertGreaterThanOrEqual(rowHeight, 64)
        XCTAssertGreaterThanOrEqual(rowHeight * CGFloat(rows), height)
      }
    }
    XCTAssertEqual(MonthCalendarGeometry.rowHeight(availableHeight: 600, rows: 5), 120)
  }

  func testLiveResizeTracksPixelsAndKeepsItsTopLeftCorner() {
    let start = WidgetGridGeometry.frames(width: 1100, sizes: [(1, 1)])[0]
    for step in 1...100 {
      let delta = CGSize(width: CGFloat(step) * 1.25, height: CGFloat(step) * 0.75)
      let live = WidgetGridGeometry.liveResizeFrame(start: start, width: 1100, translation: delta)
      XCTAssertEqual(live.origin, start.origin)
      XCTAssertEqual(live.width, start.width + delta.width, accuracy: 0.001)
      XCTAssertEqual(live.height, start.height + delta.height, accuracy: 0.001)
    }
  }

  func testLiveResizeReservesSpaceForEveryIntermediateCalendarSize() {
    let sizes = [(2, 2), (1, 2), (1, 1), (1, 1), (2, 1), (1, 1), (4, 3)]
    for width: CGFloat in [700, 800, 1040, 1400] {
      let original = WidgetGridGeometry.frames(width: width, sizes: sizes)
      for index in sizes.indices {
        for step in stride(from: -250, through: 450, by: 25) {
          let live = WidgetGridGeometry.liveResizeFrame(
            start: original[index], width: width,
            translation: CGSize(width: CGFloat(step), height: CGFloat(step)))
          let frames = WidgetGridGeometry.frames(
            width: width, sizes: sizes, liveResize: (index, live))
          XCTAssertEqual(frames[index], live)
          for (i, frame) in frames.enumerated() {
            XCTAssertGreaterThan(frame.width, 0)
            XCTAssertLessThanOrEqual(frame.maxX, width + 0.01)
            for other in frames.dropFirst(i + 1) {
              XCTAssertFalse(
                frame.intersects(other), "Overlap at width \(width), step \(step), widget \(index)")
              XCTAssertFalse(frame.intersects(other.insetBy(dx: -15.9, dy: -15.9)))
            }
          }
        }
      }
    }
  }

  func testResizeClampsAtCanvasEdgesAndSupportedHeights() {
    let frames = WidgetGridGeometry.frames(width: 1100, sizes: [(1, 1), (1, 1), (1, 1), (1, 1)])
    let start = frames[3]
    let large = WidgetGridGeometry.liveResizeFrame(
      start: start, width: 1100, translation: CGSize(width: 10000, height: 10000))
    XCTAssertEqual(large.maxX, 1100, accuracy: 0.001)
    XCTAssertEqual(large.origin, start.origin)
    XCTAssertEqual(large.height, 620)
    let small = WidgetGridGeometry.liveResizeFrame(
      start: start, width: 1100, translation: CGSize(width: -10000, height: -10000))
    XCTAssertEqual(small, start)
  }

  func testVerticalResizePreservesFullWidthPreferenceInCompactWindow() {
    let widget = WidgetConfiguration(kind: .dayFlow, columns: 4, rows: 2)
    let start = WidgetGridGeometry.frames(width: 700, sizes: [(4, 2)])[0]
    var gesture = WidgetInteraction(
      id: widget.id, resizing: true, startFrame: start, anchor: .zero, originalFrames: [start],
      originalIDs: [widget.id])
    gesture.translation = CGSize(width: 0, height: 212)
    let vertical = gesture.finalSize(of: widget, width: 700)
    XCTAssertEqual(vertical.columns, 4)
    XCTAssertEqual(vertical.rows, 3)
    gesture.translation = CGSize(width: -20, height: 212)
    XCTAssertEqual(gesture.finalSize(of: widget, width: 700).columns, 4)
    gesture.translation = CGSize(width: -358, height: -212)
    let narrower = gesture.finalSize(of: widget, width: 700)
    XCTAssertEqual(narrower.columns, 1)
    XCTAssertEqual(narrower.rows, 1)
  }

  func testMovingCardFollowsPointerWhilePreviewOrderChanges() {
    let widgets = [
      WidgetConfiguration(kind: .dayFlow), WidgetConfiguration(kind: .tasks),
      WidgetConfiguration(kind: .focus),
    ]
    let frames = WidgetGridGeometry.frames(
      width: 1100, sizes: widgets.map { ($0.columns, $0.rows) })
    var gesture = WidgetInteraction(
      id: widgets[0].id, resizing: false, startFrame: frames[0], anchor: CGPoint(x: 40, y: 20),
      originalFrames: frames, originalIDs: widgets.map(\.id))
    XCTAssertEqual(gesture.reordered(widgets), widgets)
    gesture.translation = CGSize(width: frames[2].minX, height: 5)
    XCTAssertEqual(gesture.moveFrame.minX, frames[2].minX)
    XCTAssertEqual(gesture.moveFrame.minY, 5)
    XCTAssertEqual(
      gesture.reordered(widgets).map(\.id), [widgets[1].id, widgets[2].id, widgets[0].id])
    // Repeated events in the same location must not make neighboring cards oscillate.
    XCTAssertEqual(gesture.targetIndex, 2)
    XCTAssertEqual(gesture.reordered(widgets).last, widgets[0])
    gesture.translation = .zero
    XCTAssertEqual(gesture.reordered(widgets), widgets)
  }

  func testDropInGutterAndBeyondLastRowHasDestination() {
    let frames = WidgetGridGeometry.frames(width: 700, sizes: [(1, 1), (1, 1), (2, 1)])
    XCTAssertEqual(
      WidgetGridGeometry.dropIndex(at: CGPoint(x: frames[1].minX - 3, y: 30), frames: frames), 1)
    XCTAssertEqual(WidgetGridGeometry.dropIndex(at: CGPoint(x: 300, y: 900), frames: frames), 2)
    XCTAssertNil(WidgetGridGeometry.dropIndex(at: .zero, frames: []))
  }

  func testNativeDragRemainsStableWhenItsViewMovesAndEscapeCancels() throws {
    let view = NativeDragSurface.DragView(frame: CGRect(x: 20, y: 20, width: 100, height: 30))
    var translations: [CGSize] = []
    var cancelled = false
    var committed = false
    view.changed = { translations.append($0) }
    view.cancelled = { cancelled = true }
    view.ended = { _, _ in committed = true }
    func event(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) throws -> NSEvent {
      try XCTUnwrap(
        NSEvent.mouseEvent(
          with: type, location: CGPoint(x: x, y: y), modifierFlags: [], timestamp: 0,
          windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }
    view.mouseDown(with: try event(.leftMouseDown, 50, 100))
    view.mouseDragged(with: try event(.leftMouseDragged, 90, 80))
    view.frame.origin = CGPoint(x: 60, y: 40)
    view.frame.size.width = 160
    view.mouseDragged(with: try event(.leftMouseDragged, 110, 65))
    XCTAssertEqual(translations, [CGSize(width: 40, height: 20), CGSize(width: 60, height: 35)])
    view.keyDown(
      with: try XCTUnwrap(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
          context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
          isARepeat: false, keyCode: 53)))
    view.mouseUp(with: try event(.leftMouseUp, 110, 65))
    XCTAssertTrue(cancelled)
    XCTAssertFalse(committed)
  }
}
