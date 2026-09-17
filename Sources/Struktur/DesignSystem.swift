import AppKit
import SwiftUI

enum StrukturTheme {
  static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
        let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        return NSColor(
          srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
          blue: CGFloat(hex & 255) / 255, alpha: 1)
      })
  }
  static let canvas = adaptive(0xF7F8F3, 0x1D211F)
  static let surface = adaptive(0xFDFDF9, 0x272C28)
  static let sidebar = adaptive(0xEEF0E9, 0x181C19)
  static let ink = adaptive(0x2B332D, 0xE9EBE3)
  static let muted = adaptive(0x697063, 0xA9B3A6)
  static let hairline = adaptive(0xE3E6DD, 0x394138)
  static let darkButton = adaptive(0x303B30, 0xDCE7D5)
  static let buttonText = adaptive(0xF8F9F2, 0x202A20)
  static let lavender = adaptive(0xE9E5F5, 0x363143)
  static let peach = adaptive(0xF9EADF, 0x42342C)
  static let mint = adaptive(0xEAF0E1, 0x2E3B2C)
  static let butter = adaptive(0xF6F0D8, 0x3B3829)
  static let destructive = adaptive(0xC43532, 0xFF8078)
  static let editingSurface = adaptive(0xEDEAE4, 0x343330)
}

extension Font {
  static func strukturSerif(_ size: CGFloat, weight: Weight = .regular) -> Font {
    .custom("Georgia", fixedSize: size).weight(weight)
  }
  static func strukturSans(_ size: CGFloat, weight: Weight = .regular) -> Font {
    .system(size: size, weight: weight)
  }
}

struct CardStyle: ViewModifier {
  var padding: CGFloat = 18
  func body(content: Content) -> some View {
    content.padding(padding)
      .background(StrukturTheme.surface, in: RoundedRectangle(cornerRadius: 18))
      .overlay {
        RoundedRectangle(cornerRadius: 18).strokeBorder(StrukturTheme.hairline, lineWidth: 1)
      }
  }
}

extension View {
  func strukturCard(padding: CGFloat = 18) -> some View { modifier(CardStyle(padding: padding)) }
}

struct StrukturButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  var primary = false
  var compact = false
  func makeBody(configuration: Configuration) -> some View {
    let destructive = configuration.role == .destructive
    return configuration.label
      .fixedSize(horizontal: false, vertical: true)
      .font(.system(size: compact ? 11 : 12, weight: .medium))
      .padding(.horizontal, compact ? 10 : 14).padding(.vertical, compact ? 7 : 10)
      .foregroundStyle(
        destructive
          ? StrukturTheme.destructive
          : (primary ? StrukturTheme.buttonText : StrukturTheme.ink)
      )
      .background(
        destructive
          ? StrukturTheme.destructive.opacity(0.10)
          : (primary ? StrukturTheme.darkButton : StrukturTheme.surface),
        in: RoundedRectangle(cornerRadius: 9)
      )
      .overlay {
        if !primary {
          RoundedRectangle(cornerRadius: 9).strokeBorder(
            destructive ? StrukturTheme.destructive.opacity(0.22) : StrukturTheme.hairline)
        }
      }
      .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
      .contentShape(RoundedRectangle(cornerRadius: 9))
  }
}

/// Flat, keyboard-accessible choices shared by calendar modes, filters, and editors.
struct StrukturOptions<Value: Hashable>: View {
  let label: String
  @Binding var selection: Value
  let options: [Value]
  var title: (Value) -> String
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.isEnabled) private var isEnabled
  @Namespace private var highlight
  @FocusState private var focusedOption: Value?

  var body: some View {
    OptionLayout {
      ForEach(options, id: \.self) { option in
        Button {
          selection = option
          focusedOption = option
        } label: {
          Text(title(option))
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(selection == option ? StrukturTheme.ink : StrukturTheme.muted)
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity).padding(.horizontal, 9).padding(.vertical, 7)
            .background {
              if selection == option {
                RoundedRectangle(cornerRadius: 7).fill(StrukturTheme.surface)
                  .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                  .matchedGeometryEffect(id: "selection", in: highlight)
              }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain)
          .focusable()
          .focused($focusedOption, equals: option)
          .accessibilityLabel(title(option))
          .accessibilityAddTraits(selection == option ? .isSelected : [])
      }
    }
    .padding(3).background(
      StrukturTheme.hairline.opacity(0.5), in: RoundedRectangle(cornerRadius: 10)
    )
    .opacity(isEnabled ? 1 : 0.45)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: selection)
    .accessibilityElement(children: .contain).accessibilityLabel(label)
    .onMoveCommand { direction in
      guard isEnabled, let index = options.firstIndex(of: selection) else { return }
      let step = direction == .left ? -1 : (direction == .right ? 1 : 0)
      guard step != 0, options.indices.contains(index + step) else { return }
      selection = options[index + step]
      focusedOption = selection
    }
  }
}

