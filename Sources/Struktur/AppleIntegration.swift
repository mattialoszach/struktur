import EventKit
import SwiftUI

@MainActor
final class AppleIntegrationService: ObservableObject {
  @Published var isWorking = false
  @Published var status = "Not connected"
  private let client: any AppleExchangeClient

  init(client: any AppleExchangeClient = SystemEventKitClient()) { self.client = client }

  func export(
    entries: [CalendarEntry], tasks: [TaskItem], includeEvents: Bool, includeTasks: Bool,
    didSave: (UUID, String, Bool) -> Void
  ) async throws -> IntegrationExportResult {
    guard !isWorking else { throw IntegrationError.busy }
    isWorking = true
    defer { isWorking = false }
    var result = IntegrationExportResult()
    if includeEvents {
      try await client.authorizeEvents()
      for item in entries where item.externalIdentifier == nil {
        let identifier = try await client.saveEvent(item)
        result.eventIdentifiers[item.id] = identifier
        didSave(item.id, identifier, true)
      }
    }
    if includeTasks {
      try await client.authorizeReminders()
      for item in tasks where !item.isCompleted && item.externalIdentifier == nil {
        let identifier = try await client.saveTask(item)
        result.taskIdentifiers[item.id] = identifier
        didSave(item.id, identifier, false)
      }
    }
    status =
      "Exported \(result.eventIdentifiers.count) events and \(result.taskIdentifiers.count) reminders"
    return result
  }

  func importCalendar(nextDays: Int = 90) async throws -> [CalendarEntry] {
    guard !isWorking else { throw IntegrationError.busy }
    isWorking = true
    defer { isWorking = false }
    try await client.authorizeEvents()
    return try await client.fetchEvents(
      in: DateInterval(start: Date().adding(days: -30), end: Date().adding(days: nextDays)))
  }

  func importReminders() async throws -> [TaskItem] {
    guard !isWorking else { throw IntegrationError.busy }
    isWorking = true
    defer { isWorking = false }
    try await client.authorizeReminders()
    return try await client.fetchTasks()
  }
}

struct IntegrationExportResult {
  var eventIdentifiers: [UUID: String] = [:]
  var taskIdentifiers: [UUID: String] = [:]
}

enum IntegrationError: LocalizedError {
  case accessDenied, missingCalendar, missingReminderList, busy, expandSeries
  var errorDescription: String? {
    switch self {
    case .accessDenied:
      "Access was denied. Enable Struktur in System Settings → Privacy & Security."
    case .missingCalendar: "Apple Calendar has no writable default calendar."
    case .missingReminderList: "Apple Reminders has no writable default list."
    case .busy: "Another Apple exchange is already in progress."
    case .expandSeries: "Choose an export date range to export repeating occurrences."
    }
  }
}

struct AppleIntegrationPreferences: View {
  @EnvironmentObject private var store: WorkspaceStore
  @StateObject private var service = AppleIntegrationService()
  @State private var includeEvents = true
  @State private var includeTasks = true
  @State private var projectID: UUID?
  @State private var exportStart = Date().startOfDay
  @State private var exportEnd = Date().adding(days: 90).startOfDay

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        PreferenceGroup(
          title: "Apple Calendar & Reminders",
          detail:
            "Export new items to your default calendar and reminder list. Repeating calendar blocks are exported as individual occurrences within the dates you choose."
        ) {
          StrukturMenuPicker(
            title: "Export scope", selection: $projectID,
            options: [StrukturMenuOption(value: UUID?.none, title: "All spaces")]
              + store.projects.map {
                StrukturMenuOption(value: Optional($0.id), title: $0.name)
              })
          StrukturToggleRow("Calendar blocks", isOn: $includeEvents)
          if includeEvents {
            HStack(alignment: .bottom, spacing: 18) {
              StrukturDateField("From", selection: $exportStart, displayedComponents: .date)
              StrukturDateField(
                "Through", selection: $exportEnd, minimumDate: exportStart,
                displayedComponents: .date)
            }
            Text(
              "Calendar export is limited to one year per exchange. Open tasks have no date-range limit."
            )
            .font(.caption).foregroundStyle(StrukturTheme.muted)
          }
          StrukturToggleRow("Open tasks as reminders", isOn: $includeTasks)
          HStack {
            Button("Export now") {
              Task {
                do {
                  _ = try await service.export(
                    entries: store.calendarEntries(
                      in: DateInterval(
                        start: exportStart.startOfDay, end: exportEnd.startOfDay.adding(days: 1)),
                      projectID: projectID),
                    tasks: store.tasks.filter { projectID == nil || $0.projectID == projectID },
                    includeEvents: includeEvents, includeTasks: includeTasks
                  ) { id, identifier, isEvent in
                    if isEvent {
                      store.recordAppleEventExport(id, identifier: identifier)
                    } else if var task = store.tasks.first(where: { $0.id == id }) {
                      task.externalIdentifier = identifier
                      store.update(task)
                    }
                  }
                } catch { service.status = error.localizedDescription }
              }
            }.disabled(
              service.isWorking || (!includeEvents && !includeTasks)
                || (includeEvents
                  && (exportEnd < exportStart
                    || exportEnd.timeIntervalSince(exportStart) > 366 * 86400))
            )
            Button("Import Calendar") {
              Task {
                do {
                  let imported = try await service.importCalendar()
                  var existing = Set(store.entries.compactMap(\.appleOccurrenceKey))
                  let exported = Set((store.workspace.appleEventLinks ?? [:]).values)
                  var count = 0
                  for item in imported {
                    if let id = item.externalIdentifier, exported.contains(id) { continue }
                    if let key = item.appleOccurrenceKey {
                      guard existing.insert(key).inserted else { continue }
                    }
                    store.add(item)
                    count += 1
                  }
                  service.status = "Added \(count) new calendar blocks. Existing items were kept."
                } catch { service.status = error.localizedDescription }
              }
            }.disabled(service.isWorking)
            Button("Import Reminders") {
              Task {
                do {
                  let imported = try await service.importReminders()
                  var existing = Set(store.tasks.compactMap(\.externalIdentifier))
                  var count = 0
                  for item in imported {
                    if let id = item.externalIdentifier {
                      guard existing.insert(id).inserted else { continue }
                    }
                    store.add(item)
                    count += 1
                  }
                  service.status = "Added \(count) new reminders. Existing tasks were kept."
                } catch { service.status = error.localizedDescription }
              }
            }.disabled(service.isWorking)
            if service.isWorking { ProgressView().controlSize(.small) }
            Spacer()
          }
        }
        PreferenceGroup(
          title: "Privacy", detail: "macOS will ask before Struktur can access either app."
        ) {
          Text(
            "This is a manual import/export connection. It adds new items, preserves existing ones, and never automatically syncs edits or deletions. Calendar imports cover the previous 30 and next 90 days. No content is sent to a server."
          )
          .font(.callout).foregroundStyle(.secondary)
        }
        Label(
          service.status,
          systemImage: service.isWorking ? "arrow.triangle.2.circlepath" : "info.circle"
        )
        .font(.caption).foregroundStyle(.secondary)
      }.padding(24)
    }.onChange(of: exportStart) { _, value in
      exportEnd = DateFieldValue.clamped(exportEnd, minimumDate: value)
    }
  }
}

extension CalendarEntry {
  var appleOccurrenceKey: String? {
    externalIdentifier.map { "\($0)|\(Int(start.timeIntervalSince1970))" }
  }
}
