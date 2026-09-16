import SwiftUI
import UniformTypeIdentifiers

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
        WidgetGrid {
          ForEach(store.widgets) { widget in
            WidgetShell(
              configuration: widget, selectedDate: $selectedDate, customizing: customizing,
              expand: { expanded = widget }
            )
            .layoutValue(key: WidgetColumnsKey.self, value: widget.columns)
            .layoutValue(key: WidgetRowsKey.self, value: widget.rows)
          }
        }
        if store.widgets.isEmpty {
          VStack(spacing: 16) {
            EmptyState(
              icon: "square.grid.2x2", title: "A little space to make your own.",
              message: "Bring in the things that help you see your day clearly.")
            Button("Add your first widget") { showingLibrary = true }.buttonStyle(
              StrukturButtonStyle(primary: true))
          }.frame(height: 310)
        }
        HStack(spacing: 7) {
          SuitIcon(symbol: .club, color: .mint, size: 12)
          Text("A little structure. A lot of possibility.").font(.strukturSerif(12))
            .foregroundStyle(StrukturTheme.muted)
          Spacer()
          Text(
            customizing
              ? "Drag a header to move · drag a corner to resize" : "Made for the way you think."
          ).font(.system(size: 9)).foregroundStyle(StrukturTheme.muted)
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
        (Text("Your day, ") + Text("by design.").italic())
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
      ? "A clear head. An open day. Make a little room for what matters."
      : "\(count) next steps, a little breathing room, and everything in its place."
  }

  private var workspaceToolbar: some View {
    HStack(spacing: 10) {
      HStack(spacing: 6) {
        Image(systemName: "square.grid.2x2").font(.system(size: 11))
        Text("Your workspace").font(.system(size: 11, weight: .semibold))
      }
      Text("\(store.widgets.count) widgets").font(.system(size: 9)).foregroundStyle(
        StrukturTheme.muted)
      Spacer()
      if customizing {
        Text("Drag, resize, make it yours.").font(.system(size: 10)).foregroundStyle(
          StrukturTheme.muted)
        Button("Done") { withAnimation(.snappy) { customizing = false } }
          .buttonStyle(StrukturButtonStyle(primary: true, compact: true))
      } else {
        Button {
          withAnimation(.snappy) { customizing = true }
        } label: {
          Label("Edit layout", systemImage: "slider.horizontal.3")
        }
        .buttonStyle(StrukturButtonStyle(compact: true))
      }
      Button {
        showingLibrary = true
      } label: {
        Label("Add widget", systemImage: "plus")
      }
      .buttonStyle(StrukturButtonStyle(primary: !customizing, compact: true))
    }.padding(.top, 21).padding(.bottom, 15)
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

struct WidgetColumnsKey: LayoutValueKey { static let defaultValue = 1 }
struct WidgetRowsKey: LayoutValueKey { static let defaultValue = 1 }

enum WidgetGridGeometry {
  static let gap: CGFloat = 16
  static let rowHeight: CGFloat = 196
  static func columnCount(width: CGFloat) -> Int { width >= 1000 ? 4 : (width >= 780 ? 3 : 2) }
  static func frames(width: CGFloat, sizes: [(columns: Int, rows: Int)]) -> [CGRect] {
    let columns = columnCount(width: width)
    let cellWidth = max(1, (width - CGFloat(columns - 1) * gap) / CGFloat(columns))
    var occupied: Set<Int> = []
    return sizes.map { size in
      let span = max(1, min(columns, size.columns))
      let rows = max(1, min(3, size.rows))
      var row = 0
      var col = 0
      search: while true {
        for candidate in 0...(columns - span) {
          let cells = (row..<(row + rows)).flatMap { r in
            (candidate..<(candidate + span)).map { r * columns + $0 }
          }
          if cells.allSatisfy({ !occupied.contains($0) }) {
            occupied.formUnion(cells)
            col = candidate
            break search
          }
        }
        row += 1
      }
      return CGRect(
        x: CGFloat(col) * (cellWidth + gap), y: CGFloat(row) * (rowHeight + gap),
        width: CGFloat(span) * cellWidth + CGFloat(span - 1) * gap,
        height: CGFloat(rows) * rowHeight + CGFloat(rows - 1) * gap)
    }
  }
}

struct WidgetGrid: Layout {
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? 1100
    return CGSize(width: width, height: frames(width, subviews).map(\.maxY).max() ?? 0)
  }
  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    let positions = frames(bounds.width, subviews)
    for (index, subview) in subviews.enumerated() {
      let rect = positions[index]
      subview.place(
        at: CGPoint(x: bounds.minX + rect.minX, y: bounds.minY + rect.minY), anchor: .topLeading,
        proposal: ProposedViewSize(rect.size))
    }
  }
  private func frames(_ width: CGFloat, _ subviews: Subviews) -> [CGRect] {
    WidgetGridGeometry.frames(
      width: width, sizes: subviews.map { ($0[WidgetColumnsKey.self], $0[WidgetRowsKey.self]) })
  }
}

