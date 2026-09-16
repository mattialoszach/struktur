import SwiftUI
import UniformTypeIdentifiers

enum PreferencesSection: String, CaseIterable, Identifiable {
  case general, calendar, dashboard, data, apple
  var id: String { rawValue }
  var title: String { rawValue.capitalized }
  var icon: String {
    switch self {
    case .general: "paintbrush"
    case .calendar: "calendar"
    case .dashboard: "square.grid.2x2"
    case .data: "externaldrive"
    case .apple: "apple.logo"
    }
  }
}

struct PreferencesView: View {
  @EnvironmentObject private var store: WorkspaceStore
  @State private var section: PreferencesSection = .general

  var body: some View {
    HStack(spacing: 0) {
      List(PreferencesSection.allCases, selection: $section) { item in
        Label(item.title, systemImage: item.icon).tag(item)
      }
      .listStyle(.sidebar).frame(width: 180)
      Divider()
      VStack(alignment: .leading, spacing: 0) {
        Text(section.title).font(.strukturSerif(27, weight: .semibold)).padding(24)
        Divider()
        Group {
          switch section {
          case .general: GeneralPreferences()
          case .calendar: CalendarPreferences()
          case .dashboard: DashboardPreferences()
          case .data: DataPreferences()
          case .apple: AppleIntegrationPreferences()
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
    }
  }
}

struct PreferenceGroup<Content: View>: View {
  let title: String
  let detail: String
  @ViewBuilder let content: Content
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.strukturSerif(18, weight: .semibold))
        Text(detail).font(.caption).foregroundStyle(.secondary)
      }
      content
    }
    .frame(maxWidth: .infinity, alignment: .leading).strukturCard()
  }
}

struct GeneralPreferences: View {
  @EnvironmentObject private var store: WorkspaceStore
  @State private var confirmEmpty = false
  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        PreferenceGroup(
          title: "Make yourself at home", detail: "A little personal touch for your workspace."
        ) {
          TextField(
            "Your name",
            text: Binding(
              get: { store.preferences.displayName },
              set: { value in store.updatePreferences { $0.displayName = value } })
          )
          .textFieldStyle(.roundedBorder)
        }
        PreferenceGroup(
          title: "Appearance", detail: "Follow macOS or keep Struktur in your preferred theme."
        ) {
          Picker("Appearance", selection: appearance) {
            ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
          }.pickerStyle(.segmented)
        }
        PreferenceGroup(
          title: "A quieter interface",
          detail: "Pastel labels always retain enough contrast in both themes."
        ) {
          HStack(spacing: 11) {
            ForEach(AccentToken.allCases) { Circle().fill($0.color).frame(width: 25, height: 25) }
          }
        }
        if store.workspace.isDemo == true {
          PreferenceGroup(
            title: "Your fresh start",
            detail:
              "You're exploring example events, tasks, and spaces. Keep them as a starting point, or begin with a clean page."
          ) {
            HStack {
              Button("Keep the examples") {
                var workspace = store.workspace
                workspace.isDemo = false
                store.replaceWorkspace(workspace)
              }
              Button("Start empty") { confirmEmpty = true }
            }
          }
        }
        if let error = store.lastSaveError {
          Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.caption)
        } else {
          Label(
            "Your workspace is saved locally and automatically.",
            systemImage: "checkmark.circle.fill"
          )
          .font(.caption).foregroundStyle(.secondary)
        }
      }.padding(24)
    }
    .confirmationDialog(
      "Start with an empty workspace? This removes the current sample content and anything you've added to it.",
      isPresented: $confirmEmpty
    ) {
      Button("Start empty", role: .destructive) {
        var empty = Workspace()
        empty.preferences = store.preferences
        empty.scratchpad = ""
        empty.isDemo = false
        store.replaceWorkspace(empty)
      }
    }
  }
  private var appearance: Binding<AppAppearance> {
    Binding(
      get: { store.preferences.appearance },
      set: { value in store.updatePreferences { $0.appearance = value } })
  }
}

struct CalendarPreferences: View {
  @EnvironmentObject private var store: WorkspaceStore
  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        PreferenceGroup(
          title: "Calendar view",
          detail:
            "Choose your calendar's opening view. The dashboard timeline remembers its own view."
        ) {
          Picker("Default", selection: mode) {
            ForEach(CalendarViewMode.allCases) { Text($0.title).tag($0) }
          }.pickerStyle(.segmented)
        }
        PreferenceGroup(
          title: "Working window", detail: "Keep the timetable focused on the hours you use."
        ) {
          HStack {
            Stepper(
              "Starts at \(store.preferences.workingDayStart):00", value: startHour, in: 0...22)
            Spacer()
            Stepper("Ends at \(store.preferences.workingDayEnd):00", value: endHour, in: 2...24)
          }
          Toggle("Show weekends", isOn: showWeekends)
          Toggle("Start weeks on Monday", isOn: weekStartsMonday)
        }
      }.padding(24)
    }
  }
  private var mode: Binding<CalendarViewMode> {
    Binding(
      get: { store.preferences.defaultCalendarMode },
      set: { v in store.updatePreferences { $0.defaultCalendarMode = v } })
  }
  private var startHour: Binding<Int> {
    Binding(
      get: { store.preferences.workingDayStart },
      set: { v in store.updatePreferences { $0.workingDayStart = min(v, $0.workingDayEnd - 1) } })
  }
  private var endHour: Binding<Int> {
    Binding(
      get: { store.preferences.workingDayEnd },
      set: { v in store.updatePreferences { $0.workingDayEnd = max(v, $0.workingDayStart + 1) } })
  }
  private var showWeekends: Binding<Bool> {
    Binding(
      get: { store.preferences.showWeekends },
      set: { v in store.updatePreferences { $0.showWeekends = v } })
  }
  private var weekStartsMonday: Binding<Bool> {
    Binding(
      get: { store.preferences.weekStartsMonday },
      set: { v in store.updatePreferences { $0.weekStartsMonday = v } })
  }
}

