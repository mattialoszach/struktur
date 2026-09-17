import SwiftUI

struct DashboardView: View {
  @EnvironmentObject private var store: WorkspaceStore
  @Binding var selectedDate: Date
  @Binding var quickCapture: QuickCaptureKind?
  @State private var customizing = false
  @State private var showingLibrary = false
  @State private var expanded: WidgetConfiguration?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        hero
        WeekRibbon(selectedDate: $selectedDate)
        workspaceToolbar
        InteractiveWidgetGrid(selectedDate: $selectedDate, customizing: customizing) {
          expanded = $0
        }
        if store.widgets.isEmpty {
          VStack(spacing: 16) {
            EmptyState(
              icon: "square.grid.2x2", title: "No widgets yet",
              message: "Add a widget to see your schedule, tasks, or notes here.")
            Button("Add your first widget") { showingLibrary = true }.buttonStyle(
              StrukturButtonStyle(primary: true))
          }.frame(height: 310)
        }
        HStack(spacing: 7) {
          SuitIcon(symbol: .club, color: .mint, size: 12)
          EditableWording(.dashboardFooter).font(.strukturSerif(12))
            .foregroundStyle(StrukturTheme.muted)
          Spacer()
          Group {
            if customizing {
              Text("Drag a header to move · drag a corner to resize")
            } else {
              EditableWording(.dashboardFooterNote)
            }
          }.font(.system(size: 9)).foregroundStyle(StrukturTheme.muted)
        }.padding(.top, 22).padding(.bottom, 8)
      }.padding(.horizontal, 30).padding(.bottom, 24)
    }
    .scrollIndicators(.hidden)
    .sheet(isPresented: $showingLibrary) { WidgetEditorSheet() }
    .sheet(item: $expanded) { widget in
      ExpandedWidgetView(configuration: widget, selectedDate: $selectedDate)
    }
  }

  private var hero: some View {
    HStack(alignment: .center) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 8) {
          Eyebrow(text: selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
          Circle().fill(StrukturTheme.muted).frame(width: 2, height: 2)
          Eyebrow(text: "Week \(Calendar.struktur.component(.weekOfYear, from: selectedDate))")
        }
        EditableWording(.dashboardTitle)
          .font(.strukturSerif(43)).tracking(-1.7)
        Text(subtitle).font(.system(size: 12)).foregroundStyle(StrukturTheme.muted)
      }
      Spacer(minLength: 15)
      OrbitArtwork()
    }.padding(.top, 21).padding(.bottom, 20)
  }

  private var subtitle: String {
    let count = store.tasks(on: selectedDate).count
    return count == 0
      ? "No open tasks for this day."
      : "\(count) open \(count == 1 ? "task" : "tasks") for this day."
  }

  private var workspaceToolbar: some View {
    HStack(spacing: 10) {
      HStack(spacing: 6) {
        Image(systemName: customizing ? "pencil.and.outline" : "square.grid.2x2")
          .font(.system(size: 11))
        Text(customizing ? "Editing layout" : "Your workspace")
          .font(.system(size: 11, weight: .semibold))
      }
      .foregroundStyle(StrukturTheme.ink)
      .frame(width: 124, height: 28)
      .background(
        customizing ? StrukturTheme.editingSurface : .clear,
        in: RoundedRectangle(cornerRadius: 7))
      Text(
        customizing ? "Drag headers to move · corners to resize" : "\(store.widgets.count) widgets"
      )
      .font(.system(size: 10)).foregroundStyle(StrukturTheme.muted).lineLimit(1)
      Spacer()
      Group {
        if customizing {
          Button {
            withAnimation(.easeInOut(duration: 0.18)) { customizing = false }
          } label: {
            Label("Done", systemImage: "checkmark").frame(width: 84, height: 14)
          }
          .keyboardShortcut(.defaultAction)
          .help("Finish editing the layout")
        } else {
          Button {
            withAnimation(.easeInOut(duration: 0.18)) { customizing = true }
          } label: {
            Label("Edit layout", systemImage: "slider.horizontal.3").frame(width: 84, height: 14)
          }
          .help("Move and resize widgets")
        }
      }
      .buttonStyle(StrukturButtonStyle(primary: customizing, compact: true))
      Button {
        showingLibrary = true
      } label: {
        Label("Add widget", systemImage: "plus").frame(width: 84, height: 14)
      }
      .buttonStyle(StrukturButtonStyle(primary: !customizing, compact: true))
    }
    .frame(height: 28)
    .padding(.top, 21).padding(.bottom, 15)
  }
}

