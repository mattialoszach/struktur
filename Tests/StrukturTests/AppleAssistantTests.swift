import XCTest
#if canImport(FoundationModels)
import FoundationModels
#endif
@testable import Struktur

@MainActor
final class AppleAssistantTests: XCTestCase {
  private var directory: URL!
  private var store: WorkspaceStore!
  override func setUp() async throws {
    directory = FileManager.default.temporaryDirectory.appending(path: "struktur-foundation-tests-\(UUID())")
    store = WorkspaceStore(fileURL: directory.appending(path: "workspace.json"))
    store.replaceWorkspace(Workspace())
  }
  override func tearDown() async throws {
    store = nil
    try? FileManager.default.removeItem(at: directory)
  }

  func testAppleIsDefaultAndLegacyModelChoiceIsRetained() throws {
    XCTAssertEqual(AssistantPreferences().provider, .apple)
    let legacy = try JSONDecoder().decode(AssistantPreferences.self, from: Data(#"{"model":"custom-model"}"#.utf8))
    XCTAssertEqual(legacy.provider, .apple)
    XCTAssertEqual(legacy.model, "custom-model")
    store.updatePreferences { $0.assistant = AssistantPreferences(model: "custom-model", provider: .openAI) }
    let restored = WorkspaceStore(fileURL: directory.appending(path: "workspace.json"))
    XCTAssertEqual(restored.preferences.assistant?.provider, .openAI)
    XCTAssertEqual(restored.preferences.assistant?.model, "custom-model")
  }

  func testAppleNeedsNoCredentialAndDoesNotCallCloud() async {
    let local = RecordingAssistantClient()
    let cloud = RecordingAssistantClient()
    let session = AssistantSession(client: cloud, credentials: ForbiddenCredentials(), appleClient: local, appleAvailability: { .available })
    session.refreshConnection()
    XCTAssertTrue(session.isReady)
    XCTAssertFalse(session.hasKey)
    session.draft = "Create a task"
    session.send(store: store, anchor: Date())
    await session.waitForResponse()
    XCTAssertNil(session.error)
    XCTAssertEqual(session.proposals.count, 1)
    let localCalls = await local.calls
    let cloudCalls = await cloud.calls
    XCTAssertEqual(localCalls, 1)
    XCTAssertEqual(cloudCalls, 0)
    XCTAssertTrue(store.tasks.isEmpty)
    session.apply(store: store)
    XCTAssertEqual(store.tasks.first?.title, "Local draft")
    session.undo(store: store)
    XCTAssertTrue(store.tasks.isEmpty)
  }

  func testUnavailableAndFailedAppleNeverFallBackAutomatically() async {
    let cloud = RecordingAssistantClient()
    for availability: AppleAssistantAvailability in [.requiresNewerOS, .deviceNotEligible, .notEnabled, .modelNotReady, .unknown] {
      let local = RecordingAssistantClient()
      let session = AssistantSession(client: cloud, credentials: ForbiddenCredentials(), appleClient: local, appleAvailability: { availability })
      session.refreshConnection()
      XCTAssertFalse(session.isReady)
      session.draft = "Private message"
      session.send(store: store, anchor: Date())
      await session.waitForResponse()
      XCTAssertNotNil(session.error)
      XCTAssertEqual(session.draft, "Private message")
      let count = await local.calls
      XCTAssertEqual(count, 0)
    }
    let failing = RecordingAssistantClient(fails: true)
    let session = AssistantSession(client: cloud, credentials: ForbiddenCredentials(), appleClient: failing, appleAvailability: { .available })
    session.draft = "Keep this local"
    session.send(store: store, anchor: Date())
    await session.waitForResponse()
    XCTAssertNotNil(session.error)
    XCTAssertEqual(session.draft, "Keep this local")
    let calls = await cloud.calls
    XCTAssertEqual(calls, 0)
    XCTAssertTrue(store.tasks.isEmpty)
  }

  func testExplicitCloudChoiceRoutesOnlyToCloudAndClearsConversation() async {
    let local = RecordingAssistantClient()
    let cloud = RecordingAssistantClient()
    let session = AssistantSession(client: cloud, credentials: TestCredentials(), appleClient: local, appleAvailability: { .available })
    session.draft = "Private note summary"
    session.send(store: store, anchor: Date())
    await session.waitForResponse()
    XCTAssertEqual(session.turns.count, 2)
    store.updatePreferences { $0.assistant = AssistantPreferences(provider: .openAI) }
    session.refreshConnection(preferences: store.preferences.assistant!)
    XCTAssertTrue(session.turns.isEmpty)
    XCTAssertTrue(session.proposals.isEmpty)
    session.draft = "Cloud request"
    session.send(store: store, anchor: Date())
    await session.waitForResponse()
    let histories = await cloud.histories
    XCTAssertEqual(histories.count, 1)
    XCTAssertEqual(histories.first, [])
    let localCalls = await local.calls
    XCTAssertEqual(localCalls, 1)
  }

  func testProviderChangeWhileRespondingDiscardsOldResult() async {
    let local = RecordingAssistantClient(delay: .milliseconds(30))
    let session = AssistantSession(credentials: ForbiddenCredentials(), appleClient: local, appleAvailability: { .available })
    session.draft = "Create privately"
    session.send(store: store, anchor: Date())
    store.updatePreferences { $0.assistant = AssistantPreferences(provider: .openAI) }
    await session.waitForResponse()
    XCTAssertTrue(session.proposals.isEmpty)
    XCTAssertTrue(session.turns.isEmpty)
    XCTAssertTrue(store.tasks.isEmpty)
    XCTAssertEqual(session.draft, "Create privately")
  }

  func testSwitchingProviderCancelsRequestAndRestoresDraft() async throws {
    let local = RecordingAssistantClient(delay: .milliseconds(80))
    let session = AssistantSession(credentials: TestCredentials(), appleClient: local, appleAvailability: { .available })
    session.draft = "Do not lose this request"
    session.send(store: store, anchor: Date())
    store.updatePreferences { $0.assistant = AssistantPreferences(provider: .openAI) }
    session.refreshConnection(preferences: store.preferences.assistant!)
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertFalse(session.isWorking)
    XCTAssertEqual(session.draft, "Do not lose this request")
    XCTAssertTrue(session.turns.isEmpty)
    XCTAssertTrue(session.proposals.isEmpty)
  }

  func testLocalContextIsValidBoundedJSONAndMarksEveryOmission() throws {
    let project = Project(name: "Research", color: .sky)
    var workspace = Workspace(projects: [project])
    let now = Date().startOfDay.setting(hour: 10)
    workspace.tasks = (0..<30).map { TaskItem(title: "Study \($0) " + String(repeating: "📚", count: 150), projectID: project.id) }
    workspace.calendarEntries = (0..<20).map { CalendarEntry(title: "Block \($0)", start: now.addingTimeInterval(Double($0) * 1800), end: now.addingTimeInterval(Double($0 + 1) * 1800)) }
    store.replaceWorkspace(workspace)
    let context = try store.assistantContext(scope: .schedule, anchor: now, provider: .apple)
    XCTAssertLessThanOrEqual(context.json.utf8.count, AppleAssistantContext.maximumBytes)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(context.json.utf8)) as? [String: Any])
    let omitted = try XCTUnwrap(json["omitted"] as? [String: Int])
    XCTAssertEqual((json["tasks"] as? [Any])!.count + omitted["tasks"]!, 30)
    XCTAssertEqual((json["events"] as? [Any])!.count + omitted["events"]!, 20)
    XCTAssertTrue(context.summary.contains("limited"))
    XCTAssertEqual(context.projectIDs, [project.id])
  }

