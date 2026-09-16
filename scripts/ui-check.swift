// Read or exercise the accessibility tree of an explicitly selected preview process.
// Usage: swift scripts/ui-check.swift <pid> list|press|set [label] [value]
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
if operation == "capture" {
  DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("app.struktur.preview.capture"), object: String(pid), userInfo: nil,
    deliverImmediately: true)
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
  ]
}
if operation == "list" {
  for element in elements {
    let role = string(element, kAXRoleAttribute as CFString)
    if [
      "AXButton", "AXCheckBox", "AXTextField", "AXTextArea", "AXPopUpButton", "AXMenuButton",
      "AXRadioButton", "AXMenuItem",
    ].contains(role) {
      print("\(role): \(names(element).filter { !$0.isEmpty }.joined(separator: " | "))")
    }
  }
} else if operation == "press" {
  guard
    let element = elements.first(where: {
      names($0).contains(label)
        && [
          "AXButton", "AXCheckBox", "AXPopUpButton", "AXMenuButton", "AXRadioButton", "AXMenuItem",
        ].contains(string($0, kAXRoleAttribute as CFString))
    })
  else { fail("No actionable element labeled \(label)") }
  let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
  guard result == .success else { fail("Press failed: \(result)") }
  print("Pressed: \(label)")
} else if operation == "set" {
  guard CommandLine.arguments.count > 4,
    let element = elements.first(where: {
      names($0).contains(label)
        && ["AXTextField", "AXTextArea"].contains(string($0, kAXRoleAttribute as CFString))
    })
  else { fail("No text field labeled \(label)") }
  let result = AXUIElementSetAttributeValue(
    element, kAXValueAttribute as CFString, CommandLine.arguments[4] as CFString)
  guard result == .success else { fail("Set failed: \(result)") }
  print("Set: \(label)")
}