struct WeekRibbon: View {
  @EnvironmentObject private var store: WorkspaceStore
  @Binding var selectedDate: Date
  private var start: Date { store.weekStart(for: selectedDate) }
  var body: some View {
    HStack(spacing: 0) {
      HStack(spacing: 5) {
        IconButton(icon: "chevron.left", label: "Previous week") {
          selectedDate = selectedDate.adding(days: -7)
        }
        VStack(alignment: .leading, spacing: 5) {
          Text(selectedDate.formatted(.dateTime.month(.wide))).font(.strukturSerif(17))
          Button("Back to today") { selectedDate = Date() }.buttonStyle(.plain)
            .font(.system(size: 9)).foregroundStyle(StrukturTheme.muted)
        }.frame(width: 90, alignment: .leading)
        IconButton(icon: "chevron.right", label: "Next week") {
          selectedDate = selectedDate.adding(days: 7)
        }
      }.padding(.trailing, 18)
      Rectangle().fill(StrukturTheme.hairline).frame(width: 1, height: 38)
      ForEach(0..<7, id: \.self) { offset in
        let day = start.adding(days: offset)
        let selected = Calendar.struktur.isDate(day, inSameDayAs: selectedDate)
        Button {
          withAnimation(.easeInOut(duration: 0.18)) { selectedDate = day }
        } label: {
          HStack(spacing: 9) {
            VStack(alignment: .leading, spacing: 4) {
              Text(day.formatted(.dateTime.weekday(.abbreviated))).font(.system(size: 9))
              Text(day.formatted(.dateTime.day())).font(.strukturSerif(18))
            }
            VStack(spacing: 3) {
              ForEach(Array(store.blocks(on: day).prefix(3))) { block in
                Capsule().fill(block.color.color).frame(width: 4, height: 6)
              }
            }.frame(width: 4)
          }
          .foregroundStyle(selected ? StrukturTheme.buttonText : StrukturTheme.ink)
          .frame(maxWidth: .infinity).frame(height: 55)
          .background(
            selected ? StrukturTheme.darkButton : .clear, in: RoundedRectangle(cornerRadius: 11)
          )
          .contentShape(Rectangle())
        }.buttonStyle(.plain).padding(.horizontal, 5)
          .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month().day()))
      }
    }.padding(10).background(StrukturTheme.surface, in: RoundedRectangle(cornerRadius: 15))
      .overlay { RoundedRectangle(cornerRadius: 15).strokeBorder(StrukturTheme.hairline) }
  }
}

enum WidgetGridGeometry {
  static let gap: CGFloat = 16
  static let rowHeight: CGFloat = 196
  static func columnCount(width: CGFloat) -> Int { width >= 1000 ? 4 : (width >= 780 ? 3 : 2) }
  static func resized(
    columns: Int, rows: Int, displayedColumns: Int, width: CGFloat, translation: CGSize
  ) -> (columns: Int, rows: Int) {
    let visible = max(1, min(columns, displayedColumns))
    let unit = (max(1, width) + gap) / CGFloat(visible)
    return (
      max(1, min(4, visible + Int((translation.width / unit).rounded()))),
      max(1, min(3, rows + Int((translation.height / (rowHeight + gap)).rounded())))
    )
  }
  static func liveResizeFrame(start: CGRect, width: CGFloat, translation: CGSize) -> CGRect {
    let columns = columnCount(width: width)
    let cellWidth = max(1, (width - CGFloat(columns - 1) * gap) / CGFloat(columns))
    return CGRect(
      origin: start.origin,
      size: CGSize(
        width: max(cellWidth, min(width - start.minX, start.width + translation.width)),
        height: max(rowHeight, min(3 * rowHeight + 2 * gap, start.height + translation.height))))
  }

