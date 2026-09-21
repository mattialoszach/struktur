import AppKit
import SwiftUI

struct AssistantLauncher: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hovering = false
  var isOpen: Bool
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 7) {
        Image(systemName: "sparkles")
          .rotationEffect(.degrees(hovering && !reduceMotion ? -12 : 0))
          .scaleEffect(hovering && !reduceMotion ? 1.12 : 1)
        Text("Assistant")
        Text("⌘ J").font(.system(size: 9)).padding(3)
          .background(StrukturTheme.hairline.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
      }
      .foregroundStyle(hovering || isOpen ? StrukturTheme.ink : StrukturTheme.muted)
      .padding(.horizontal, 9).padding(.vertical, 6)
      .background {
        RoundedRectangle(cornerRadius: 8)
          .fill(LinearGradient(colors: [StrukturTheme.lavender, StrukturTheme.peach, StrukturTheme.mint],
            startPoint: hovering ? .topLeading : .leading, endPoint: .bottomTrailing))
          .opacity(hovering ? 1 : (isOpen ? 0.7 : 0))
      }
      .overlay {
        RoundedRectangle(cornerRadius: 8).strokeBorder(
          LinearGradient(colors: [AccentToken.lilac.color, AccentToken.peach.color, AccentToken.mint.color],
            startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
          .opacity(hovering ? 0.7 : 0)
      }
      .shadow(color: StrukturTheme.lavender.opacity(hovering ? 0.6 : 0), radius: 7)
      .contentShape(RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain).onHover { hovering = $0 }
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: hovering)
    .help("Assistant · ⌘ J").accessibilityLabel("Assistant").accessibilityIdentifier("assistant.launcher")
  }
}

struct AssistantComposer: NSViewRepresentable {
  @Binding var text: String
  @Binding var focused: Bool
  var isEnabled: Bool
  var send: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSScrollView()
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    let view = AssistantTextView(frame: .zero)
    view.isRichText = false
    view.drawsBackground = false
    view.font = .systemFont(ofSize: 13)
    view.textContainerInset = NSSize(width: 0, height: 4)
    view.textContainer?.lineFragmentPadding = 0
    view.isVerticallyResizable = true
    view.isHorizontallyResizable = false
    view.autoresizingMask = [.width]
    view.textContainer?.widthTracksTextView = true
    view.delegate = context.coordinator
    view.setAccessibilityLabel("Message assistant")
    view.setAccessibilityIdentifier("assistant.composer")
    scroll.documentView = view
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    guard let view = scroll.documentView as? AssistantTextView else { return }
    context.coordinator.parent = self
    view.send = send
    view.isEditable = isEnabled
    view.textColor = NSColor(StrukturTheme.ink)
    view.insertionPointColor = NSColor(StrukturTheme.ink)
    if view.string != text, !view.hasMarkedText() { view.string = text }
    if focused && isEnabled {
      DispatchQueue.main.async { [weak view] in
        guard let view, view.window?.firstResponder !== view else { return }
        view.window?.makeFirstResponder(view)
      }
    }
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: AssistantComposer
    init(_ parent: AssistantComposer) { self.parent = parent }
    func textDidChange(_ notification: Notification) {
      guard let view = notification.object as? NSTextView else { return }
      parent.text = view.string
    }
    func textDidBeginEditing(_ notification: Notification) { parent.focused = true }
    func textDidEndEditing(_ notification: Notification) { parent.focused = false }
  }
}

final class AssistantTextView: NSTextView {
  var send: (() -> Void)?
  override func keyDown(with event: NSEvent) {
    if [36, 76].contains(event.keyCode), !hasMarkedText(),
      event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
      if isEditable { send?() }
      return
    }
    super.keyDown(with: event)
  }
}
