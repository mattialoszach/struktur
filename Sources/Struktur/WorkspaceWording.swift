import SwiftUI

/// Stable keys keep personal wording independent of changes to the built-in copy.
enum WordingKey: String, CaseIterable {
  case dashboardTitle, dashboardFooter, dashboardFooterNote
  case sidebarEyebrow, calendarEyebrow, tasksSubtitle
  case spacesEyebrow, spacesTitle, goalsEyebrow, goalsTitle, goalsSubtitle
  case focusEyebrow, focusTitle, focusSubtitle
  case insightsTitle, insightsSubtitle, insightsFooter
  case scheduleTitle, tasksTitle, connectionsTitle, progressTitle, notesTitle

  var defaultValue: String {
    switch self {
    case .dashboardTitle: "The day ahead."
    case .dashboardFooter: "Plans, tasks, notes."
    case .dashboardFooterNote: "Struktur for Mac"
    case .sidebarEyebrow: "Workspace"
    case .calendarEyebrow: "Schedule"
    case .tasksSubtitle: "Deadlines, scheduled work, and open tasks."
    case .spacesEyebrow: "Projects & areas of life"
    case .spacesTitle: "Your spaces."
    case .goalsEyebrow: "Goals"
    case .goalsTitle: "What you’re working toward."
    case .goalsSubtitle: "Track completed tasks and focus time."
    case .focusEyebrow: "Focus"
    case .focusTitle: "Time to focus."
    case .focusSubtitle: "Choose a task, set a timer, and keep notes here."
    case .insightsTitle: "Your week."
    case .insightsSubtitle: "Completed tasks and scheduled time."
    case .insightsFooter: "See where your time goes."
    case .scheduleTitle: "Your schedule"
    case .tasksTitle: "To do"
    case .connectionsTitle: "Tasks and time by space"
    case .progressTitle: "Completed"
    case .notesTitle: "Notes"
    }
  }

  var characterLimit: Int {
    switch self {
    case .tasksSubtitle, .goalsSubtitle, .focusSubtitle, .insightsSubtitle, .insightsFooter: 120
    case .sidebarEyebrow, .calendarEyebrow, .spacesEyebrow, .goalsEyebrow, .focusEyebrow,
      .dashboardFooterNote:
      40
    default: 60
    }
  }

  func normalized(_ value: String) -> String {
    value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
  }

  func override(from value: String) -> String? {
    let value = String(normalized(value).prefix(characterLimit))
    return value.isEmpty || value == defaultValue ? nil : value
  }
}

extension WorkspaceStore {
  func wording(_ key: WordingKey) -> String {
    preferences.wordingOverrides?[key.rawValue].flatMap { key.override(from: $0) }
      ?? key.defaultValue
  }

  func setWording(_ value: String, for key: WordingKey) {
    updatePreferences {
      var overrides = $0.wordingOverrides ?? [:]
      overrides[key.rawValue] = key.override(from: value)
      $0.wordingOverrides = overrides.isEmpty ? nil : overrides
    }
  }
}

/// Plain text at rest; editing is available through a double-click or accessibility action.
struct EditableWording: View {
  @EnvironmentObject private var store: WorkspaceStore
  let key: WordingKey
  var uppercase = false
  @State private var editing = false

  init(_ key: WordingKey, uppercase: Bool = false) {
    self.key = key
    self.uppercase = uppercase
  }

  private var text: Text {
    let value = store.wording(key)
    if key == .dashboardTitle && value == key.defaultValue && !uppercase {
      return Text("The day ") + Text("ahead.").italic()
    }
    return Text(verbatim: uppercase ? value.uppercased() : value)
  }

  var body: some View {
    text
      .lineLimit(2)
      .truncationMode(.tail)
      .contentShape(Rectangle())
      .onTapGesture(count: 2) { editing = true }
      .accessibilityIdentifier("wording.\(key.rawValue)")
      .accessibilityAction(named: Text("Edit wording")) { editing = true }
      .contextMenu {
        Button("Edit wording…") { editing = true }
      }
      .popover(isPresented: $editing, arrowEdge: .bottom) {
        WordingEditor(key: key, value: store.wording(key))
          .environmentObject(store)
      }
  }
}

private struct WordingEditor: View {
  @EnvironmentObject private var store: WorkspaceStore
  @Environment(\.dismiss) private var dismiss
  let key: WordingKey
  @State private var draft: String
  @FocusState private var focused: Bool

  init(key: WordingKey, value: String) {
    self.key = key
    _draft = State(initialValue: value)
  }

  private var tooLong: Bool { key.normalized(draft).count > key.characterLimit }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Edit wording").font(.strukturSerif(20))
      TextField("Wording", text: $draft)
        .textFieldStyle(.roundedBorder)
        .focused($focused)
        .onSubmit { save() }
      Text(
        tooLong ? "Use up to \(key.characterLimit) characters." : "Leave blank to use the default."
      )
      .font(.caption).foregroundStyle(tooLong ? Color.red : StrukturTheme.muted)
      HStack(spacing: 8) {
        Button("Use default") { draft = key.defaultValue }
          .buttonStyle(StrukturButtonStyle(compact: true))
        Spacer()
        Button("Cancel") { dismiss() }
          .buttonStyle(StrukturButtonStyle(compact: true)).keyboardShortcut(.cancelAction)
        Button("Save", action: save)
          .buttonStyle(StrukturButtonStyle(primary: true, compact: true))
          .keyboardShortcut(.defaultAction).disabled(tooLong)
      }
    }
    .font(.system(size: 12)).tracking(0).textCase(nil)
    .foregroundStyle(StrukturTheme.ink)
    .padding(20).frame(width: 360).background(StrukturTheme.surface)
    .onAppear { focused = true }
  }

  private func save() {
    guard !tooLong else { return }
    store.setWording(draft, for: key)
    dismiss()
  }
}
