import SwiftUI

/// Keeps transient pointer movement local to the overlay, away from the page underneath.
struct AssistantPanelHost: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @EnvironmentObject private var store: WorkspaceStore
  @ObservedObject var session: AssistantSession
  let anchor: Date
  let size: CGSize
  let close: () -> Void
  @State private var dragX: CGFloat = 0

  private var position: AssistantPanelPosition {
    (store.preferences.assistant ?? AssistantPreferences()).position
  }

  var body: some View {
    let width = min(424, max(0, size.width - 24))
    let center = position.centerX(in: size.width, panelWidth: width)
    AssistantPanel(session: session, anchor: anchor, position: position,
      close: close, moveChanged: { delta in
        // Follow the pointer exactly; only settling into a position is animated.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
          dragX = position.draggedCenterX(delta.width, in: size.width, panelWidth: width) - center
        }
      }, moveEnded: { delta in
        settle(at: position.destination(after: delta.width, in: size.width, panelWidth: width))
      }, moveCancelled: { settle(at: position) }, moveTo: settle)
      .frame(width: width, height: max(0, size.height - 24))
      .position(x: center + dragX, y: size.height / 2)
      .onChange(of: size) { _, _ in dragX = 0 }
  }

  private func settle(at destination: AssistantPanelPosition) {
    // Commit and clear the live offset in one transaction, including same-position
    // drops and Escape. Separate transactions make the panel jump on release.
    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
      dragX = 0
      if destination != position {
        store.updatePreferences {
          var settings = $0.assistant ?? AssistantPreferences()
          settings.position = destination
          $0.assistant = settings
        }
      }
    }
  }
}
