// Read or exercise the accessibility tree of an explicitly selected preview process.
// Usage: swift scripts/ui-check.swift <pid> <operation> [label] [value]
// Operations: list, press, set, frames, scroll, drag, resize, adjust, capture,
// replay-drag, replay-resize, replay-hold-drag, replay-hold-resize (Escape cancels), capture-now,
// replay-click, replay-double-click, replay-key (return/escape/tab/left/right/up/down), replay-text.
import AppKit
import ApplicationServices

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(1)
}
guard CommandLine.arguments.count >= 3, let pid = Int32(CommandLine.arguments[1]),
  let app = NSRunningApplication(processIdentifier: pid),
  app.executableURL?.lastPathComponent == "Struktur"
else {
  fail("Pass the PID of the Struktur preview process.")
}
let operation = CommandLine.arguments[2]
let label = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : ""
if operation.hasPrefix("replay-") && app.executableURL?.path.contains("/.build/") != true {
  fail("Event replay is restricted to debug preview binaries.")
}
if operation == "replay-text" {
  DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("app.struktur.preview.replay"), object: String(pid),
    userInfo: ["text": label], deliverImmediately: true)
  RunLoop.current.run(until: Date().addingTimeInterval(0.5))
  print("Replaced the focused preview editor's text")
  exit(0)
}
if operation == "replay-key" {
  guard
    let code = [
      "return": 36, "tab": 48, "escape": 53, "left": 123, "right": 124,
      "down": 125, "up": 126,
    ][label]
  else {
    fail("Supply return, tab, escape, left, right, up, or down.")
  }
  DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("app.struktur.preview.replay"), object: String(pid),
    userInfo: ["keyCode": code], deliverImmediately: true)
  RunLoop.current.run(until: Date().addingTimeInterval(0.5))
  print("Replayed \(label)")
  exit(0)
}
if operation == "capture" || operation == "capture-now" {
  if operation == "capture-now" { RunLoop.current.run(until: Date().addingTimeInterval(0.4)) }
  DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("app.struktur.preview.capture"), object: String(pid),
    userInfo: ["immediate": operation == "capture-now"],
    deliverImmediately: true)
  if operation == "capture-now" { RunLoop.current.run(until: Date().addingTimeInterval(0.3)) }
  print("Requested preview snapshot for \(pid)")
  exit(0)
}
func value(_ element: AXUIElement, _ key: CFString) -> CFTypeRef? {
  var result: CFTypeRef?
  AXUIElementCopyAttributeValue(element, key, &result)
  return result
}
func string(_ element: AXUIElement, _ key: CFString) -> String {
  value(element, key) as? String ?? ""
}
var elements: [AXUIElement] = []
func collect(_ element: AXUIElement, depth: Int = 0) {
  guard depth < 30, elements.count < 8000 else { return }
  elements.append(element)
  for child in value(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? [] {
    collect(child, depth: depth + 1)
  }
}
let application = AXUIElementCreateApplication(pid)
for window in value(application, kAXWindowsAttribute as CFString) as? [AXUIElement] ?? [] {
  collect(window)
}
func names(_ element: AXUIElement) -> [String] {
  [
    string(element, kAXTitleAttribute as CFString),
    string(element, kAXDescriptionAttribute as CFString),
    string(element, kAXValueAttribute as CFString), string(element, kAXHelpAttribute as CFString),
    string(element, kAXPlaceholderValueAttribute as CFString),
    string(element, kAXIdentifierAttribute as CFString),
  ]
}
func rect(_ element: AXUIElement) -> CGRect? {
  guard let position = value(element, kAXPositionAttribute as CFString),
    let size = value(element, kAXSizeAttribute as CFString),
    CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
  else { return nil }
  var point = CGPoint.zero
  var dimensions = CGSize.zero
  AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point)
  AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &dimensions)
  return CGRect(origin: point, size: dimensions)
}
func named(_ label: String) -> AXUIElement {
  guard let element = elements.last(where: { names($0).contains(label) }) else {
    fail("No element labeled \(label)")
  }
  return element
}
func drag(from: CGPoint, to: CGPoint) {
  guard app.executableURL?.path.contains("/.build/") == true else {
    fail("Pointer smoke tests are restricted to debug preview binaries.")
  }
  let windows = value(application, kAXWindowsAttribute as CFString) as? [AXUIElement] ?? []
  guard windows.contains(where: { rect($0)?.contains(from) == true }),
    windows.contains(where: { rect($0)?.contains(to) == true })
  else {
    fail("Scroll the source and destination into the preview window before dragging.")
  }
  let windowInfo =
    (CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? [])
    .first { info in
      guard info[kCGWindowOwnerPID as String] as? Int32 == pid,
        let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
        let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
      else { return false }
      return frame.contains(from) && (info[kCGWindowLayer as String] as? Int) == 0
    }
  guard windowInfo != nil else { fail("Cannot resolve the preview window.") }
  app.activate()
  if let window = windows.first { AXUIElementPerformAction(window, kAXRaiseAction as CFString) }
  RunLoop.current.run(until: Date().addingTimeInterval(0.3))
  func send(_ kind: CGEventType, _ point: CGPoint) {
    let event = CGEvent(
      mouseEventSource: nil, mouseType: kind, mouseCursorPosition: point, mouseButton: .left)!
    event.setIntegerValueField(.mouseEventClickState, value: 1)
    CGWarpMouseCursorPosition(point)
    event.post(tap: .cghidEventTap)
  }
  send(.mouseMoved, from)
  send(.leftMouseDown, from)
  RunLoop.current.run(until: Date().addingTimeInterval(0.2))
  for step in 1...40 {
    let t = CGFloat(step) / 40
    send(
      .leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
    RunLoop.current.run(until: Date().addingTimeInterval(0.035))
  }
  send(.leftMouseUp, to)
  RunLoop.current.run(until: Date().addingTimeInterval(0.5))
}
if operation == "frames" {
  for element in elements where !names(element).filter({ !$0.isEmpty }).isEmpty {
    if let rect = rect(element) {
      print("\(names(element).filter { !$0.isEmpty }.joined(separator: " | ")): \(rect)")
    }
  }
  exit(0)
}
if operation == "scroll" {
  let bars = elements.filter { string($0, kAXRoleAttribute as CFString) == "AXScrollBar" }
  guard
    let bar = bars.last(where: {
      string($0, kAXOrientationAttribute as CFString) == "AXVerticalOrientation"
    }),
    let fraction = Double(label), (0...1).contains(fraction)
  else { fail("Supply a scroll position from 0 to 1 for the frontmost scroll view.") }
  let result = AXUIElementSetAttributeValue(
    bar, kAXValueAttribute as CFString, NSNumber(value: fraction))
  guard result == .success else { fail("Scroll failed: \(result)") }
  print("Scrolled to \(fraction)")
  exit(0)
}
if operation == "replay-click" || operation == "replay-double-click" {
  guard let frame = rect(named(label)),
    let window = (value(application, kAXWindowsAttribute as CFString) as? [AXUIElement] ?? [])
      .compactMap({ rect($0) }).first(where: { $0.contains(frame) })
  else { fail("The click target must be visible in the preview window.") }
  DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("app.struktur.preview.replay"), object: String(pid),
    userInfo: [
      "x": frame.midX - window.minX, "y": window.maxY - frame.midY,
      "clickCount": operation == "replay-double-click" ? 2 : 1,
    ], deliverImmediately: true)
  RunLoop.current.run(until: Date().addingTimeInterval(0.6))
  print("Replayed \(operation) on \(label)")
  exit(0)
}
if ["drag", "resize", "replay-drag", "replay-resize", "replay-hold-drag", "replay-hold-resize"]
  .contains(operation)
{
  guard let frame = rect(named(label)) else { fail("Element has no screen rectangle.") }
  let start = CGPoint(x: frame.midX, y: frame.midY)
  let finish: CGPoint
  if operation.hasSuffix("drag") {
    guard CommandLine.arguments.count > 4, let target = rect(named(CommandLine.arguments[4])) else {
      fail("Supply a target label.")
    }
    finish = CGPoint(x: target.midX, y: target.midY)
  } else {
    guard CommandLine.arguments.count > 5, let dx = Double(CommandLine.arguments[4]),
      let dy = Double(CommandLine.arguments[5])
    else { fail("Supply dx and dy in screen points.") }
    finish = CGPoint(x: start.x + dx, y: start.y + dy)
  }
  if operation.hasPrefix("replay-") {
    let windows = value(application, kAXWindowsAttribute as CFString) as? [AXUIElement] ?? []
    guard
      let window = windows.compactMap({ rect($0) }).first(where: {
        $0.contains(start) && $0.contains(finish)
      })
    else { fail("Source and destination must be visible.") }
    DistributedNotificationCenter.default().postNotificationName(
      Notification.Name("app.struktur.preview.replay"), object: String(pid),
      userInfo: [
        "x": start.x - window.minX, "y": window.maxY - start.y,
        "endX": finish.x - window.minX, "endY": window.maxY - finish.y,
        "hold": operation.contains("hold"),
      ], deliverImmediately: true)
    RunLoop.current.run(until: Date().addingTimeInterval(2))
  } else {
    drag(from: start, to: finish)
  }
  print("Dragged \(label) from \(start) to \(finish)")
  exit(0)
}
if operation == "adjust" {
  let action = CommandLine.arguments.last == "increment" ? kAXIncrementAction : kAXDecrementAction
  let result = AXUIElementPerformAction(named(label), action as CFString)
  guard result == .success else { fail("Adjustment failed: \(result)") }
  print("Adjusted \(label)")
  exit(0)
}
if operation == "list" {
  for element in elements {
    let role = string(element, kAXRoleAttribute as CFString)
    if [
      "AXButton", "AXCheckBox", "AXTextField", "AXTextArea", "AXPopUpButton", "AXMenuButton",
      "AXRadioButton", "AXMenuItem", "AXLink",
    ].contains(role) {
      print("\(role): \(names(element).filter { !$0.isEmpty }.joined(separator: " | "))")
    }
  }
} else if operation == "press" {
  guard
    let element = elements.last(where: {
      names($0).contains(label)
        && [
          "AXButton", "AXCheckBox", "AXPopUpButton", "AXMenuButton", "AXRadioButton", "AXMenuItem", "AXLink",
        ].contains(string($0, kAXRoleAttribute as CFString))
    })
  else { fail("No actionable element labeled \(label)") }
  let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
  guard result == .success else { fail("Press failed: \(result)") }
  print("Pressed: \(label)")
} else if operation == "set" {
  guard CommandLine.arguments.count > 4,
    let element = elements.last(where: {
      names($0).contains(label)
        && ["AXTextField", "AXTextArea"].contains(string($0, kAXRoleAttribute as CFString))
    })
  else { fail("No text field labeled \(label)") }
  let result = AXUIElementSetAttributeValue(
    element, kAXValueAttribute as CFString, CommandLine.arguments[4] as CFString)
  guard result == .success else { fail("Set failed: \(result)") }
  print("Set: \(label)")
}
