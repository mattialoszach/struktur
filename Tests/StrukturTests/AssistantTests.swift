import XCTest
@testable import Struktur

@MainActor
final class AssistantTests: XCTestCase {
  private var directory: URL!
  private var store: WorkspaceStore!
  override func setUp() async throws {
    directory = FileManager.default.temporaryDirectory.appending(path: "struktur-assistant-tests-\(UUID())")
    store = WorkspaceStore(fileURL: directory.appending(path: "workspace.json"))
    store.replaceWorkspace(Workspace())
    store.updatePreferences { $0.assistant = AssistantPreferences(provider: .openAI) }
  }
  override func tearDown() async throws {
    store = nil
    try? FileManager.default.removeItem(at: directory)
  }

  func testKeychainSaveReplaceAndRemoveInIsolatedService() throws {
    let keychain = AssistantKeychain(service: "app.struktur.assistant.tests.\(UUID())")
    defer { try? keychain.remove() }
    XCTAssertNil(try keychain.read())
    try keychain.save("test-placeholder-one")
    XCTAssertEqual(try keychain.read(), "test-placeholder-one")
    try keychain.save("test-placeholder-two")
    XCTAssertEqual(try keychain.read(), "test-placeholder-two")
    XCTAssertThrowsError(try keychain.save("invalid whitespace key"))
    XCTAssertEqual(try keychain.read(), "test-placeholder-two")
    try keychain.remove()
    XCTAssertNil(try keychain.read())
  }

  func testLegacyPreferencesAndConfiguredModelRoundTrip() throws {
    let legacy = try JSONDecoder().decode(UserPreferences.self, from: Data("{}".utf8))
    XCTAssertNil(legacy.assistant)
    XCTAssertEqual((legacy.assistant ?? AssistantPreferences()).model, "gpt-4.1-mini")
    store.updatePreferences { $0.assistant = AssistantPreferences(model: "my-model"); $0.appearance = .dark }
    let restored = WorkspaceStore(fileURL: directory.appending(path: "workspace.json"))
    XCTAssertEqual(restored.preferences.assistant?.model, "my-model")
    XCTAssertEqual(restored.preferences.appearance, .dark)
    XCTAssertFalse(String(decoding: try store.exportData(), as: UTF8.self).contains("apiKey"))
  }

  func testContextScopesExcludePrivateBodiesAndDeletedNotes() throws {
    let project = Project(name: "Study", color: .mint)
    store.add(project)
    store.add(TaskItem(title: "Read chapter", notes: "PRIVATE TASK BODY", dueDate: Date(), projectID: project.id))
    store.add(CalendarEntry(title: "Lecture", notes: "PRIVATE EVENT BODY", start: Date(), end: Date().addingTimeInterval(3600)))
    let noteID = store.createNote(title: "Lecture note", markdown: "NOTE BODY")
    store.createNote(title: "Other note", markdown: "OTHER PRIVATE NOTE")
    store.revealNote(noteID)
    let schedule = try store.assistantContext(scope: .schedule, anchor: Date())
    XCTAssertTrue(schedule.json.contains("Read chapter"))
    XCTAssertFalse(schedule.json.contains("PRIVATE"))
    XCTAssertFalse(schedule.json.contains("NOTE BODY"))
    XCTAssertEqual(schedule.projectIDs, [project.id])
    let note = try store.assistantContext(scope: .note, anchor: Date())
    XCTAssertTrue(note.json.contains("NOTE BODY"))
    XCTAssertFalse(note.json.contains("OTHER PRIVATE"))
    XCTAssertFalse(note.json.contains("Read chapter"))
    XCTAssertTrue(note.projectIDs.isEmpty)
    let message = try store.assistantContext(scope: .message, anchor: Date())
    XCTAssertFalse(message.json.contains("Lecture"))
    XCTAssertFalse(message.json.contains(project.id.uuidString))
    store.editNote(noteID) { $0.deletedAt = Date() }
    XCTAssertThrowsError(try store.assistantContext(scope: .note, anchor: Date()))
  }

