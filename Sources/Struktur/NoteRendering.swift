import AppKit

struct NoteCodeFence: Equatable {
  var marker: Character
  var length: Int

  static func after(_ line: String, starting current: Self?) -> Self? {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let marker = trimmed.first, marker == "`" || marker == "~" else { return current }
    let run = trimmed.prefix { $0 == marker }.count
    guard run >= 3 else { return current }
    if let current {
      return marker == current.marker && run >= current.length
        && trimmed.dropFirst(run).trimmingCharacters(in: .whitespaces).isEmpty ? nil : current
    }
    return Self(marker: marker, length: run)
  }
}

extension NoteColor {
  func foreground(dark: Bool) -> NSColor {
    let hex: UInt32 =
      switch self {
      case .rose: dark ? 0xF4A5B8 : 0xA82F51
      case .gold: dark ? 0xEBD07E : 0x81600D
      case .green: dark ? 0xA1D4AE : 0x296742
      case .blue: dark ? 0xA5C6EF : 0x2C609C
      case .purple: dark ? 0xC7B4EC : 0x7350A4
      }
    return NSColor(
      srgbRed: CGFloat((hex >> 16) & 255) / 255,
      green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
  }
  func background(dark: Bool) -> NSColor {
    foreground(dark: dark).withAlphaComponent(dark ? 0.25 : 0.16)
  }
}

enum NoteRendering {
  static func allowed(_ url: URL) -> Bool {
    ["http", "https", "mailto", "struktur"].contains(url.scheme?.lowercased() ?? "")
  }
}
