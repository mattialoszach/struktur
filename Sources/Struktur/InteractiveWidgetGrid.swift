import SwiftUI

/// Gesture previews stay local; only the final order or snapped size reaches WorkspaceStore.
struct InteractiveWidgetGrid: View {
  @EnvironmentObject private var store: WorkspaceStore
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Binding var selectedDate: Date
  var customizing: Bool
  var expand: (WidgetConfiguration) -> Void
  @State private var width: CGFloat = 1100
  @State private var interaction: WidgetInteraction?

  private var motion: Animation? { reduceMotion ? nil : .smooth(duration: 0.22) }
  private var orderedWidgets: [WidgetConfiguration] {
    guard let interaction, !interaction.resizing else { return store.widgets }
    return interaction.reordered(store.widgets)
  }
  private var frames: [CGRect] {
    let widgets = orderedWidgets
    let live = interaction.flatMap { value -> (index: Int, frame: CGRect)? in
      guard value.resizing, let index = widgets.firstIndex(where: { $0.id == value.id }) else {
        return nil
      }
      return (index, value.resizeFrame(width: width))
    }
    return WidgetGridGeometry.frames(
      width: width, sizes: widgets.map { ($0.columns, $0.rows) }, liveResize: live)
  }

  var body: some View {
    let positions = Dictionary(uniqueKeysWithValues: zip(orderedWidgets.map(\.id), frames))
    ZStack(alignment: .topLeading) {
      if let interaction, !interaction.resizing, let frame = positions[interaction.id] {
        RoundedRectangle(cornerRadius: 16)
          .fill(StrukturTheme.editingSurface)
          .frame(width: frame.width, height: frame.height)
          .position(x: frame.midX, y: frame.midY)
          .animation(motion, value: frame)
          .allowsHitTesting(false).accessibilityHidden(true)
      }
      ForEach(store.widgets) { widget in
        let active = interaction?.id == widget.id
        let placed = positions[widget.id] ?? .zero
        let rect = active && interaction?.resizing == false ? interaction!.moveFrame : placed
        WidgetShell(
          configuration: widget, selectedDate: $selectedDate, customizing: customizing,
          interacting: active,
          moveBegan: { begin(widget, frame: placed, anchor: $0, resizing: false) },
          moveChanged: update, moveEnded: finish,
          resizeBegan: { begin(widget, frame: placed, anchor: .zero, resizing: true) },
          resizeChanged: update, resizeEnded: finish, cancelInteraction: cancel,
          expand: { expand(widget) }
        )
        .frame(width: rect.width, height: rect.height)
        .shadow(
          color: .black.opacity(active ? 0.16 : 0), radius: active ? 16 : 0, y: active ? 8 : 0
        )
        .position(x: rect.midX, y: rect.midY)
        // The held card follows each pointer event directly. Neighbors settle into place.
        .animation(active ? nil : motion, value: rect)
        .zIndex(active ? 2 : 0)
        .accessibilityIdentifier("widget.\(widget.id)")
      }
    }
    .frame(
      height: max(
        frames.map(\.maxY).max() ?? 0,
        interaction?.resizing == false ? interaction?.moveFrame.maxY ?? 0 : 0),
      alignment: .topLeading
    )
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .onGeometryChange(for: CGFloat.self) {
      $0.size.width
    } action: { newWidth in
      if abs(newWidth - width) > 0.5 {
        cancel()
        width = newWidth
      }
    }
    .onChange(of: customizing) { _, _ in cancel() }
    .onChange(of: store.widgets) { _, _ in cancel() }
    .onDisappear { interaction = nil }
  }

  private func begin(_ widget: WidgetConfiguration, frame: CGRect, anchor: CGPoint, resizing: Bool)
  {
    guard customizing else { return }
    interaction = WidgetInteraction(
      id: widget.id, resizing: resizing, startFrame: frame,
      // The grip spans the full header height, inset 17 points from the leading edge.
      anchor: CGPoint(x: 17 + anchor.x, y: anchor.y),
      originalFrames: frames, originalIDs: store.widgets.map(\.id))
  }

  private func update(_ translation: CGSize) {
    guard var value = interaction else { return }
    value.translation = translation
    interaction = value
  }

  private func finish() {
    guard let value = interaction else { return }
    withAnimation(motion) {
      interaction = nil
      guard value.hasMoved else { return }
      if value.resizing, let widget = store.widgets.first(where: { $0.id == value.id }) {
        let size = value.finalSize(of: widget, width: width)
        if size.columns != widget.columns || size.rows != widget.rows {
          store.resizeWidget(value.id, columns: size.columns, rows: size.rows)
        }
      } else if let index = value.targetIndex,
        store.widgets.firstIndex(where: { $0.id == value.id }) != index
      {
        store.reorderWidget(value.id, to: index)
      }
    }
  }

  private func cancel() {
    guard interaction != nil else { return }
    withAnimation(motion) { interaction = nil }
  }
}

struct WidgetInteraction {
  var id: UUID
  var resizing: Bool
  var startFrame: CGRect
  var anchor: CGPoint
  var originalFrames: [CGRect]
  var originalIDs: [UUID]
  var translation = CGSize.zero

  var hasMoved: Bool { abs(translation.width) > 3 || abs(translation.height) > 3 }
  var moveFrame: CGRect { startFrame.offsetBy(dx: translation.width, dy: translation.height) }
  var targetIndex: Int? {
    guard hasMoved else { return originalIDs.firstIndex(of: id) }
    return WidgetGridGeometry.dropIndex(
      at: CGPoint(x: moveFrame.minX + anchor.x, y: moveFrame.minY + anchor.y),
      frames: originalFrames)
  }
  func resizeFrame(width: CGFloat) -> CGRect {
    WidgetGridGeometry.liveResizeFrame(start: startFrame, width: width, translation: translation)
  }
  func finalSize(of widget: WidgetConfiguration, width: CGFloat) -> (columns: Int, rows: Int) {
    let rect = resizeFrame(width: width)
    let size = WidgetGridGeometry.resized(
      columns: widget.columns, rows: widget.rows,
      displayedColumns: WidgetGridGeometry.columnCount(width: width), width: startFrame.width,
      translation: CGSize(
        width: rect.width - startFrame.width, height: rect.height - startFrame.height))
    // Preserve a saved wider span unless the drag actually snaps to a different visible width.
    let visibleColumns = min(widget.columns, WidgetGridGeometry.columnCount(width: width))
    return (size.columns == visibleColumns ? widget.columns : size.columns, size.rows)
  }
  func reordered(_ widgets: [WidgetConfiguration]) -> [WidgetConfiguration] {
    guard let index = targetIndex, let source = widgets.firstIndex(where: { $0.id == id }) else {
      return widgets
    }
    var preview = widgets
    let widget = preview.remove(at: source)
    preview.insert(widget, at: min(index, preview.count))
    return preview
  }
}
