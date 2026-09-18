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
        if ProcessInfo.processInfo.environment["STRUKTUR_PREVIEW_FIXTURE"] == "notes" {
          let folder = store.createNoteFolder(name: "Study")
          let child = store.createNoteFolder(name: "Design systems", parentID: folder)
          store.createNote(title: "Small ideas", markdown: "A place for thoughts worth keeping.")
          let source = "# A language we share\n\nGood systems make everyday choices **easier**. Keep the useful patterns close, and leave room to explore.\n\n## From today's lecture\n\n- [ ] Review the typography examples\n- [x] Collect three useful references\n\n> Consistency gives us room to focus on what matters.\n\n## Next steps\n\n1. Sketch a small component library\n2. Compare the patterns with our project\n\n[Open the related task](struktur://task/\(store.tasks[0].id))\n\n`spacing = 8`\n"
          let id = store.createNote(folderID: child, title: "Design systems · Week 3", markdown: source)
          let range = (source as NSString).range(of: "everyday choices")
          store.editNote(id) { $0.decorations = [NoteDecoration(location: range.location, length: range.length, color: .gold, highlight: true)] }
          store.updateNoteLibrary { $0.expandedFolderIDs = [folder, child].compactMap { $0 }; $0.folderID = child }
          store.saveNow()
        }

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
          if let keyCode = info["keyCode"] as? Int,
            [6, 36, 48, 53, 123, 124, 125, 126].contains(keyCode)
          {
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
          let hold = info["hold"] as? Bool == true
          DispatchQueue.main.async {
            replayDrag(from: CGPoint(x: x, y: y), to: CGPoint(x: endX, y: endY), hold: hold)
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
        ) { notification in
          let immediate = notification.userInfo?["immediate"] as? Bool == true
          DispatchQueue.main.async {
            if immediate { captureWindow(to: destination) } else { captureIfRequested() }
          }
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
          captureWindow(to: destination)
        }
      }
    #endif
  }

  #if DEBUG
    @MainActor private static func captureWindow(to destination: String) {
      guard
        let window = NSApplication.shared.windows.first(where: {
          $0.contentView != nil && $0.styleMask.contains(.resizable) && !$0.isSheet
        }),
        let view = NSApplication.shared.windows.first(where: {
          $0.isVisible && $0.className.contains("Popover")
        })?.contentView ?? window.attachedSheet?.contentView ?? window.contentView,
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
      else { return }
      view.cacheDisplay(in: view.bounds, to: bitmap)
      if let data = bitmap.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: destination))
        FileHandle.standardOutput.write(
          Data("Snapshot: \(destination); window: \(window.windowNumber)\n".utf8))
      }
    }

    @MainActor private static func replayKey(_ code: UInt16) {
      guard
        let window = NSApplication.shared.modalWindow ?? NSApplication.shared.keyWindow ?? previewTextField()?.window
          ?? NSApplication.shared.windows.first(where: {
            $0.isVisible && $0.styleMask.contains(.resizable)
          })
      else {
        return
      }
      window.makeKeyAndOrderFront(nil)
      NSApplication.shared.activate(ignoringOtherApps: true)
      for type in [NSEvent.EventType.keyDown, .keyUp] {
        let character =
          [
            6: "z", 36: "\r", 48: "\t", 53: "\u{1b}", 123: "\u{f702}", 124: "\u{f703}",
            125: "\u{f701}", 126: "\u{f700}",
          ][Int(code)] ?? ""
        if let event = NSEvent.keyEvent(
          with: type, location: .zero, modifierFlags: code == 6 ? [.command] : [],
          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
          context: nil, characters: character, charactersIgnoringModifiers: character,
          isARepeat: false, keyCode: code)
        {
          window.sendEvent(event)
        }
      }
    }

    @MainActor private static func replayText(_ text: String) {
      var target = previewTextField()?.window ?? NSApplication.shared.modalWindow
        ?? NSApplication.shared.keyWindow
        ?? NSApplication.shared.windows.first(where: {
          $0.isVisible && $0.styleMask.contains(.resizable) && !$0.isSheet
        })
      while let sheet = target?.attachedSheet { target = sheet }
      guard let window = target else { return }
      window.makeKeyAndOrderFront(nil)
      NSApplication.shared.activate(ignoringOtherApps: true)
      if let editor = window.firstResponder as? NSTextView, editor.isEditable {
        editor.selectAll(nil)
        editor.insertText(text, replacementRange: editor.selectedRange())
        return
      }
      func find(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable, !field.isHidden { return field }
        return view.subviews.lazy.compactMap { find(in: $0) }.first
      }
      guard let field = window.contentView.flatMap({ find(in: $0) }) else { return }
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
      var target = window
      while let sheet = target.attachedSheet { target = sheet }
      let location = target.convertPoint(fromScreen: window.convertPoint(toScreen: point))
      for click in 1...count {
        for (index, type) in [NSEvent.EventType.leftMouseDown, .leftMouseUp].enumerated() {
          DispatchQueue.main.asyncAfter(
            deadline: .now() + Double(click) * 0.1 + Double(index) * 0.03
          ) {
            if let event = NSEvent.mouseEvent(
              with: type, location: location, modifierFlags: [],
              timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: target.windowNumber,
              context: nil, eventNumber: 0, clickCount: click, pressure: index == 0 ? 1 : 0)
            {
              NSApplication.shared.postEvent(event, atStart: false)
            }
          }
        }
      }
    }

    @MainActor private static func replayDrag(from start: CGPoint, to finish: CGPoint, hold: Bool) {
      guard
        let window = NSApplication.shared.windows.first(where: {
          $0.styleMask.contains(.resizable) && !$0.isSheet
        }),
        CGRect(origin: .zero, size: window.frame.size).contains(start),
        CGRect(origin: .zero, size: window.frame.size).contains(finish)
      else { return }
      window.makeKeyAndOrderFront(nil)
      NSApplication.shared.activate(ignoringOtherApps: true)
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
      if !hold { enqueue(.leftMouseUp, at: finish, delay: 1.35) }
    }
  #endif
}
