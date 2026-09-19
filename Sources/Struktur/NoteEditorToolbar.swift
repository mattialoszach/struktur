import SwiftUI

struct NoteEditorToolbar: View {
  @EnvironmentObject private var store: WorkspaceStore
  @Environment(\.colorScheme) private var colorScheme
  let noteID: UUID
  @ObservedObject var controller: NoteEditorController
  var showLinks: () -> Void
  var chooseImage: () -> Void
  @State private var showingTextColors = false
  @State private var showingHighlights = false

  var body: some View {
    NoteToolbarLayout {
      HStack(spacing: 9) { formatButtons }
      insertMenu
    }
  }

  @ViewBuilder private var formatButtons: some View {
    IconButton(icon: "bold", label: "Bold selection (⌘B)") {
      controller.wrap("**", placeholder: "bold text")
    }
    IconButton(icon: "italic", label: "Italic selection (⌘I)") {
      controller.wrap("*", placeholder: "italic text")
    }
    IconButton(icon: "strikethrough", label: "Strikethrough selection") {
      controller.wrap("~~", placeholder: "text")
    }
    IconButton(icon: "chevron.left.forwardslash.chevron.right", label: "Inline code") {
      controller.wrap("`", placeholder: "code")
    }
    Divider().frame(height: 17)
    decorationMenu(highlight: false)
    decorationMenu(highlight: true)
  }
  private func decorationMenu(highlight: Bool) -> some View {
    let presented = highlight ? $showingHighlights : $showingTextColors
    return Button {
      presented.wrappedValue.toggle()
    } label: {
      Label(
        highlight ? "Highlight" : "Color", systemImage: highlight ? "highlighter" : "paintpalette"
      )
      .font(.system(size: 11, weight: .medium)).padding(.horizontal, 5).frame(height: 28)
    }
    .buttonStyle(.plain)
    .disabled(!controller.hasSelection)
    .help("Select text, then choose a \(highlight ? "highlight" : "text color")")
    .accessibilityLabel(highlight ? "Highlight selection" : "Text color")
    .popover(isPresented: presented, arrowEdge: .bottom) {
      VStack(alignment: .leading, spacing: 6) {
        Text(highlight ? "Highlight" : "Text color").font(.strukturSerif(20)).padding(.bottom, 6)
        ForEach(NoteColor.allCases) { color in
          Button {
            decorate(color, highlight: highlight)
            presented.wrappedValue = false
          } label: {
            HStack(spacing: 12) {
              Text("Text").font(.system(size: 12, weight: .medium))
                .foregroundStyle(
                  highlight
                    ? StrukturTheme.ink
                    : Color(nsColor: color.foreground(dark: colorScheme == .dark))
                )
                .frame(width: 46, height: 28)
                .background(
                  highlight
                    ? Color(nsColor: color.background(dark: colorScheme == .dark))
                    : StrukturTheme.surface,
                  in: RoundedRectangle(cornerRadius: 5)
                )
                .overlay(
                  RoundedRectangle(cornerRadius: 5).strokeBorder(
                    StrukturTheme.hairline, lineWidth: 1))
              Text(color.title).font(.system(size: 12))
              Spacer()
            }.padding(4).contentShape(Rectangle())
          }.buttonStyle(.plain).accessibilityLabel(
            "\(color.title) \(highlight ? "highlight" : "text color")")
        }
        Divider().padding(.vertical, 4)
        Button(
          highlight ? "Remove highlight" : "Default text color", systemImage: "arrow.uturn.backward"
        ) {
          decorate(nil, highlight: highlight)
          presented.wrappedValue = false
        }.buttonStyle(.plain).font(.system(size: 12)).padding(6)
      }.padding(16).frame(width: 210).background(StrukturTheme.canvas)
    }
  }
  private var insertMenu: some View {
    Menu {
      Button("Heading 1") { controller.block("# ") }
      Button("Heading 2") { controller.block("## ") }
      Button("Heading 3") { controller.block("### ") }
      Divider()
      Button("Bullet list") { controller.block("- ") }
      Button("Numbered list") { controller.block("1. ") }
      Button("Checklist") { controller.block("- [ ] ") }
      Button("Quote") { controller.block("> ") }
      Button("Code block") {
        controller.insert("\n```\ncode\n```\n", selectOffset: 5, selectLength: 4)
      }
      Button("Divider") { controller.insert("\n\n---\n\n") }
      Divider()
      Button("Web link") {
        controller.insert("[Link title](https://example.com)", selectOffset: 13, selectLength: 19)
      }
      Button("Link to workspace item…") { showLinks() }
      Button("Image from file…", systemImage: "photo") { chooseImage() }
    } label: {
      Label("Insert", systemImage: "plus").font(.system(size: 11, weight: .medium))
    }
    .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Insert into note")
  }
  private func decorate(_ color: NoteColor?, highlight: Bool) {
    let selection = controller.selection
    if var note = store.note(noteID) {
      guard selection.length > 0, Range(selection, in: note.markdown) != nil else { return }
      note.decorations = note.decorations.flatMap { item -> [NoteDecoration] in
        guard item.highlight == highlight, NSIntersectionRange(item.range, selection).length > 0
        else { return [item] }
        var pieces: [NoteDecoration] = []
        if item.location < selection.location {
          var left = item
          left.length = selection.location - item.location
          pieces.append(left)
        }
        if NSMaxRange(item.range) > NSMaxRange(selection) {
          var right = item
          right.location = NSMaxRange(selection)
          right.length = NSMaxRange(item.range) - right.location
          pieces.append(right)
        }
        return pieces
      }
      if let color {
        note.decorations.append(
          NoteDecoration(
            location: selection.location, length: selection.length, color: color,
            highlight: highlight))
      }
      controller.applyDecorations(note.decorations, store: store, noteID: noteID)
    }
  }
}

/// A single set of native controls; narrow layouts move Insert to a second row.
/// ViewThatFits built both complete toolbar/menu/popover trees while measuring.
struct NoteToolbarLayout: Layout {
  func makeCache(subviews: Subviews) -> [CGSize] {
    subviews.map { $0.sizeThatFits(.unspecified) }
  }
  func updateCache(_ cache: inout [CGSize], subviews: Subviews) {
    cache = makeCache(subviews: subviews)
  }
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout [CGSize]) -> CGSize
  {
    let frames = Self.frames(width: proposal.width, sizes: cache)
    return CGSize(width: frames.map(\.maxX).max() ?? 0, height: frames.map(\.maxY).max() ?? 0)
  }
  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout [CGSize]
  ) {
    for (index, frame) in Self.frames(width: bounds.width, sizes: cache).enumerated() {
      subviews[index].place(
        at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
        anchor: .topLeading, proposal: ProposedViewSize(frame.size))
    }
  }
  static func frames(width: CGFloat?, sizes: [CGSize]) -> [CGRect] {
    guard sizes.count == 2 else { return [] }
    let naturalWidth = sizes[0].width + 9 + sizes[1].width
    let available = width?.isFinite == true ? max(sizes[0].width, width!) : naturalWidth
    if available >= naturalWidth {
      let height = max(sizes[0].height, sizes[1].height)
      return [
        CGRect(
          x: 0, y: (height - sizes[0].height) / 2, width: sizes[0].width, height: sizes[0].height),
        CGRect(
          x: available - sizes[1].width, y: (height - sizes[1].height) / 2, width: sizes[1].width,
          height: sizes[1].height),
      ]
    }
    return [
      CGRect(origin: .zero, size: sizes[0]),
      CGRect(x: 0, y: sizes[0].height + 8, width: sizes[1].width, height: sizes[1].height),
    ]
  }
}