struct WidgetShell: View {
  @EnvironmentObject private var store: WorkspaceStore
  let configuration: WidgetConfiguration
  @Binding var selectedDate: Date
  var customizing: Bool
  var expand: () -> Void
  @State private var dropTarget = false
  @State private var resizeTranslation = CGSize.zero

  var body: some View {
    GeometryReader { geometry in
      VStack(spacing: 0) {
        header
        WidgetContent(configuration: configuration, selectedDate: $selectedDate)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
      .background(background, in: RoundedRectangle(cornerRadius: 16))
      .overlay {
        RoundedRectangle(cornerRadius: 16)
          .strokeBorder(
            dropTarget
              ? AccentToken.lilac.color
              : (customizing ? StrukturTheme.ink.opacity(0.3) : StrukturTheme.hairline),
            style: StrokeStyle(lineWidth: dropTarget ? 2 : 1, dash: customizing ? [5, 4] : [])
          )
          .allowsHitTesting(false)
      }
      .clipShape(RoundedRectangle(cornerRadius: 16))
      .overlay(alignment: .bottomTrailing) {
        if customizing {
          Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 10, weight: .bold)).foregroundStyle(StrukturTheme.ink)
            .frame(width: 27, height: 27).background(
              StrukturTheme.surface, in: RoundedRectangle(cornerRadius: 7)
            )
            .padding(5)
            .offset(x: resizeTranslation.width, y: resizeTranslation.height)
            .gesture(
              DragGesture(minimumDistance: 3)
                .onChanged { resizeTranslation = $0.translation }
                .onEnded { value in
                  let unit = (geometry.size.width + 16) / CGFloat(configuration.columns)
                  let columns =
                    configuration.columns + Int((value.translation.width / unit).rounded())
                  let rows = configuration.rows + Int((value.translation.height / 212).rounded())
                  withAnimation(.snappy) {
                    store.resizeWidget(configuration.id, columns: columns, rows: rows)
                    resizeTranslation = .zero
                  }
                }
            )
            .help("Drag to resize. More sizes are available in the widget menu.")
            .accessibilityLabel("Resize \(configuration.kind.title)")
        }
      }
      .dropDestination(for: String.self) { items, _ in
        guard customizing, let value = items.first, value.hasPrefix("struktur-widget:"),
          let id = UUID(uuidString: String(value.dropFirst(16)))
        else { return false }
        withAnimation(.snappy) { store.moveWidget(id, before: configuration.id) }
        return true
      } isTargeted: {
        dropTarget = customizing && $0
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
          .font(.system(size: 10)).foregroundStyle(StrukturTheme.muted)
        Text(configuration.kind.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
        Spacer(minLength: 0)
      }.contentShape(Rectangle()).draggable("struktur-widget:\(configuration.id.uuidString)")
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
        Button("Remove widget", role: .destructive) {
          withAnimation(.snappy) {
            store.setWidgets(store.widgets.filter { $0.id != configuration.id })
          }
        }
      } label: {
        Image(systemName: "ellipsis").font(.system(size: 11)).frame(width: 18, height: 25)
      }
      .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
      .help("Widget options").accessibilityLabel("Options for \(configuration.kind.title)")
    }.padding(.leading, 17).padding(.trailing, 12).frame(height: 43)
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
          Eyebrow(text: "A workspace that feels like you")
          Text("A place for your possibilities.").font(.strukturSerif(29))
          Text("Add what you need. Resize it. Give it a space of its own.").font(.caption)
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
                let tall = kind == .dayFlow || kind == .tasks
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