  func testContextBoundsAndRecurringOccurrences() throws {
    let now = Date().startOfDay.setting(hour: 9)
    var workspace = Workspace()
    workspace.tasks = (0..<120).map { TaskItem(title: "Task \($0)", dueDate: now.adding(days: $0)) }
    workspace.calendarEntries = [CalendarEntry(title: "Weekly lecture", start: now,
      end: now.addingTimeInterval(3600), recurrence: CalendarRecurrence())]
    store.replaceWorkspace(workspace)
    let context = try store.assistantContext(scope: .schedule, anchor: now)
    let data = try XCTUnwrap(context.json.data(using: .utf8))
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual((json["tasks"] as? [[String: Any]])?.count, 100)
    XCTAssertEqual((json["omitted"] as? [String: Int])?["tasks"], 20)
    XCTAssertEqual((json["events"] as? [[String: Any]])?.count, 2)
    XCTAssertTrue(context.summary.contains("limited"))
  }

  func testBatchCreatePersistsStableIDsAndUndo() throws {
    let now = Date()
    let task = AssistantAction(kind: .task, title: "Read", dueDate: now.addingTimeInterval(7200),
      start: now, estimateMinutes: 45)
    let event = AssistantAction(kind: .event, title: "Lecture", start: now.addingTimeInterval(7200), end: now.addingTimeInterval(10800))
    let receipt = try store.applyAssistantActions([task, event], generation: store.workspaceGeneration)
    XCTAssertEqual(store.tasks.map(\.id), [task.id])
    XCTAssertEqual(store.entries.map(\.id), [event.id])
    XCTAssertEqual(store.tasks.first?.plannedStart, now)
    XCTAssertEqual(store.tasks.first?.dueDate, now.addingTimeInterval(7200))
    let restored = WorkspaceStore(fileURL: directory.appending(path: "workspace.json"))
    XCTAssertEqual(restored.tasks.first?.id, task.id)
    XCTAssertEqual(restored.entries.first?.id, event.id)
    try restored.workspace.validate()
    XCTAssertThrowsError(try store.applyAssistantActions([task, event], generation: store.workspaceGeneration))
    XCTAssertEqual(store.tasks.count, 1)
    try store.undoAssistantActions(receipt)
    XCTAssertTrue(store.tasks.isEmpty)
    XCTAssertTrue(store.entries.isEmpty)
    XCTAssertTrue(WorkspaceStore(fileURL: directory.appending(path: "workspace.json")).tasks.isEmpty)
  }

  func testInvalidBatchIsAtomicAndStaleWorkspaceRejected() throws {
    let valid = AssistantAction(kind: .task, title: "Valid")
    let invalid = AssistantAction(kind: .event, title: "Invalid", start: Date(), end: Date().addingTimeInterval(-3600))
    XCTAssertThrowsError(try store.applyAssistantActions([valid, invalid], generation: store.workspaceGeneration))
    XCTAssertTrue(store.tasks.isEmpty)
    let generation = store.workspaceGeneration
    store.replaceWorkspace(Workspace())
    XCTAssertThrowsError(try store.applyAssistantActions([valid], generation: generation))
    XCTAssertThrowsError(try store.applyAssistantActions([AssistantAction(kind: .task, title: "Unknown space", projectID: UUID())], generation: store.workspaceGeneration))
    XCTAssertTrue(store.tasks.isEmpty)
  }

  func testUnreadableWorkspaceNeverOverwrittenByAssistant() throws {
    let url = directory.appending(path: "damaged.json")
    let original = Data("not valid JSON".utf8)
    try original.write(to: url)
    let damaged = WorkspaceStore(fileURL: url)
    XCTAssertThrowsError(try damaged.applyAssistantActions([AssistantAction(kind: .task, title: "Hello")], generation: damaged.workspaceGeneration))
    XCTAssertEqual(try Data(contentsOf: url), original)
    XCTAssertTrue(damaged.tasks.isEmpty)
  }

