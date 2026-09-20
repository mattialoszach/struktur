import SwiftUI

@main
struct StrukturApp: App {
  @NSApplicationDelegateAdaptor(StrukturApplicationDelegate.self) private var delegate
  @StateObject private var store = WorkspaceStore.forLaunch()

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(store)
        .preferredColorScheme(store.preferences.appearance.colorScheme)
        .frame(minWidth: 1040, minHeight: 700)
        .onAppear {
          delegate.store = store
          PreviewSupport.captureIfRequested()
          #if DEBUG
            AppleQARunner.runIfRequested()
          #endif
        }
    }
    .windowStyle(.hiddenTitleBar)
    .windowToolbarStyle(.unifiedCompact(showsTitle: false))
    .defaultSize(width: 1460, height: 980)
    .commands {
      StrukturCommands()
    }

    Settings {
      PreferencesView()
        .environmentObject(store)
        .preferredColorScheme(store.preferences.appearance.colorScheme)
        .frame(width: 820, height: 660)
    }
  }
}

struct StrukturCommands: Commands {
  @FocusedValue(\.showQuickCapture) private var showQuickCapture
  @FocusedValue(\.navigateToday) private var navigateToday
  @FocusedValue(\.createNote) private var createNote
  @FocusedValue(\.toggleAssistant) private var toggleAssistant

  var body: some Commands {
    CommandGroup(replacing: .newItem) {
      Button("New task") { showQuickCapture?(.task) }
        .keyboardShortcut("n", modifiers: [.command])
      Button("New note") { createNote?() }
        .keyboardShortcut("n", modifiers: [.command, .option])
      Button("New event") { showQuickCapture?(.event) }
        .keyboardShortcut("n", modifiers: [.command, .shift])
    }
    CommandMenu("Navigate") {
      Button("Today") { navigateToday?() }
        .keyboardShortcut("t", modifiers: [.command])
    }
    CommandMenu("Assistant") {
      Button("Ask Struktur") { toggleAssistant?() }
        .keyboardShortcut("j", modifiers: [.command])
        .disabled(toggleAssistant == nil)
    }
  }
}

@MainActor
final class StrukturApplicationDelegate: NSObject, NSApplicationDelegate {
  var store: WorkspaceStore?
  func applicationWillTerminate(_ notification: Notification) { store?.saveNow() }
}

enum QuickCaptureKind { case task, event }

private struct ShowQuickCaptureKey: FocusedValueKey {
  typealias Value = (QuickCaptureKind) -> Void
}

private struct CreateNoteKey: FocusedValueKey {
  typealias Value = () -> Void
}

private struct NavigateTodayKey: FocusedValueKey {
  typealias Value = () -> Void
}

private struct ToggleAssistantKey: FocusedValueKey {
  typealias Value = () -> Void
}

extension FocusedValues {
  var toggleAssistant: (() -> Void)? {
    get { self[ToggleAssistantKey.self] }
    set { self[ToggleAssistantKey.self] = newValue }
  }
  var createNote: (() -> Void)? {
    get { self[CreateNoteKey.self] }
    set { self[CreateNoteKey.self] = newValue }
  }
  var showQuickCapture: ((QuickCaptureKind) -> Void)? {
    get { self[ShowQuickCaptureKey.self] }
    set { self[ShowQuickCaptureKey.self] = newValue }
  }
  var navigateToday: (() -> Void)? {
    get { self[NavigateTodayKey.self] }
    set { self[NavigateTodayKey.self] = newValue }
  }
}