  static func dropIndex(at point: CGPoint, frames: [CGRect]) -> Int? {
    // Include the gutters, so a drop between cards has a predictable destination.
    if let hit = frames.firstIndex(where: { $0.insetBy(dx: -gap / 2, dy: -gap / 2).contains(point) }
    ) {
      return hit
    }
    return frames.indices.min {
      distance(point, to: frames[$0]) < distance(point, to: frames[$1])
    }
  }

  private static func distance(_ point: CGPoint, to rect: CGRect) -> CGFloat {
    let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
    let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
    return dx * dx + dy * dy
  }

  static func frames(
    width: CGFloat, sizes: [(columns: Int, rows: Int)],
    liveResize: (index: Int, frame: CGRect)? = nil
  ) -> [CGRect] {
    let columns = columnCount(width: width)
    let cellWidth = max(1, (width - CGFloat(columns - 1) * gap) / CGFloat(columns))
    var occupied: [CGRect] = liveResize.map { [$0.frame] } ?? []
    return sizes.enumerated().map { index, size in
      if let liveResize, index == liveResize.index { return liveResize.frame }
      let span = max(1, min(columns, size.columns))
      let rows = max(1, min(3, size.rows))
      var row = 0
      while true {
        for candidate in 0...(columns - span) {
          let rect = CGRect(
            x: CGFloat(candidate) * (cellWidth + gap), y: CGFloat(row) * (rowHeight + gap),
            width: CGFloat(span) * cellWidth + CGFloat(span - 1) * gap,
            height: CGFloat(rows) * rowHeight + CGFloat(rows - 1) * gap)
          if occupied.allSatisfy({ !rect.intersects($0.insetBy(dx: -gap + 0.01, dy: -gap + 0.01)) })
          {
            occupied.append(rect)
            return rect
          }
        }
        row += 1
      }
    }
  }
}

struct WidgetShell: View {
  @EnvironmentObject private var store: WorkspaceStore
  let configuration: WidgetConfiguration
  @Binding var selectedDate: Date
  var customizing: Bool
  var interacting = false
  var moveBegan: (CGPoint) -> Void
  var moveChanged: (CGSize) -> Void
  var moveEnded: () -> Void
  var resizeBegan: () -> Void
  var resizeChanged: (CGSize) -> Void
  var resizeEnded: () -> Void
  var cancelInteraction: () -> Void
  var expand: () -> Void

