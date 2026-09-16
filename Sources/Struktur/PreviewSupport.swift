import AppKit
import SwiftUI

extension WorkspaceStore {
  static func forLaunch() -> WorkspaceStore {
    #if DEBUG
      if ProcessInfo.processInfo.environment["STRUKTUR_PREVIEW"] == "1" {
        let directory = FileManager.default.temporaryDirectory.appending(
          path: "struktur-preview-\(UUID().uuidString)")
        let store = WorkspaceStore(fileURL: directory.appending(path: "workspace.json"))
        var sample = sampleWorkspace()
        sample.preferences.appearance =
          ProcessInfo.processInfo.environment["STRUKTUR_THEME"] == "dark" ? .dark : .light
        sample.preferences.widgetLayout = WidgetConfiguration.starterLayout
        store.replaceWorkspace(sample)
        return store
      }
    #endif
    return WorkspaceStore()
  }
}

enum PreviewSupport {
  @MainActor private static var observer: NSObjectProtocol?
  @MainActor static func captureIfRequested() {
    #if DEBUG
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
}