  func testUndoPreservesEditedAndReferencedItems() throws {
    let action = AssistantAction(kind: .task, title: "Original")
    let receipt = try store.applyAssistantActions([action], generation: store.workspaceGeneration)
    var edited = try XCTUnwrap(store.tasks.first)
    edited.title = "Edited later"
    store.update(edited)
    XCTAssertThrowsError(try store.undoAssistantActions(receipt))
    XCTAssertEqual(store.tasks.first?.title, "Edited later")
    store.update(receipt.tasks[0])
    store.saveGoal(TrackedGoal(title: "Goal", taskIDs: [action.id]))
    XCTAssertThrowsError(try store.undoAssistantActions(receipt))
    XCTAssertEqual(store.tasks.count, 1)
  }

  func testConflictsIncludeRecurrenceScheduledWorkAndOtherProposals() {
    let start = Date().startOfDay.setting(hour: 10)
    store.add(CalendarEntry(title: "Weekly lecture", start: start.adding(days: -7), end: start.adding(days: -7).addingTimeInterval(3600), recurrence: CalendarRecurrence()))
    store.add(TaskItem(title: "Scheduled reading", plannedStart: start.addingTimeInterval(-900), estimateMinutes: 60))
    let action = AssistantAction(kind: .event, title: "Proposed", start: start, end: start.addingTimeInterval(3600))
    let other = AssistantAction(kind: .task, title: "Other proposal", start: start, estimateMinutes: 30)
    XCTAssertEqual(Set(store.assistantConflicts(action, among: [action, other])), ["Weekly lecture", "Scheduled reading", "Other proposal"])
    let adjacent = AssistantAction(kind: .event, title: "Afterwards", start: start.addingTimeInterval(3600), end: start.addingTimeInterval(7200))
    XCTAssertTrue(store.assistantConflicts(adjacent, among: [action]).isEmpty)
  }

  func testDatesAndTaskDeadlineValidation() throws {
    XCTAssertEqual(try AssistantWireReply.date("2026-10-25T09:00:00+01:00"),
      try AssistantWireReply.date("2026-10-25T08:00:00Z"))
    XCTAssertNotNil(try AssistantWireReply.date("2026-10-25T08:00:00.123Z"))
    XCTAssertThrowsError(try AssistantWireReply.date("2026-10-25T09:00:00"))
    XCTAssertThrowsError(try AssistantWireReply.date("tomorrow"))
    let start = Date()
    XCTAssertThrowsError(try AssistantAction(kind: .task, title: "Late", dueDate: start.addingTimeInterval(600), start: start).validate(projectIDs: []))
    XCTAssertNoThrow(try AssistantAction(kind: .task, title: "No estimate").validate(projectIDs: []))
    XCTAssertThrowsError(try AssistantAction(kind: .task, title: "Scheduled without duration", start: start).validate(projectIDs: []))
    XCTAssertThrowsError(try AssistantAction(kind: .task, title: " ").validate(projectIDs: []))
    XCTAssertThrowsError(try AssistantAction(kind: .task, title: "Bad duration", estimateMinutes: 0).validate(projectIDs: []))
  }

  func testRequestUsesStructuredOutputAndNoServerStorage() throws {
    let request = try OpenAIAssistantClient.request(prompt: "Hello", context: AssistantContext(json: "{}", summary: "", projectIDs: []), history: [], model: "gpt-4.1-mini", apiKey: "test-key")
    XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    XCTAssertEqual(json["store"] as? Bool, false)
    let format = (json["text"] as? [String: Any])?["format"] as? [String: Any]
    XCTAssertEqual(format?["type"] as? String, "json_schema")
    XCTAssertEqual(format?["strict"] as? Bool, true)
    XCTAssertFalse(String(decoding: request.httpBody!, as: UTF8.self).contains("test-key"))
    XCTAssertThrowsError(try OpenAIAssistantClient.request(prompt: "Hi", context: AssistantContext(json: "{}", summary: "", projectIDs: []), history: [], model: "", apiKey: "test"))
  }

