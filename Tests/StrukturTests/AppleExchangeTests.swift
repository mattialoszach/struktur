import XCTest

@testable import Struktur

@MainActor
private final class FakeAppleClient: AppleExchangeClient {
  var eventAccess = true
  var reminderAccess = true
  var events: [CalendarEntry] = []
  var tasks: [TaskItem] = []
  var failAfterEvents: Int?
  var authorizationCalls = 0
  func authorizeEvents() async throws {
    authorizationCalls += 1
    if !eventAccess { throw IntegrationError.accessDenied }
  }
  func authorizeReminders() async throws {
    authorizationCalls += 1
    if !reminderAccess { throw IntegrationError.accessDenied }
  }
  func saveEvent(_ entry: CalendarEntry) async throws -> String {
    if let limit = failAfterEvents, events.count >= limit { throw IntegrationError.missingCalendar }
    events.append(entry)
    return "apple-event-\(entry.id)"
  }
  func saveTask(_ task: TaskItem) async throws -> String {
    tasks.append(task)
    return "apple-task-\(task.id)"
  }
  func fetchEvents(in window: DateInterval) async throws -> [CalendarEntry] {
    events.filter { $0.start < window.end && $0.end > window.start }
  }
  func fetchTasks() async throws -> [TaskItem] { tasks }
}

@MainActor
final class AppleExchangeTests: XCTestCase {
  func testDeniedPermissionPerformsNoWritesAndReleasesBusyState() async {
    let fake = FakeAppleClient()
    fake.eventAccess = false
    let service = AppleIntegrationService(client: fake)
    do {
      _ = try await service.export(
        entries: [event()], tasks: [], includeEvents: true, includeTasks: false
      ) { _, _, _ in XCTFail("No successful export expected") }
      XCTFail("Expected denied access")
    } catch {}
    XCTAssertTrue(fake.events.isEmpty)
    XCTAssertFalse(service.isWorking)
  }
  func testPartialFailureRecordsSuccessfulExportsBeforeReturningError() async {
    let fake = FakeAppleClient()
    fake.failAfterEvents = 1
    let service = AppleIntegrationService(client: fake)
    let first = event()
    let second = event()
    var saved: [UUID] = []
    do {
      _ = try await service.export(
        entries: [first, second], tasks: [], includeEvents: true, includeTasks: false
      ) { id, _, _ in saved.append(id) }
      XCTFail("Expected failure")
    } catch {}
    XCTAssertEqual(saved, [first.id])
    XCTAssertEqual(fake.events.count, 1)
    XCTAssertFalse(service.isWorking)
  }
  func testRetrySkipsKnownLinksAndCompletedTasks() async throws {
    let fake = FakeAppleClient()
    let service = AppleIntegrationService(client: fake)
    var known = event()
    known.externalIdentifier = "already-exported"
    let fresh = event()
    let pending = TaskItem(title: "Open")
    let completed = TaskItem(title: "Done", isCompleted: true)
    let linked = TaskItem(title: "Known", externalIdentifier: "existing")
    let result = try await service.export(
      entries: [known, fresh], tasks: [pending, completed, linked],
      includeEvents: true, includeTasks: true
    ) { _, _, _ in }
    XCTAssertEqual(fake.events.map(\.id), [fresh.id])
    XCTAssertEqual(fake.tasks.map(\.id), [pending.id])
    XCTAssertEqual(result.eventIdentifiers.count, 1)
    XCTAssertEqual(result.taskIdentifiers.count, 1)
  }
  func testImportsUseRequestedWindowAndNeverWrite() async throws {
    let fake = FakeAppleClient()
    let recent = event()
    var distant = event()
    distant.start = Date().adding(days: 500)
    distant.end = distant.start.addingTimeInterval(3600)
    fake.events = [recent, distant]
    fake.tasks = [TaskItem(title: "Imported")]
    let service = AppleIntegrationService(client: fake)
    let events = try await service.importCalendar()
    let tasks = try await service.importReminders()
    XCTAssertEqual(events.map(\.id), [recent.id])
    XCTAssertEqual(tasks.count, 1)
    XCTAssertEqual(fake.events.count, 2)
    XCTAssertEqual(fake.authorizationCalls, 2)
  }
  func testExportedRecurringOccurrenceLinkPersistsWithoutCreatingException() throws {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "struktur-apple-test-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "workspace.json")
    let store = WorkspaceStore(fileURL: url)
    store.replaceWorkspace(Workspace())
    var master = event()
    master.recurrence = CalendarRecurrence()
    store.add(master)
    let occurrence = try XCTUnwrap(master.occurrence(at: 1))
    store.recordAppleEventExport(occurrence.id, identifier: "external")
    XCTAssertEqual(store.entries.count, 1)
    XCTAssertEqual(
      WorkspaceStore(fileURL: url).calendarEntries(on: occurrence.start).first?.externalIdentifier,
      "external")
  }
  private func event() -> CalendarEntry {
    CalendarEntry(
      title: "QA", start: Date().startOfDay.setting(hour: 9),
      end: Date().startOfDay.setting(hour: 10))
  }
}
