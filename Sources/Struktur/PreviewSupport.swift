import AppKit
import SwiftUI

extension WorkspaceStore {
  static func forLaunch() -> WorkspaceStore {
    #if DEBUG
      if ProcessInfo.processInfo.environment["STRUKTUR_PREVIEW"] == "1" {
        let requested = ProcessInfo.processInfo.environment["STRUKTUR_PREVIEW_ID"] ?? ""
        let identifier =
          requested.range(of: #"^[A-Za-z0-9-]{1,80}$"#, options: .regularExpression) != nil
          ? requested : UUID().uuidString
        let directory = FileManager.default.temporaryDirectory.appending(
          path: "struktur-preview-\(identifier)")
        let workspaceURL = directory.appending(path: "workspace.json")
        let existed = FileManager.default.fileExists(atPath: workspaceURL.path)
        let store = WorkspaceStore(fileURL: directory.appending(path: "workspace.json"))
        if existed {
          FileHandle.standardOutput.write(
            Data(
              "Restored preview PID: \(ProcessInfo.processInfo.processIdentifier); workspace: \(workspaceURL.path)\n"
                .utf8))
          return store
        }
        var sample = sampleWorkspace()
        sample.preferences.appearance =
          ProcessInfo.processInfo.environment["STRUKTUR_THEME"] == "dark" ? .dark : .light
        sample.preferences.widgetLayout = WidgetConfiguration.starterLayout
        if ProcessInfo.processInfo.environment["STRUKTUR_PREVIEW_FIXTURE"] == "completion" {
          let anchor = Date().setting(hour: 9)
          sample.calendarEntries.append(
            CalendarEntry(
              title: "Weekly lecture QA", start: anchor,
              end: anchor.addingTimeInterval(3600), kind: .lecture,
              projectID: sample.projects.first?.id, recurrence: CalendarRecurrence()))
          sample.goals = [
            TrackedGoal(title: "Five small steps", projectIDs: sample.projects.prefix(1).map(\.id))
          ]
        }
        store.replaceWorkspace(sample)
        FileHandle.standardOutput.write(
          Data(
            "Preview PID: \(ProcessInfo.processInfo.processIdentifier); workspace: \(directory.appending(path: "workspace.json").path)\n"
              .utf8))
        return store
      }
    #endif
    return WorkspaceStore()
  }
}

enum PreviewSupport {
  @MainActor private static var observer: NSObjectProtocol?
  @MainActor private static var eventObserver: Any?
  @MainActor private static var replayObserver: NSObjectProtocol?
  @MainActor static func captureIfRequested() {
    #if DEBUG
      if replayObserver == nil && ProcessInfo.processInfo.environment["STRUKTUR_PREVIEW"] == "1" {
        replayObserver = DistributedNotificationCenter.default().addObserver(
          forName: Notification.Name("app.struktur.preview.replay"),
          object: String(ProcessInfo.processInfo.processIdentifier), queue: .main
        ) { notification in
          let info = notification.userInfo ?? [:]
          if let text = info["text"] as? String {
            DispatchQueue.main.async { replayText(text) }
            return
          }
          if let keyCode = info["keyCode"] as? Int, [36, 48, 53].contains(keyCode) {
            DispatchQueue.main.async { replayKey(UInt16(keyCode)) }
            return
          }
          if let x = info["x"] as? Double, let y = info["y"] as? Double,
            let clicks = info["clickCount"] as? Int, (1...2).contains(clicks)
          {
            DispatchQueue.main.async { replayClick(at: CGPoint(x: x, y: y), count: clicks) }
            return
          }
          guard let x = info["x"] as? Double, let y = info["y"] as? Double,
            let endX = info["endX"] as? Double, let endY = info["endY"] as? Double
          else { return }
          DispatchQueue.main.async {
            replayDrag(from: CGPoint(x: x, y: y), to: CGPoint(x: endX, y: endY))
          }
        }
      }
      if eventObserver == nil
        && ProcessInfo.processInfo.environment["STRUKTUR_PREVIEW_EVENTS"] == "1"
      {
        eventObserver = NSEvent.addLocalMonitorForEvents(matching: [
          .leftMouseDown, .leftMouseDragged, .leftMouseUp,
        ]) { event in
          FileHandle.standardOutput.write(
            Data(
              "Pointer \(event.type.rawValue) at \(event.locationInWindow), window \(event.windowNumber)\n"
                .utf8))
          return event
        }
      }
      guard let destination = ProcessInfo.processInfo.environment["STRUKTUR_SNAPSHOT"] else {
        return
      }
      if observer == nil {
        observer = DistributedNotificationCenter.default().addObserver(
          forName: Notification.Name("app.struktur.preview.capture"),
          object: String(ProcessInfo.processInfo.processIdentifier), queue: .main
        ) { _ in
          DispatchQueue.main.async { captureIfRequested() }
        }
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        guard
          let window = NSApplication.shared.windows.first(where: {
            $0.contentView != nil && $0.styleMask.contains(.resizable) && !$0.isSheet
          })
        else { return }
        let width = Double(ProcessInfo.processInfo.environment["STRUKTUR_WIDTH"] ?? "") ?? 1460
        let height = Double(ProcessInfo.processInfo.environment["STRUKTUR_HEIGHT"] ?? "") ?? 980
        window.setContentSize(NSSize(width: width, height: height))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
          guard let view = window.attachedSheet?.contentView ?? window.contentView,
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
          else { return }
          view.cacheDisplay(in: view.bounds, to: bitmap)
          if let data = bitmap.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: destination))
            FileHandle.standardOutput.write(
              Data("Snapshot: \(destination); window: \(window.windowNumber)\n".utf8))
          }
        }
      }
    #endif
  }

  #if DEBUG
    @MainActor private static func replayKey(_ code: UInt16) {
      guard let window = previewTextField()?.window ?? NSApplication.shared.keyWindow else {
        return
      }
      for type in [NSEvent.EventType.keyDown, .keyUp] {
        let character = code == 36 ? "\r" : (code == 48 ? "\t" : "\u{1b}")
        if let event = NSEvent.keyEvent(
          with: type, location: .zero, modifierFlags: [],
          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
          context: nil, characters: character, charactersIgnoringModifiers: character,
          isARepeat: false, keyCode: code)
        {
          window.sendEvent(event)
        }
      }
    }

    @MainActor private static func replayText(_ text: String) {
      guard let field = previewTextField() else { return }
      field.selectText(nil)
      guard let editor = field.currentEditor() as? NSTextView else { return }
      editor.selectAll(nil)
      editor.insertText(text, replacementRange: editor.selectedRange())
    }

    @MainActor private static func previewTextField() -> NSTextField? {
      func find(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable,
          field.placeholderString == "Wording"
        {
          return field
        }
        return view.subviews.lazy.compactMap { find(in: $0) }.first
      }
      return NSApplication.shared.windows.filter(\.isVisible).lazy.compactMap {
        $0.contentView.flatMap { find(in: $0) }
      }.first
    }

    @MainActor private static func replayClick(at point: CGPoint, count: Int) {
      guard
        let window = NSApplication.shared.windows.first(where: {
          $0.styleMask.contains(.resizable) && !$0.isSheet
        }), CGRect(origin: .zero, size: window.frame.size).contains(point)
      else { return }
      window.makeKeyAndOrderFront(nil)
      NSApplication.shared.activate(ignoringOtherApps: true)
      for click in 1...count {
        for (index, type) in [NSEvent.EventType.leftMouseDown, .leftMouseUp].enumerated() {
          DispatchQueue.main.asyncAfter(
            deadline: .now() + Double(click) * 0.1 + Double(index) * 0.03
          ) {
            if let event = NSEvent.mouseEvent(
              with: type, location: point, modifierFlags: [],
              timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
              context: nil, eventNumber: 0, clickCount: click, pressure: index == 0 ? 1 : 0)
            {
              NSApplication.shared.postEvent(event, atStart: false)
            }
          }
        }
      }
    }

    @MainActor private static func replayDrag(from start: CGPoint, to finish: CGPoint) {
      guard
        let window = NSApplication.shared.windows.first(where: {
          $0.styleMask.contains(.resizable) && !$0.isSheet
        }),
        CGRect(origin: .zero, size: window.frame.size).contains(start),
        CGRect(origin: .zero, size: window.frame.size).contains(finish)
      else { return }
      window.makeKeyAndOrderFront(nil)
      func enqueue(_ type: NSEvent.EventType, at point: CGPoint, delay: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
          guard
            let event = NSEvent.mouseEvent(
              with: type, location: point, modifierFlags: [],
              timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
              context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)
          else { return }
          NSApplication.shared.postEvent(event, atStart: false)
        }
      }
      enqueue(.leftMouseDown, at: start, delay: 0.1)
      for step in 1...40 {
        let t = CGFloat(step) / 40
        enqueue(
          .leftMouseDragged,
          at: CGPoint(x: start.x + (finish.x - start.x) * t, y: start.y + (finish.y - start.y) * t),
          delay: 0.25 + Double(step) * 0.025)
      }
      enqueue(.leftMouseUp, at: finish, delay: 1.35)
    }
  #endif
}