  private func response(action: [String: Any]? = nil, status: String = "completed") throws -> Data {
    let content = try JSONSerialization.data(withJSONObject: ["message": "Ready to review.", "actions": action.map { [$0] } ?? []])
    return try JSONSerialization.data(withJSONObject: ["status": status, "output": [
      ["type": "message", "content": [["type": "output_text", "text": String(decoding: content, as: UTF8.self)]]],
    ]])
  }

  func testResponseDecodingRejectsInvalidToolsAndIncompleteOutput() throws {
    var action: [String: Any] = ["kind": "task", "title": "Study", "notes": "", "projectID": NSNull(),
      "dueDate": NSNull(), "start": NSNull(), "end": NSNull(), "estimateMinutes": 30,
      "priority": "normal", "eventKind": "personal", "location": ""]
    let reply = try OpenAIAssistantClient.decode(response(action: action), status: 200, projectIDs: [])
    XCTAssertEqual(reply.actions.first?.title, "Study")
    XCTAssertNil(reply.actions.first?.dueDate)
    action["estimateMinutes"] = NSNull()
    let noEstimate = try OpenAIAssistantClient.decode(response(action: action), status: 200, projectIDs: [])
    XCTAssertNil(noEstimate.actions.first?.estimateMinutes)
    action["kind"] = "delete_task"
    XCTAssertThrowsError(try OpenAIAssistantClient.decode(response(action: action), status: 200, projectIDs: []))
    action["kind"] = "task"; action["projectID"] = UUID().uuidString
    XCTAssertThrowsError(try OpenAIAssistantClient.decode(response(action: action), status: 200, projectIDs: []))
    XCTAssertThrowsError(try OpenAIAssistantClient.decode(response(status: "incomplete"), status: 200, projectIDs: []))
    XCTAssertThrowsError(try OpenAIAssistantClient.decode(Data("garbage".utf8), status: 200, projectIDs: []))
    let refusal = Data(#"{"status":"completed","output":[{"type":"message","content":[{"type":"refusal","refusal":"No"}]}]}"#.utf8)
    XCTAssertTrue(try OpenAIAssistantClient.decode(refusal, status: 200, projectIDs: []).actions.isEmpty)
    for code in [401, 403, 404, 429, 500] {
      XCTAssertThrowsError(try OpenAIAssistantClient.decode(Data(), status: code, projectIDs: []))
    }
  }

  func testSessionReviewApplyUndoAndContextReset() async {
    let session = AssistantSession(client: FakeAssistantClient(), credentials: FakeCredentials())
    session.refreshConnection(preferences: AssistantPreferences(provider: .openAI))
    XCTAssertTrue(session.hasKey)
    session.setContextIdentity("schedule")
    session.draft = "Create a task"
    session.send(store: store, anchor: Date())
    await session.waitForResponse()
    XCTAssertEqual(session.proposals.count, 1)
    XCTAssertTrue(store.tasks.isEmpty, "A response must not write before review")
    session.apply(store: store)
    XCTAssertEqual(store.tasks.count, 1)
    session.apply(store: store)
    XCTAssertEqual(store.tasks.count, 1)
    session.undo(store: store)
    XCTAssertTrue(store.tasks.isEmpty)
    session.setContextIdentity("note")
    XCTAssertTrue(session.turns.isEmpty)
    XCTAssertTrue(session.proposals.isEmpty)
  }

  func testCancellationAndLateReplyCannotCreateProposals() async throws {
    let session = AssistantSession(client: FakeAssistantClient(delay: .milliseconds(80)), credentials: FakeCredentials())
    session.draft = "Keep my request"
    session.send(store: store, anchor: Date())
    session.stop()
    try await Task.sleep(for: .milliseconds(120))
    XCTAssertFalse(session.isWorking)
    XCTAssertTrue(session.proposals.isEmpty)
    XCTAssertTrue(session.turns.isEmpty)
    XCTAssertEqual(session.draft, "Keep my request")
    XCTAssertTrue(store.tasks.isEmpty)
  }

  func testWorkspaceReplacementDuringRequestRejectsResult() async {
    let session = AssistantSession(client: FakeAssistantClient(delay: .milliseconds(40)), credentials: FakeCredentials())
    session.draft = "Create a task"
    session.send(store: store, anchor: Date())
    store.replaceWorkspace(Workspace())
    await session.waitForResponse()
    XCTAssertTrue(session.proposals.isEmpty)
    XCTAssertTrue(store.tasks.isEmpty)
    XCTAssertNotNil(session.error)
    XCTAssertEqual(session.draft, "Create a task")
  }

  func testNetworkFailurePreservesDraftAndDoesNotMutateWorkspace() async {
    let session = AssistantSession(client: FakeAssistantClient(fails: true), credentials: FakeCredentials())
    session.draft = "Please keep this"
    session.send(store: store, anchor: Date())
    await session.waitForResponse()
    XCTAssertFalse(session.isWorking)
    XCTAssertEqual(session.draft, "Please keep this")
    XCTAssertTrue(session.turns.isEmpty)
    XCTAssertNotNil(session.error)
    XCTAssertTrue(store.tasks.isEmpty)
    let unconfigured = AssistantSession(client: FakeAssistantClient(), credentials: FakeCredentials(key: nil))
    unconfigured.draft = "No key"
    unconfigured.send(store: store, anchor: Date())
    XCTAssertFalse(unconfigured.isWorking)
    XCTAssertEqual(unconfigured.draft, "No key")
  }
}

private struct FakeCredentials: AssistantCredentialStore {
  var key: String? = "test-only"
  func read() throws -> String? { key }
  func save(_ key: String) throws {}
  func remove() throws {}
}
private struct FakeAssistantClient: AssistantServing {
  var delay: Duration = .zero
  var fails = false
  func respond(prompt: String, context: AssistantContext, history: [AssistantTurn], model: String, apiKey: String) async throws -> AssistantReply {
    // Deliberately ignore cancellation to verify the session's independent generation guard.
    try? await Task.sleep(for: delay)
    if fails { throw AssistantFailure("Test connection failed") }
    return AssistantReply(message: "Ready to review", actions: [AssistantAction(kind: .task, title: "Study")])
  }
}

private final class AssistantURLProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let payload = #"{"message":"From the transport","actions":[{"kind":"task","title":"Transport task","notes":"","projectID":null,"dueDate":null,"start":null,"end":null,"estimateMinutes":25,"priority":"normal","eventKind":"personal","location":""}]}"#
    let data = try! JSONSerialization.data(withJSONObject: ["status": "completed", "output": [
      ["type": "message", "content": [["type": "output_text", "text": payload]]],
    ]])
    client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

extension AssistantTests {
  func testURLSessionThroughReviewAndPersistence() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AssistantURLProtocol.self]
    let transport = URLSession(configuration: configuration)
    defer { transport.invalidateAndCancel() }
    let assistant = AssistantSession(client: OpenAIAssistantClient(session: transport), credentials: FakeCredentials())
    assistant.draft = "Create a task"
    assistant.send(store: store, anchor: Date())
    await assistant.waitForResponse()
    XCTAssertNil(assistant.error)
    XCTAssertEqual(assistant.proposals.first?.title, "Transport task")
    XCTAssertTrue(store.tasks.isEmpty)
    assistant.apply(store: store)
    let restored = WorkspaceStore(fileURL: directory.appending(path: "workspace.json"))
    XCTAssertEqual(restored.tasks.first?.title, "Transport task")
    XCTAssertEqual(restored.tasks.first?.estimateMinutes, 25)
  }
}