/// Measure each choice before sharing spare space; long labels never get squeezed into equal slots.
struct OptionLayout: Layout {
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let frames = positions(proposal.width, subviews)
    return CGSize(width: frames.map(\.maxX).max() ?? 0, height: frames.map(\.maxY).max() ?? 0)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    for (index, rect) in positions(bounds.width, subviews).enumerated() {
      subviews[index].place(
        at: CGPoint(x: bounds.minX + rect.minX, y: bounds.minY + rect.minY),
        anchor: .topLeading, proposal: ProposedViewSize(rect.size))
    }
  }

  private func positions(_ width: CGFloat?, _ subviews: Subviews) -> [CGRect] {
    OptionLayoutGeometry.frames(width: width, sizes: subviews.map { $0.sizeThatFits(.unspecified) })
  }
}

enum OptionLayoutGeometry {
  static func frames(width: CGFloat?, sizes: [CGSize], spacing: CGFloat = 2) -> [CGRect] {
    guard !sizes.isEmpty else { return [] }
    let naturalWidth = sizes.reduce(0) { $0 + $1.width } + CGFloat(sizes.count - 1) * spacing
    let available = max(
      sizes.map(\.width).max() ?? 0, width?.isFinite == true ? width! : naturalWidth)
    var rows: [[Int]] = [[]]
    var used: CGFloat = 0
    for index in sizes.indices {
      let next = sizes[index].width + (rows.last!.isEmpty ? 0 : spacing)
      if used + next > available && !rows.last!.isEmpty {
        rows.append([])
        used = 0
      }
      if !rows[rows.count - 1].isEmpty { used += spacing }
      rows[rows.count - 1].append(index)
      used += sizes[index].width
    }
    var result = Array(repeating: CGRect.zero, count: sizes.count)
    var y: CGFloat = 0
    for row in rows {
      let height = row.map { sizes[$0].height }.max() ?? 0
      let contentWidth = row.reduce(0) { $0 + sizes[$1].width } + CGFloat(row.count - 1) * spacing
      let extra = max(0, available - contentWidth) / CGFloat(row.count)
      var x: CGFloat = 0
      for index in row {
        result[index] = CGRect(x: x, y: y, width: sizes[index].width + extra, height: height)
        x += sizes[index].width + extra + spacing
      }
      y += height + spacing
    }
    return result
  }
}

struct IconButton: View {
  let icon: String
  let label: String
  let action: () -> Void
  @State private var hovered = false
  var body: some View {
    Button(action: action) {
      Image(systemName: icon).font(.system(size: 11, weight: .medium))
        .frame(width: 26, height: 26)
        .background(
          hovered ? StrukturTheme.hairline : .clear, in: RoundedRectangle(cornerRadius: 6))
    }.buttonStyle(.plain).foregroundStyle(StrukturTheme.muted)
      .onHover { hovered = $0 }.help(label).accessibilityLabel(label)
  }
}

struct SuitIcon: View {
  var symbol: SuitSymbol
  var color: AccentToken? = nil
  var size: CGFloat = 17
  var body: some View {
    Image(systemName: symbol.icon).font(.system(size: size, weight: .regular))
      .foregroundStyle((color ?? symbol.color).color)
      .accessibilityLabel(symbol.title)
  }
}

struct AccentDot: View {
  let color: AccentToken
  var size: CGFloat = 8
  var body: some View { Circle().fill(color.color).frame(width: size, height: size) }
}

struct Eyebrow: View {
  var text = ""
  var wording: WordingKey?
  var body: some View {
    Group {
      if let wording {
        EditableWording(wording, uppercase: true)
      } else {
        Text(text.uppercased())
      }
    }.font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(StrukturTheme.muted)
  }
}

struct TagPill: View {
  let text: String
  var color: AccentToken = .mint
  var body: some View {
    Text(text).font(.system(size: 9, weight: .medium))
      .padding(.horizontal, 8).padding(.vertical, 4)
      .background(color.color.opacity(0.19), in: Capsule())
  }
}

struct EmptyState: View {
  let icon: String
  let title: String
  let message: String
  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: icon).font(.system(size: 28, weight: .light)).foregroundStyle(
        AccentToken.mint.color)
      Text(title).font(.strukturSerif(22))
      Text(message).font(.callout).foregroundStyle(StrukturTheme.muted).multilineTextAlignment(
        .center)
    }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

struct OrbitArtwork: View {
  var body: some View {
    ZStack {
      Ellipse().stroke(StrukturTheme.ink.opacity(0.24), lineWidth: 0.8)
        .frame(width: 205, height: 63).rotationEffect(.degrees(-18))
      Ellipse().stroke(
        StrukturTheme.ink.opacity(0.12), style: StrokeStyle(lineWidth: 0.8, dash: [2, 5])
      )
      .frame(width: 166, height: 97).rotationEffect(.degrees(24))
      SuitIcon(symbol: .spade, color: .lilac, size: 57).rotationEffect(.degrees(-17)).offset(
        x: -58, y: -6)
      SuitIcon(symbol: .heart, color: .peach, size: 50).rotationEffect(.degrees(18)).offset(
        x: 18, y: -26)
      SuitIcon(symbol: .club, color: .mint, size: 47).rotationEffect(.degrees(10)).offset(
        x: 61, y: 25)
      SuitIcon(symbol: .diamond, color: .butter, size: 32).rotationEffect(.degrees(-12)).offset(
        x: -8, y: 34)
      Image(systemName: "sparkle").font(.system(size: 14)).offset(x: 104, y: -24)
      Circle().fill(StrukturTheme.ink).frame(width: 4, height: 4).offset(x: -111, y: 15)
    }.frame(width: 250, height: 128).accessibilityHidden(true)
  }
}
