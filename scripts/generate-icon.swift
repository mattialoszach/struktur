import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
  fputs("Usage: generate-icon.swift <iconset-directory>\n", stderr)
  exit(2)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
guard output.pathExtension == "iconset" else {
  fputs("The output must be an .iconset directory.\n", stderr)
  exit(2)
}
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let variants: [(String, Int)] = [
  ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
  ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
  ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
  ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
  ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

func makeIcon(size: Int) throws -> Data {
  let dimension = CGFloat(size)
  guard
    let context = CGContext(
      data: nil,
      width: size,
      height: size,
      bitsPerComponent: 8,
      bytesPerRow: size * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
  else { throw CocoaError(.fileWriteUnknown) }

  let bounds = CGRect(x: 0, y: 0, width: dimension, height: dimension)
  let inset = dimension * 0.055
  let tileRect = bounds.insetBy(dx: inset, dy: inset)
  let tile = CGPath(
    roundedRect: tileRect, cornerWidth: dimension * 0.225, cornerHeight: dimension * 0.225,
    transform: nil)
  context.addPath(tile)
  context.setFillColor(CGColor(red: 0.94, green: 0.95, blue: 0.91, alpha: 1))
  context.fillPath()

  context.saveGState()
  context.addPath(tile)
  context.clip()
  context.translateBy(x: dimension / 2, y: dimension / 2)
  context.rotate(by: -.pi / 8)
  context.setStrokeColor(CGColor(red: 0.2, green: 0.25, blue: 0.2, alpha: 0.20))
  context.setLineWidth(max(0.5, dimension * 0.0018))
  context.strokeEllipse(
    in: CGRect(
      x: -dimension * 0.40, y: -dimension * 0.22, width: dimension * 0.80, height: dimension * 0.44)
  )
  context.restoreGState()

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
  func drawSymbol(_ name: String, color: NSColor, rect: CGRect, weight: NSFont.Weight = .regular) {
    let configuration = NSImage.SymbolConfiguration(pointSize: rect.width, weight: weight)
      .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    NSImage(systemSymbolName: name, accessibilityDescription: nil)?
      .withSymbolConfiguration(configuration)?.draw(in: rect)
  }
  let ink = NSColor(srgbRed: 0.17, green: 0.21, blue: 0.18, alpha: 1)
  drawSymbol(
    "asterisk", color: ink,
    rect: CGRect(
      x: dimension * 0.22, y: dimension * 0.22, width: dimension * 0.56, height: dimension * 0.56),
    weight: .heavy)
  if size >= 64 {
    let side = dimension * 0.15
    drawSymbol(
      "suit.spade.fill", color: NSColor(srgbRed: 0.76, green: 0.70, blue: 0.94, alpha: 1),
      rect: CGRect(x: dimension * 0.12, y: dimension * 0.68, width: side, height: side))
    drawSymbol(
      "suit.heart.fill", color: NSColor(srgbRed: 0.96, green: 0.72, blue: 0.60, alpha: 1),
      rect: CGRect(x: dimension * 0.72, y: dimension * 0.19, width: side, height: side))
    drawSymbol(
      "suit.club.fill", color: NSColor(srgbRed: 0.62, green: 0.82, blue: 0.71, alpha: 1),
      rect: CGRect(x: dimension * 0.14, y: dimension * 0.18, width: side, height: side))
    drawSymbol(
      "suit.diamond.fill", color: NSColor(srgbRed: 0.91, green: 0.79, blue: 0.40, alpha: 1),
      rect: CGRect(x: dimension * 0.73, y: dimension * 0.70, width: side * 0.8, height: side))
  }
  NSGraphicsContext.restoreGraphicsState()

  guard let cgImage = context.makeImage(),
    let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
  else {
    throw CocoaError(.fileWriteUnknown)
  }
  return png
}

for (name, size) in variants {
  try makeIcon(size: size).write(to: output.appending(path: name), options: .atomic)
}