  func testLongUnicodeNoteIsExplicitlyAnExcerptWithoutOtherNotes() throws {
    let id = store.createNote(title: "Long note", markdown: String(repeating: "☕️ Study café 文学\n", count: 2000))
    store.createNote(title: "Hidden", markdown: "UNRELATED PRIVATE BODY")
    store.revealNote(id)
    let context = try store.assistantContext(scope: .note, anchor: Date(), provider: .apple)
    XCTAssertLessThanOrEqual(context.json.utf8.count, AppleAssistantContext.maximumBytes)
    XCTAssertTrue(context.summary.contains("excerpt only"))
    XCTAssertFalse(context.json.contains("UNRELATED"))
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(context.json.utf8)) as? [String: Any])
    XCTAssertEqual((json["note"] as? [String: Any])?["truncated"] as? Bool, true)
    XCTAssertTrue(context.projectIDs.isEmpty)
  }

  func testApplePromptPreservesRequestAndBoundsHistory() throws {
    let context = AssistantContext(json: "{}", summary: "", projectIDs: [])
    let old = AssistantTurn(role: "user", text: "OLD PRIVATE DATA")
    let latest = AssistantTurn(role: "assistant", text: String(repeating: "a", count: 6000))
    let input = try AppleAssistantClient.input(prompt: "Current exact request", context: context,
      history: [old, latest, AssistantTurn(role: "user", text: "Last message")])
    XCTAssertFalse(input.contains("OLD PRIVATE DATA"))
    XCTAssertTrue(input.hasSuffix("Current exact request"))
    XCTAssertLessThan(input.count, 1100)
    XCTAssertThrowsError(try AppleAssistantClient.input(prompt: String(repeating: "a", count: 2001), context: context, history: []))
  }

  func testDraftSupportingTextMustComeFromSuppliedText() throws {
    let context = AssistantContext(json: #"{"note":{"markdown":"Bring the résumé."}}"#, summary: "", projectIDs: [])
    let invented = AssistantAction(kind: .event, title: "Study", notes: "Study for exam.", location: "Library")
    let copied = AssistantAction(kind: .task, title: "Prepare", notes: "Bring the résumé.")
    let result = try AppleAssistantClient.groundSupportingText([invented, copied],
      prompt: "Create a study block in the Library.", context: context,
      history: [AssistantTurn(role: "assistant", text: "Study for exam.")])
    XCTAssertEqual(result[0].notes, "")
    XCTAssertEqual(result[0].location, "Library")
    XCTAssertEqual(result[1].notes, "Bring the résumé.")
    XCTAssertEqual(result[0].id, invented.id)
    let unknown = try AppleAssistantClient.groundSupportingText([invented], prompt: "Study",
      context: context, history: [])
    XCTAssertEqual(unknown[0].location, "")
  }

  func testDayBriefKeepsDeadlinesSeparateFromScheduledWorkAndLabelsOmissions() throws {
    let context = AssistantContext(json: #"{"scope":"schedule","selectedDate":"2026-10-25T00:00:00+02:00","timeZone":"Europe/Zurich","events":[{"title":"Study","start":"2026-10-25T10:00:00+01:00","end":"2026-10-25T11:00:00+01:00"},{"title":"Next day","start":"2026-10-26T10:00:00+01:00","end":"2026-10-26T11:00:00+01:00"}],"tasks":[{"title":"Scheduled only","deadline":"","scheduledStart":"2026-10-25T15:00:00+01:00","minutes":30},{"title":"Deadline only","deadline":"2026-10-25T17:00:00+01:00","scheduledStart":"","minutes":25}],"omitted":{"tasks":3}}"#, summary: "", projectIDs: [])
    let brief = try XCTUnwrap(AppleAssistantContext.scheduleBrief(context))
    XCTAssertTrue(brief.contains("Scheduled only — no deadline; scheduled"))
    XCTAssertTrue(brief.contains("Deadline only — due"))
    XCTAssertTrue(brief.contains("unscheduled · 25 min"))
    XCTAssertTrue(brief.contains("Study —"))
    XCTAssertFalse(brief.contains("Next day"))
    XCTAssertTrue(brief.contains("context is limited"))
    XCTAssertNil(try AppleAssistantContext.scheduleBrief(AssistantContext(json: #"{"scope":"message"}"#, summary: "", projectIDs: [])))
  }

  #if canImport(FoundationModels)
  func testGuidedOutputUsesSharedDateAndProjectValidation() throws {
    guard #available(macOS 26, *) else { throw XCTSkip("Requires Foundation Models") }
    let draft = AppleEventDraft(title: "Study",
      start: "2026-10-25T10:00:00+01:00", end: "2026-10-25T11:00:00+01:00",
      eventKind: .deepWork, projectID: nil, notes: nil, location: nil)
    let action = try draft.action()
    try action.validate(projectIDs: [])
    XCTAssertEqual(action.interval?.duration, 3600)
    XCTAssertEqual(action.eventKind, .deepWork)
    var invalid = draft
    for value in ["", "null", "None"] {
      invalid.projectID = value
      invalid.notes = value
      invalid.location = value
      XCTAssertNil(try invalid.action().projectID)
      XCTAssertEqual(try invalid.action().notes, "")
      XCTAssertEqual(try invalid.action().location, "")
    }
    invalid.projectID = "invented-space"
    XCTAssertThrowsError(try invalid.action())
    invalid.projectID = UUID().uuidString
    XCTAssertThrowsError(try invalid.action().validate(projectIDs: []))
    invalid = draft; invalid.end = invalid.start
    XCTAssertThrowsError(try invalid.action().validate(projectIDs: []))
    invalid = draft; invalid.start = "2026-10-25T10:00:00"
    XCTAssertThrowsError(try invalid.action())
    let task = try AppleTaskDraft(title: "Read", dueDate: nil, start: nil,
      estimateMinutes: 25, priority: .high, projectID: nil, notes: nil).action()
    try task.validate(projectIDs: [])
    XCTAssertNil(task.start)
    XCTAssertNil(task.dueDate)
    XCTAssertEqual(task.estimateMinutes, 25)
    XCTAssertEqual(task.priority, .high)
    let unestimated = try AppleTaskDraft(title: "Someday", dueDate: "null", start: "None",
      estimateMinutes: nil, priority: .normal, projectID: nil, notes: nil).action()
    try unestimated.validate(projectIDs: [])
    XCTAssertNil(unestimated.estimateMinutes)
    XCTAssertNil(unestimated.dueDate)
    XCTAssertNil(unestimated.start)
  }

  func testFoundationErrorsHaveRecoveryGuidance() throws {
    guard #available(macOS 26, *) else { throw XCTSkip("Requires Foundation Models") }
    let context = LanguageModelSession.GenerationError.Context(debugDescription: "test")
    XCTAssertTrue(AppleAssistantClient.failure(for: LanguageModelSession.GenerationError.exceededContextWindowSize(context)).message.contains("shorter"))
    XCTAssertTrue(AppleAssistantClient.failure(for: LanguageModelSession.GenerationError.unsupportedLanguageOrLocale(context)).message.contains("language"))
    XCTAssertTrue(AppleAssistantClient.failure(for: LanguageModelSession.GenerationError.assetsUnavailable(context)).message.contains("System Settings"))
  }
  #endif

  /// Explicitly enabled local inference, isolated workspace only. No Apple Calendar/Reminders access.
  func testLiveFoundationModelWhenRequested() async throws {
    guard ProcessInfo.processInfo.environment["STRUKTUR_TEST_APPLE_MODEL"] == "1" else {
      throw XCTSkip("Set STRUKTUR_TEST_APPLE_MODEL=1 to exercise actual on-device inference.")
    }
    guard AppleAssistantAvailability.current().isAvailable else { throw XCTSkip(AppleAssistantAvailability.current().title) }
    let client = AppleAssistantClient()
    let note = store.createNote(title: "Design systems", markdown: "A design system is a shared set of reusable components and rules. Consistent typography and spacing help teams build coherent interfaces. Our next step is to audit the button components.")
    store.revealNote(note)
    let summary = try await client.respond(prompt: "Summarize this note in two sentences. Do not create anything.",
      context: store.assistantContext(scope: .note, anchor: Date(), provider: .apple), history: [], model: "", apiKey: "")
    print("LIVE APPLE SUMMARY: \(summary.message)")
    XCTAssertFalse(summary.message.isEmpty)
    XCTAssertTrue(summary.actions.isEmpty)
    let session = AssistantSession()
    session.scope = .message
    session.draft = "Create one task titled Read chapter. It has no deadline and is not scheduled. Estimate 25 minutes."
    session.send(store: store, anchor: Date())
    await session.waitForResponse()
    print("LIVE APPLE TASK REPLY: \(session.turns.last?.text ?? "none"); error: \(session.error ?? "none")")
    XCTAssertNil(session.error)
    XCTAssertEqual(session.proposals.count, 1)
    let task = try XCTUnwrap(session.proposals.first)
    XCTAssertEqual(task.kind, .task)
    XCTAssertEqual(task.title, "Read chapter")
    XCTAssertNil(task.dueDate)
    XCTAssertNil(task.start)
    XCTAssertEqual(task.estimateMinutes, 25)
    print("LIVE APPLE TASK: \(task.title)")
    session.apply(store: store)
    XCTAssertEqual(store.tasks.count, 1)
    session.undo(store: store)
    XCTAssertTrue(store.tasks.isEmpty)
    let noEstimate = try await client.respond(
      prompt: "Create one task titled Write code for ARGUS. It has no deadline, is unscheduled, and I did not give a duration estimate.",
      context: store.assistantContext(scope: .message, anchor: Date(), provider: .apple),
      history: [], model: "", apiKey: "")
    XCTAssertEqual(noEstimate.actions.count, 1)
    XCTAssertNil(noEstimate.actions.first?.estimateMinutes)
    XCTAssertNil(noEstimate.actions.first?.start)
    print("LIVE APPLE TASK WITHOUT ESTIMATE: \(noEstimate.actions.first?.title ?? "none")")
    let event = try await client.respond(prompt: "Create a calendar block titled Study on October 25, 2026 from 10:00 to 11:00 in Europe/Zurich (UTC+01:00).",
      context: AssistantContext(json: #"{"now":"2026-10-24T12:00:00+02:00","timeZone":"Europe/Zurich"}"#, summary: "", projectIDs: []),
      history: [], model: "", apiKey: "")
    let block = try XCTUnwrap(event.actions.first)
    XCTAssertEqual(event.actions.count, 1)
    XCTAssertEqual(block.kind, .event)
    XCTAssertEqual(block.start, try AssistantWireReply.date("2026-10-25T09:00:00Z"))
    XCTAssertEqual(block.end, try AssistantWireReply.date("2026-10-25T10:00:00Z"))
    XCTAssertFalse(block.notes.localizedCaseInsensitiveContains("exam"), "Do not invent an exam from the title Study.")
    XCTAssertEqual(block.location, "")
    print("LIVE APPLE EVENT: \(block.title), \(String(describing: block.start)) → \(String(describing: block.end))")
    let receipt = try store.applyAssistantActions([block], generation: store.workspaceGeneration)
    XCTAssertEqual(store.entries.count, 1)
    XCTAssertEqual(WorkspaceStore(fileURL: directory.appending(path: "workspace.json")).entries.first?.start, block.start)
    try store.undoAssistantActions(receipt)
    XCTAssertTrue(store.entries.isEmpty)
    store.replaceWorkspace(WorkspaceStore.sampleWorkspace())
    let brief = try await client.respond(prompt: "Summarize my selected day, deadlines, and open tasks. What deserves my attention?",
      context: store.assistantContext(scope: .schedule, anchor: Date(), provider: .apple), history: [], model: "", apiKey: "")
    print("LIVE APPLE DAY BRIEF: \(brief.message)")
    XCTAssertFalse(brief.message.isEmpty)
    XCTAssertTrue(brief.actions.isEmpty)
    XCTAssertTrue(brief.message.contains("Dates and task state come directly from your workspace."))
  }
}

private struct ForbiddenCredentials: AssistantCredentialStore {
  func read() throws -> String? { throw AssistantFailure("TEST: Credentials must not be read for Apple.") }
  func save(_ key: String) throws { throw AssistantFailure("Unexpected key write") }
  func remove() throws { throw AssistantFailure("Unexpected key delete") }
}
private struct TestCredentials: AssistantCredentialStore {
  func read() throws -> String? { "test-key" }
  func save(_ key: String) throws {}
  func remove() throws {}
}
private actor RecordingAssistantClient: AssistantServing {
  var calls = 0
  var histories: [[String]] = []
  var fails: Bool
  var delay: Duration
  init(fails: Bool = false, delay: Duration = .zero) { self.fails = fails; self.delay = delay }
  func respond(prompt: String, context: AssistantContext, history: [AssistantTurn], model: String, apiKey: String) async throws -> AssistantReply {
    calls += 1
    histories.append(history.map(\.text))
    try? await Task.sleep(for: delay)
    if fails { throw AssistantFailure("On-device generation failed") }
    return AssistantReply(message: "Review this draft.", actions: [AssistantAction(kind: .task, title: "Local draft")])
  }
}