  var body: some View {
    GeometryReader { geometry in
      VStack(spacing: 0) {
        header
        GeometryReader { content in
          WidgetContent(configuration: configuration, selectedDate: $selectedDate)
            .frame(width: content.size.width, height: content.size.height, alignment: .topLeading)
            .clipped()
        }
        .allowsHitTesting(!customizing)
        .opacity(customizing ? 0.65 : 1)
      }
      .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
      .background(background, in: RoundedRectangle(cornerRadius: 16))
      .overlay {
        RoundedRectangle(cornerRadius: 16)
          .strokeBorder(StrukturTheme.hairline, lineWidth: 1)
          .allowsHitTesting(false)
      }
      .clipShape(RoundedRectangle(cornerRadius: 16))
      .overlay(alignment: .bottomTrailing) {
        if customizing {
          Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 10, weight: .bold)).foregroundStyle(StrukturTheme.ink)
            .frame(width: 27, height: 27).background(
              StrukturTheme.editingSurface, in: RoundedRectangle(cornerRadius: 7)
            )
            .padding(5)
            .overlay {
              NativeDragSurface(
                began: { _ in resizeBegan() }, changed: resizeChanged,
                ended: { delta, _ in
                  resizeChanged(delta)
                  resizeEnded()
                },
                cancelled: cancelInteraction, cursor: .crosshair)
            }
            .help("Drag to resize. More sizes are available in the widget menu.")
            .accessibilityLabel("Resize \(configuration.kind.title)")
            .accessibilityValue("\(configuration.columns) columns, \(configuration.rows) rows")
            .accessibilityAdjustableAction { direction in
              if direction == .increment {
                resize(configuration.columns, min(3, configuration.rows + 1))
              } else if direction == .decrement {
                resize(configuration.columns, max(1, configuration.rows - 1))
              }
            }
            .accessibilityAction(named: "Make wider") {
              resize(min(4, configuration.columns + 1), configuration.rows)
            }
            .accessibilityAction(named: "Make narrower") {
              resize(max(1, configuration.columns - 1), configuration.rows)
            }
        }
      }
    }
  }

  private var background: Color {
    switch configuration.kind {
    case .focus: StrukturTheme.lavender
    case .deadlines: StrukturTheme.peach
    case .projectPulse: StrukturTheme.mint
    case .quickNote: StrukturTheme.butter
    default: StrukturTheme.surface
    }
  }

  private var header: some View {
    HStack(spacing: 6) {
      HStack(spacing: 7) {
        Image(systemName: customizing ? "line.3.horizontal" : configuration.kind.icon)
          .font(.system(size: 10, weight: customizing ? .semibold : .regular))
          .foregroundStyle(customizing ? StrukturTheme.ink : StrukturTheme.muted)
        Text(configuration.kind.title)
          .font(.system(size: 11, weight: customizing ? .semibold : .medium))
          .fixedSize(horizontal: false, vertical: true)
          .foregroundStyle(StrukturTheme.ink)
        Spacer(minLength: 0)
      }.frame(maxHeight: .infinity).contentShape(Rectangle())
        .overlay {
          if customizing {
            NativeDragSurface(
              began: moveBegan, changed: moveChanged,
              ended: { delta, _ in
                moveChanged(delta)
                moveEnded()
              }, cancelled: cancelInteraction)
          }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Move \(configuration.kind.title)")
        .accessibilityAction(named: "Move earlier") { move(-1) }
        .accessibilityAction(named: "Move later") { move(1) }
      IconButton(
        icon: "arrow.up.left.and.arrow.down.right", label: "Open \(configuration.kind.title)"
      ) { expand() }
      Menu {
        Button("Open widget", action: expand)
        Menu("Size") {
          Button("Small · 1 × 1") { resize(1, 1) }
          Button("Tall · 1 × 2") { resize(1, 2) }
          Button("Wide · 2 × 1") { resize(2, 1) }
          Button("Large · 2 × 2") { resize(2, 2) }
          Button("Full width · 4 × 2") { resize(4, 2) }
        }
        if [.dayFlow, .tasks, .deadlines, .connections, .upcoming, .projectPulse].contains(
          configuration.kind)
        {
          Menu("Show space") {
            Button("All spaces") { pin(nil) }
            ForEach(store.projects) { project in Button(project.name) { pin(project.id) } }
          }
        }
        Button("Move earlier") { move(-1) }
        Button("Move later") { move(1) }
        Divider()
        Button(role: .destructive) {
          withAnimation(.snappy) {
            store.setWidgets(store.widgets.filter { $0.id != configuration.id })
          }
        } label: {
          Label("Remove widget", systemImage: "trash").foregroundStyle(StrukturTheme.destructive)
        }
      } label: {
        Image(systemName: "ellipsis").font(.system(size: 11)).frame(width: 18, height: 25)
      }
      .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
      .help("Widget options").accessibilityLabel("Options for \(configuration.kind.title)")
    }.padding(.leading, 17).padding(.trailing, 12).frame(height: 43)
      .background(customizing ? StrukturTheme.editingSurface : .clear)
  }
  private func resize(_ columns: Int, _ rows: Int) {
    withAnimation(.snappy) { store.resizeWidget(configuration.id, columns: columns, rows: rows) }
  }
  private func pin(_ id: UUID?) {
    var widgets = store.widgets
    if let index = widgets.firstIndex(where: { $0.id == configuration.id }) {
      widgets[index].projectID = id
      store.setWidgets(widgets)
    }
  }
  private func move(_ direction: Int) {
    var widgets = store.widgets
    guard let index = widgets.firstIndex(where: { $0.id == configuration.id }),
      widgets.indices.contains(index + direction)
    else { return }
    widgets.swapAt(index, index + direction)
    withAnimation(.snappy) { store.setWidgets(widgets) }
  }
}

