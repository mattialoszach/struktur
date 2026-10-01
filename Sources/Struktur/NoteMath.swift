import AppKit
import SwiftMath

/// Bounded, offline typesetting. Both successful and incomplete expressions are
/// cached so moving the caret and repainting never reparse an equation.
@MainActor enum NoteMath {
  final class Result: NSObject {
    let image: NSImage?
    let error: String?
    init(image: NSImage?, error: String?) {
      self.image = image
      self.error = error
    }
  }
  private static let cache: NSCache<NSString, Result> = {
    let cache = NSCache<NSString, Result>()
    cache.countLimit = 256
    cache.totalCostLimit = 24_000_000
    return cache
  }()
  private(set) static var renderCount = 0

  static func render(_ source: String, display: Bool, dark: Bool) -> Result {
    let key = "\(display):\(dark):\(source)" as NSString
    if let cached = cache.object(forKey: key) { return cached }
    let result: Result
    if !isBounded(source) {
      result = Result(image: nil, error: "Equation is too large or deeply nested to render inline.")
    } else {
      renderCount += 1
      let renderer = MTMathImage(
        latex: source, fontSize: display ? 20 : 16,
        textColor: NoteWriteStyle.ink(dark: dark),
        labelMode: display ? .display : .text, textAlignment: .left)
      let (error, vector) = renderer.asImage()
      if let vector, vector.size.width.isFinite, vector.size.height.isFinite,
        vector.size.width > 0, vector.size.height > 0,
        vector.size.width <= 8000, vector.size.height <= 2000
      {
        // Rasterize once at Retina resolution. Scrolling only draws this bitmap.
        let size = NSSize(width: ceil(vector.size.width) + 4, height: ceil(vector.size.height) + 4)
        let bitmap = NSBitmapImageRep(
          bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
          colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        vector.draw(in: NSRect(origin: CGPoint(x: 2, y: 2), size: vector.size))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        result = Result(image: image, error: nil)
      } else {
        result = Result(image: nil, error: error?.localizedDescription ?? "Incomplete equation")
      }
    }
    let cost = result.image.map { Int($0.size.width * $0.size.height * 16) } ?? source.utf8.count
    cache.setObject(result, forKey: key, cost: cost)
    return result
  }

  private static func isBounded(_ source: String) -> Bool {
    guard source.utf16.count <= 4096 else { return false }
    var depth = 0
    var commands = 0
    for character in source {
      if character == "{" { depth += 1 }
      if character == "}" { depth -= 1 }
      if character == "\\" { commands += 1 }
      if depth > 32 || commands > 256 { return false }
    }
    return true
  }
}

/// Drawn by TextKit's viewport fragments; the source characters stay in storage.
/// Keeping one UTF-16 coordinate space makes undo, IME and annotations native.
final class NoteInlineVisual: NSObject {
  enum Kind { case math, image, checkbox, bullet, divider }
  let image: NSImage
  let size: NSSize
  let kind: Kind
  init(image: NSImage, width: CGFloat, kind: Kind) {
    self.image = image
    let scale = min(1, max(32, width) / max(1, image.size.width))
    size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
    self.kind = kind
  }
}

extension NSAttributedString.Key {
  static let noteWidthSensitive = Self("StrukturWidthSensitive")
  static let noteCustomLayout = Self("StrukturCustomLayout")
  static let noteHidden = Self("StrukturHiddenSyntax")
  static let noteVisual = Self("StrukturInlineVisual")
  static let noteVisualSource = Self("StrukturVisualSource")
  static let noteMathPreview = Self("StrukturMathPreview")
  static let noteCheckbox = Self("StrukturCheckbox")
  static let noteLiteral = Self("StrukturLiteral")
}

/// Uses public TextKit 2 drawing hooks. No layout-manager fallback, web view,
/// document replacement, or mutation of text during a display pass.
final class NoteLayoutFragment: NSTextLayoutFragment {
  private lazy var previews: [NoteInlineVisual] = {
    guard let paragraph = textElement as? NSTextParagraph else { return [] }
    var result: [NoteInlineVisual] = []
    paragraph.attributedString.enumerateAttribute(
      .noteMathPreview, in: NSRange(location: 0, length: paragraph.attributedString.length)
    ) { value, _, _ in if let visual = value as? NoteInlineVisual { result.append(visual) } }
    return result
  }()
  override var bottomMargin: CGFloat {
    super.bottomMargin + previews.reduce(0) { $0 + $1.size.height + 10 }
  }
  override func draw(at point: CGPoint, in context: CGContext) {
    super.draw(at: point, in: context)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    defer { NSGraphicsContext.restoreGraphicsState() }
    let clip = context.boundingBoxOfClipPath
    for line in textLineFragments
    where line.typographicBounds.offsetBy(dx: point.x, dy: point.y).intersects(clip) {
      line.attributedString.enumerateAttribute(.noteVisual, in: line.characterRange) {
        value, range, _ in
        guard let visual = value as? NoteInlineVisual else { return }
        let location = line.locationForCharacter(at: range.location)
        let origin = CGPoint(
          x: point.x + line.typographicBounds.minX + location.x,
          y: point.y + line.typographicBounds.minY
            + (line.typographicBounds.height - visual.size.height) / 2)
        visual.image.draw(
          in: NSRect(origin: origin, size: visual.size),
          from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
      }
    }
    var y = point.y + (textLineFragments.map(\.typographicBounds.maxY).max() ?? 0) + 8
    for visual in previews {
      visual.image.draw(
        in: NSRect(x: point.x, y: y, width: visual.size.width, height: visual.size.height),
        from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
      y += visual.size.height + 10
    }
  }
}
