import EventKit
import SwiftUI

@MainActor
final class AppleIntegrationService: ObservableObject {
  @Published var isWorking = false
  @Published var status = "Not connected"
  private let eventStore = EKEventStore()

  func export(
    entries: [CalendarEntry], tasks: [TaskItem], includeEvents: Bool, includeTasks: Bool,
    didSave: (UUID, String, Bool) -> Void
  ) async throws -> IntegrationExportResult {
    isWorking = true
    defer { isWorking = false }
    var result = IntegrationExportResult()

    if includeEvents {
      guard try await eventStore.requestFullAccessToEvents() else {
        throw IntegrationError.accessDenied
      }
      guard let calendar = eventStore.defaultCalendarForNewEvents else {
        throw IntegrationError.missingCalendar
      }
      for item in entries where item.externalIdentifier == nil {
        let event = EKEvent(eventStore: eventStore)
        event.title = item.title
        event.notes = item.notes
        event.startDate = item.start
        event.endDate = item.end
        event.isAllDay = item.isAllDay
        event.location = item.location
        event.calendar = calendar
        try eventStore.save(event, span: .thisEvent, commit: true)
        let identifier = event.calendarItemExternalIdentifier ?? event.calendarItemIdentifier
        result.eventIdentifiers[item.id] = identifier
        didSave(item.id, identifier, true)
      }
    }

    if includeTasks {
      guard try await eventStore.requestFullAccessToReminders() else {
        throw IntegrationError.accessDenied
      }
      guard let calendar = eventStore.defaultCalendarForNewReminders() else {
        throw IntegrationError.missingReminderList
      }
      for item in tasks where !item.isCompleted && item.externalIdentifier == nil {
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = item.title
        reminder.notes = item.notes
        reminder.calendar = calendar
        if let due = item.dueDate {
          reminder.dueDateComponents = Calendar.autoupdatingCurrent.dateComponents(
            in: .autoupdatingCurrent, from: due)
        }
        reminder.priority = item.priority == .high ? 1 : (item.priority == .low ? 9 : 5)
        try eventStore.save(reminder, commit: true)
        let identifier = reminder.calendarItemExternalIdentifier ?? reminder.calendarItemIdentifier
        result.taskIdentifiers[item.id] = identifier
        didSave(item.id, identifier, false)
      }
    }
    status =
      "Exported \(result.eventIdentifiers.count) events and \(result.taskIdentifiers.count) reminders"
    return result
  }

  func importCalendar(nextDays: Int = 90) async throws -> [CalendarEntry] {
    isWorking = true
    defer { isWorking = false }
    guard try await eventStore.requestFullAccessToEvents() else {
      throw IntegrationError.accessDenied
    }
    let start = Date().adding(days: -30)
    let end = Date().adding(days: nextDays)
    let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
    let entries = eventStore.events(matching: predicate).map { event in
      CalendarEntry(
        title: event.title ?? "Untitled event",
        notes: event.notes ?? "",
        start: event.startDate,
        end: event.endDate,
        kind: .personal,
        color: .sky,
        location: event.location ?? "",
        isAllDay: event.isAllDay,
        externalIdentifier: event.calendarItemExternalIdentifier ?? event.calendarItemIdentifier
      )
    }
    status = "Imported \(entries.count) calendar events"
    return entries
  }

  func importReminders() async throws -> [TaskItem] {
    isWorking = true
    defer { isWorking = false }
    guard try await eventStore.requestFullAccessToReminders() else {
      throw IntegrationError.accessDenied
    }
    let predicate = eventStore.predicateForReminders(in: nil)
    let tasks: [TaskItem] = await withCheckedContinuation { continuation in
      eventStore.fetchReminders(matching: predicate) { reminders in
        let tasks = (reminders ?? []).map { reminder in
          TaskItem(
            title: reminder.title ?? "Untitled reminder",
            notes: reminder.notes ?? "",
            isCompleted: reminder.isCompleted,
            completedAt: reminder.completionDate,
            dueDate: reminder.dueDateComponents.flatMap {
              Calendar.autoupdatingCurrent.date(from: $0)
            },
            priority: reminder.priority > 0 && reminder.priority <= 4
              ? .high : (reminder.priority >= 6 ? .low : .normal),
            color: .mint,
            externalIdentifier: reminder.calendarItemExternalIdentifier
              ?? reminder.calendarItemIdentifier
          )
        }
        continuation.resume(returning: tasks)
      }
    }
    status = "Found \(tasks.count) reminders"
    return tasks
  }
}

struct IntegrationExportResult {
  var eventIdentifiers: [UUID: String] = [:]
  var taskIdentifiers: [UUID: String] = [:]
}

enum IntegrationError: LocalizedError {
  case accessDenied, missingCalendar, missingReminderList
  var errorDescription: String? {
    switch self {
    case .accessDenied:
      "Access was denied. Enable Struktur in System Settings → Privacy & Security."
    case .missingCalendar: "Apple Calendar has no writable default calendar."
    case .missingReminderList: "Apple Reminders has no writable default list."
    }
  }
}

struct AppleIntegrationPreferences: View {
  @EnvironmentObject private var store: WorkspaceStore
  @StateObject private var service = AppleIntegrationService()
  @State private var includeEvents = true
  @State private var includeTasks = true
  @State private var projectID: UUID?

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        PreferenceGroup(
          title: "Apple Calendar & Reminders",
          detail:
            "Export new items to your default calendar and reminder list. Choose a space, or bring everything along."
        ) {
          Picker("Export scope", selection: $projectID) {
            Text("All spaces").tag(UUID?.none)
            ForEach(store.projects) { Text($0.name).tag(Optional($0.id)) }
          }
          Toggle("Calendar blocks", isOn: $includeEvents)
          Toggle("Open tasks as reminders", isOn: $includeTasks)
          HStack {
            Button("Export now") {
              Task {
                do {
                  _ = try await service.export(
                    entries: store.entries.filter { projectID == nil || $0.projectID == projectID },
                    tasks: store.tasks.filter { projectID == nil || $0.projectID == projectID },
                    includeEvents: includeEvents, includeTasks: includeTasks
                  ) { id, identifier, isEvent in
                    if isEvent, var entry = store.entries.first(where: { $0.id == id }) {
                      entry.externalIdentifier = identifier
                      store.update(entry)
                    } else if var task = store.tasks.first(where: { $0.id == id }) {
                      task.externalIdentifier = identifier
                      store.update(task)
                    }
                  }
                } catch { service.status = error.localizedDescription }
              }
            }.disabled(service.isWorking || (!includeEvents && !includeTasks))
            Button("Import Calendar") {
              Task {
                do {
                  let imported = try await service.importCalendar()
                  var existing = Set(store.entries.compactMap(\.appleOccurrenceKey))
                  var count = 0
                  for item in imported {
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
    }
  }
}

extension CalendarEntry {
  var appleOccurrenceKey: String? {
    externalIdentifier.map { "\($0)|\(Int(start.timeIntervalSince1970))" }
  }
}