struct ExpandedWidgetView: View {
  @EnvironmentObject private var store: WorkspaceStore
  @Environment(\.dismiss) private var dismiss
  let configuration: WidgetConfiguration
  @Binding var selectedDate: Date
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 6) {
          Text(configuration.kind.title).font(.strukturSerif(29))
          Text(configuration.kind.detail).font(.caption).foregroundStyle(StrukturTheme.muted)
        }
        Spacer()
        IconButton(icon: "xmark", label: "Close widget") { dismiss() }
      }.padding(24)
      Divider()
      if configuration.kind == .momentum {
        InsightsPage()
      } else {
        WidgetContent(
          configuration: store.widgets.first(where: { $0.id == configuration.id }) ?? configuration,
          selectedDate: $selectedDate, expanded: true
        ).padding(12)
      }
    }.frame(width: 800, height: 670).background(StrukturTheme.canvas)
  }
}

struct WidgetEditorSheet: View {
  @EnvironmentObject private var store: WorkspaceStore
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 7) {
          Eyebrow(text: "Dashboard")
          Text("Widget library").font(.strukturSerif(29))
          Text("Add widgets, then arrange and resize them on your dashboard.").font(.caption)
            .foregroundStyle(StrukturTheme.muted)
        }
        Spacer()
        IconButton(icon: "xmark", label: "Close widget library") { dismiss() }
      }.padding(25)
      Divider()
      ScrollView {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
          ForEach(DashboardWidgetKind.allCases) { kind in
            VStack(alignment: .leading, spacing: 11) {
              HStack {
                Image(systemName: kind.icon).font(.system(size: 20, weight: .light)).frame(
                  width: 38, height: 38
                )
                .background(kind.accent.color.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
                Spacer()
                let count = store.widgets.filter { $0.kind == kind }.count
                if count > 0 { TagPill(text: "\(count) on your workspace") }
              }
              Text(kind.title).font(.strukturSerif(18))
              Text(kind.detail).font(.system(size: 11)).foregroundStyle(StrukturTheme.muted).frame(
                height: 33, alignment: .top)
              Button {
                let large = kind == .dayFlow || kind == .connections
                let tall = kind == .dayFlow || kind == .tasks || kind == .goals
                withAnimation {
                  store.setWidgets(
                    store.widgets + [
                      WidgetConfiguration(kind: kind, columns: large ? 2 : 1, rows: tall ? 2 : 1)
                    ])
                }
              } label: {
                Label("Add to workspace", systemImage: "plus")
              }.buttonStyle(StrukturButtonStyle(compact: true))
                .accessibilityLabel("Add \(kind.title) widget")
            }.frame(maxWidth: .infinity, alignment: .leading).strukturCard(padding: 16)
          }
        }.padding(22)
      }
      Divider()
      HStack {
        Text("Changes save automatically.").font(.caption2).foregroundStyle(StrukturTheme.muted)
        Spacer()
        Button("Done") { dismiss() }.buttonStyle(StrukturButtonStyle(primary: true))
      }.padding(18)
    }.frame(width: 690, height: 680).background(StrukturTheme.canvas)
  }
}
