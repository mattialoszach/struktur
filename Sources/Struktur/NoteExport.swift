import AppKit
import CoreGraphics

@MainActor enum NoteExport {
  /// Export a portable folder without overwriting an existing document or asset directory.
  static func markdown(_ note: NoteDocument, to destination: URL) throws {
    let manager = FileManager.default
    guard !manager.fileExists(atPath: destination.path) else {
      throw WorkspaceValidationError.invalid(
        "A folder already exists at this location. Choose a new name.")
    }
    let staging = destination.deletingLastPathComponent().appending(
      path: ".struktur-export-\(UUID())")
    try manager.createDirectory(at: staging, withIntermediateDirectories: false)
    defer { try? manager.removeItem(at: staging) }
    try Data(note.markdown.utf8).write(
      to: staging.appending(path: "\(safeName(note.displayTitle)).md"), options: .atomic)
    let used = note.attachments.filter { note.markdown.contains($0.markdownPath) }
    if !used.isEmpty {
      try manager.createDirectory(
        at: staging.appending(path: "assets"), withIntermediateDirectories: false)
      for attachment in used {
        try attachment.data.write(
          to: staging.appending(path: attachment.markdownPath), options: .atomic)
      }
    }
    try manager.moveItem(at: staging, to: destination)
  }

  static func safeName(_ title: String) -> String {
    let value = title.components(
      separatedBy: CharacterSet(charactersIn: "/\\:\n\r\t").union(.controlCharacters)
    )
    .joined(separator: "-").trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    return value.isEmpty ? "Note" : String(value.prefix(80))
  }

  static func pdf(_ note: NoteDocument) throws -> Data {
    let pageSize = CGSize(width: 595, height: 842)
    let margin: CGFloat = 48
    let contentSize = CGSize(
      width: pageSize.width - margin * 2, height: pageSize.height - margin * 2 - 24)
    let content = NSMutableAttributedString(
      string: note.displayTitle + "\n\n",
      attributes: [
        .font: NSFont(name: "Georgia", size: 26) ?? NSFont.systemFont(ofSize: 26),
        .foregroundColor: NSColor.black,
      ])
    content.append(
      NoteWriteStyle.attributedForExport(note, width: contentSize.width))
    let storage = NSTextStorage(attributedString: content)
    let layout = NSLayoutManager()
    storage.addLayoutManager(layout)
    var pages: [(NSTextContainer, NSRange)] = []
    var end = 0
    repeat {
      let container = NSTextContainer(containerSize: contentSize)
      container.lineFragmentPadding = 0
      layout.addTextContainer(container)
      let range = layout.glyphRange(for: container)
      guard range.length > 0, pages.count < 2000 else {
        throw WorkspaceValidationError.invalid("This note is too large to lay out as a PDF.")
      }
      pages.append((container, range))
      end = NSMaxRange(range)
    } while end < layout.numberOfGlyphs
    let output = NSMutableData()
    var mediaBox = CGRect(origin: .zero, size: pageSize)
    guard let consumer = CGDataConsumer(data: output),
      let context = CGContext(
        consumer: consumer,
        mediaBox: &mediaBox, [kCGPDFContextTitle: note.displayTitle] as CFDictionary)
    else {
      throw WorkspaceValidationError.invalid("The PDF could not be created.")
    }
    for (index, page) in pages.enumerated() {
      context.beginPDFPage(nil)
      context.saveGState()
      context.translateBy(x: 0, y: pageSize.height)
      context.scaleBy(x: 1, y: -1)
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
      let origin = CGPoint(x: margin, y: margin)
      layout.drawBackground(forGlyphRange: page.1, at: origin)
      layout.drawGlyphs(forGlyphRange: page.1, at: origin)
      ("\(index + 1) / \(pages.count)" as NSString).draw(
        at: CGPoint(x: margin, y: pageSize.height - 34),
        withAttributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.gray])
      NSGraphicsContext.restoreGraphicsState()
      context.restoreGState()
      let characters = layout.characterRange(forGlyphRange: page.1, actualGlyphRange: nil)
      content.enumerateAttribute(.link, in: characters) { value, range, _ in
        guard let url = value as? URL, NoteRendering.allowed(url) else { return }
        let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        layout.enumerateEnclosingRects(
          forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
          in: page.0
        ) { rect, _ in
          context.setURL(
            url as CFURL,
            for: CGRect(
              x: margin + rect.minX,
              y: pageSize.height - margin - rect.maxY, width: rect.width, height: rect.height))
        }
      }
      context.endPDFPage()
    }
    context.closePDF()
    return output as Data
  }
}