struct DashboardPreferences: View {
  @EnvironmentObject private var store: WorkspaceStore
  @State private var showingLibrary = false
  @State private var resetLayout = false
  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        PreferenceGroup(
          title: "A workspace that moves with you",
          detail:
            "Use Edit layout on Your day to drag widgets into place and resize their corners. Each widget also has size and space options in its menu."
        ) {
          HStack {
            Button("Browse widgets") { showingLibrary = true }
            Button("Restore starter layout") { resetLayout = true }
          }
          Toggle(
            "Show completed tasks in the next-moves widget",
            isOn: Binding(
              get: { store.preferences.showCompletedTasks },
              set: { value in store.updatePreferences { $0.showCompletedTasks = value } }))
        }
        PreferenceGroup(
          title: "Modules",
          detail: "Turn dashboard widgets on or off. Reorder them in Customize on the overview."
        ) {
          ForEach(DashboardWidgetKind.allCases) { kind in
            Toggle(isOn: enabled(kind)) { Label(kind.title, systemImage: kind.icon) }
          }
        }
      }.padding(24)
    }
    .sheet(isPresented: $showingLibrary) { WidgetEditorSheet() }
    .confirmationDialog(
      "Restore the starter layout? Your tasks, events, and spaces stay saved.",
      isPresented: $resetLayout
    ) {
      Button("Restore layout") { store.setWidgets(WidgetConfiguration.starterLayout) }
    }
  }
  private func enabled(_ kind: DashboardWidgetKind) -> Binding<Bool> {
    Binding(
      get: { store.widgets.contains { $0.kind == kind } },
      set: { value in
        if value && !store.widgets.contains(where: { $0.kind == kind }) {
          store.setWidgets(
            store.widgets + [
              WidgetConfiguration(
                kind: kind, columns: kind == .dayFlow ? 2 : 1,
                rows: kind == .dayFlow || kind == .tasks ? 2 : 1)
            ])
        }
        if !value { store.setWidgets(store.widgets.filter { $0.kind != kind }) }
      })
  }
}

struct WorkspaceDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.json] }
  var data: Data
  init(data: Data = Data()) { self.data = data }
  init(configuration: ReadConfiguration) throws {
    data = configuration.file.regularFileContents ?? Data()
  }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}

struct DataPreferences: View {
  @EnvironmentObject private var store: WorkspaceStore
  @State private var exportDocument: WorkspaceDocument?
  @State private var exporting = false
  @State private var importing = false
  @State private var status: String?
  @State private var showingResetConfirmation = false
  @State private var exportProjectID: UUID?

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        PreferenceGroup(
          title: "Portable by design",
          detail: "Export every task, project, event, preference, and note as readable JSON."
        ) {
          Picker("Export", selection: $exportProjectID) {
            Text("Entire workspace").tag(UUID?.none)
            ForEach(store.projects) { Text("Space: " + $0.name).tag(Optional($0.id)) }
          }
          HStack {
            Button("Export workspace") {
              do {
                exportDocument = WorkspaceDocument(
                  data: try store.exportData(projectID: exportProjectID))
                exporting = true
              } catch { status = error.localizedDescription }
            }
            Button("Import workspace") { importing = true }
            Spacer()
          }
        }
        PreferenceGroup(
          title: "Local-first",
          detail: "Your data lives in Application Support/Struktur on this Mac."
        ) {
          Text("No account, analytics, or network connection is required.").font(.callout)
          Button("Restore demo workspace", role: .destructive) { showingResetConfirmation = true }
          Button("Reveal data folder") {
            NSWorkspace.shared.open(WorkspaceStore.defaultFileURL.deletingLastPathComponent())
          }
          Text(
            "A separate backup is saved beside your workspace before each import. Importing replaces the current workspace, including when importing a single space."
          )
          .font(.caption).foregroundStyle(StrukturTheme.muted)
        }
        if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
      }.padding(24)
    }
    .fileExporter(
      isPresented: $exporting, document: exportDocument, contentType: .json,
      defaultFilename: "Struktur Workspace"
    ) { result in
      switch result {
      case .success: status = "Workspace exported."
      case .failure(let error): status = error.localizedDescription
      }
    }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
      do {
        let url = try result.get()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try store.importData(Data(contentsOf: url))
        status = "Workspace imported."
      } catch { status = "Couldn’t import: \(error.localizedDescription)" }
    }
    .confirmationDialog(
      "Replace the current workspace with the demo?", isPresented: $showingResetConfirmation
    ) {
      Button("Replace workspace", role: .destructive) {
        store.replaceWorkspace(WorkspaceStore.sampleWorkspace())
      }
    }
  }
}
