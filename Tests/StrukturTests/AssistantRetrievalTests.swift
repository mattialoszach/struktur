import AppKit
import XCTest
@testable import Struktur

@MainActor
final class AssistantRetrievalTests: XCTestCase {
  private var directory: URL!
  private var store: WorkspaceStore!
  override func setUp() async throws {
    directory = FileManager.default.temporaryDirectory.appending(path: "struktur-retrieval-\(UUID())")
    store = WorkspaceStore(fileURL: directory.appending(path: "workspace.json"))
    store.replaceWorkspace(Workspace())
  }
  override func tearDown() async throws {
    store = nil
    try? FileManager.default.removeItem(at: directory)
  }

  func testOverviewContainsNoWorkspaceBodiesOrTitles() throws {
    store.add(TaskItem(title: "PRIVATE TASK", notes: "SECRET BODY"))
    store.createNote(title: "PRIVATE NOTE", markdown: "SECRET NOTE")
    let context = try store.assistantOverview(anchor: Date())
    XCTAssertFalse(context.json.contains("PRIVATE"))
    XCTAssertFalse(context.json.contains("SECRET"))
    XCTAssertTrue(context.json.contains("currentNote"))
    XCTAssertTrue(context.projectIDs.isEmpty)
  }

  func testTargetedTaskQueryPreservesAllScheduleConflicts() throws {
    let date = Date().startOfDay.setting(hour: 10)
    store.add(TaskItem(title: "Write thesis", notes: "PRIVATE TASK"))
    store.add(TaskItem(title: "Unrelated scheduled work", plannedStart: date, estimateMinutes: 30))
    store.add(TaskItem(title: "Unrelated unscheduled task"))
    store.add(CalendarEntry(title: "Dentist", notes: "PRIVATE EVENT", start: date, end: date.addingTimeInterval(3600)))
    store.createNote(title: "Thesis", markdown: "PRIVATE NOTE")
    let context = try store.assistantContext(request: .init(schedule: true, tasks: true, query: "thesis"),
      anchor: date, provider: .openAI)
    XCTAssertTrue(context.json.contains("Write thesis"))
    XCTAssertTrue(context.json.contains("Unrelated scheduled work"))
    XCTAssertTrue(context.json.contains("Dentist"))
    XCTAssertFalse(context.json.contains("Unrelated unscheduled task"))
    XCTAssertFalse(context.json.contains("PRIVATE"))
  }

  func testNoteLookupUsesMatchingExcerptAndExcludesDeletedNotes() throws {
    store.createNote(title: "Other", markdown: "UNRELATED PRIVATE TEXT")
    let id = store.createNote(title: "Research", markdown: String(repeating: "preface ", count: 1500) + "needle matching paragraph")
    let context = try store.assistantContext(request: .init(note: true, noteQuery: "needle"), anchor: Date(), provider: .apple)
    XCTAssertTrue(context.json.contains("needle matching paragraph"))
    XCTAssertFalse(context.json.contains("UNRELATED"))
    XCTAssertTrue(context.summary.contains("limited"))
    let mixed = try store.assistantContext(request: .init(tasks: true, note: true, query: "other task"), anchor: Date(), provider: .apple)
    XCTAssertTrue(mixed.json.contains("Research"), "A task search must not change which current note is read")
    store.editNote(id) { $0.deletedAt = Date() }
    let deleted = try store.assistantContext(request: .init(note: true, noteQuery: "needle"), anchor: Date(), provider: .apple)
    XCTAssertFalse(deleted.json.contains("matching paragraph"))
    XCTAssertTrue(deleted.json.contains("No matching note"))
  }

  func testMixedUnicodeContextIsBoundedWithValidIDsAndOmissionCounts() throws {
    var workspace = Workspace()
    workspace.tasks = (0..<100).map { TaskItem(title: "Task \($0) " + String(repeating: "📚", count: 200)) }
    workspace.projects = (0..<25).map { Project(name: "Space \($0) " + String(repeating: "🪴", count: 200), color: .mint) }
    workspace.notes = [NoteDocument(title: "Note", markdown: String(repeating: "👩🏽‍💻", count: 4000))]
    workspace.noteLibrary = NoteLibraryPreferences()
    workspace.noteLibrary?.selectedNoteID = workspace.notes?.first?.id
    store.replaceWorkspace(workspace)
    for provider: AssistantProvider in [.apple, .openAI] {
      let context = try store.assistantContext(request: .init(tasks: true, note: true, spaces: true), anchor: Date(), provider: provider)
      XCTAssertLessThanOrEqual(context.json.utf8.count, provider == .apple ? 5_000 : 14_000)
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(context.json.utf8)) as? [String: Any])
      let rows = json["spaces"] as? [[String: String]] ?? []
      XCTAssertEqual(context.projectIDs, Set(rows.compactMap { $0["id"].flatMap(UUID.init(uuidString:)) }))
      let tasks = json["tasks"] as? [[String: Any]] ?? []
      XCTAssertEqual((json["omitted"] as? [String: Int])?["tasks"], 100 - tasks.count)
      XCTAssertTrue(context.summary.contains("limited"))
    }
  }

  func testRequestedDatesOverrideSelectedDayAndInvalidRangesFail() throws {
    let selected = try XCTUnwrap(AssistantWireReply.date("2026-10-01T00:00:00+02:00"))
    let future = try XCTUnwrap(AssistantWireReply.date("2026-11-03T12:00:00+01:00"))
    store.add(CalendarEntry(title: "Future appointment", start: future, end: future.addingTimeInterval(3600)))
    let query = AssistantContextRequest(schedule: true, startDate: "2026-11-02T00:00:00+01:00", endDate: "2026-11-04T00:00:00+01:00")
    let context = try store.assistantContext(request: query, anchor: selected, provider: .apple)
    XCTAssertTrue(context.json.contains("Future appointment"))
    XCTAssertTrue(try XCTUnwrap(AppleAssistantContext.scheduleBrief(context)).contains("Future appointment"))
    var invalid = query
    invalid.endDate = "2027-11-04T00:00:00+01:00"
    XCTAssertThrowsError(try store.assistantContext(request: invalid, anchor: selected, provider: .openAI))
    invalid.startDate = "tomorrow"
    XCTAssertThrowsError(try store.assistantContext(request: invalid, anchor: selected, provider: .openAI))
  }

  func testHistoryHasTotalBudgetAndRetainsLatestOutcome() throws {
    let history = (0..<10).map { AssistantTurn(role: "user", text: String(repeating: "a", count: 8000) + "\($0)") }
      + [AssistantTurn(role: "user", text: "APP RESULT: Added Study. Do not recreate it.")]
    let bounded = AssistantTurn.bounded(history)
    XCTAssertLessThanOrEqual(bounded.map(\.text.count).reduce(0, +), 6100)
    XCTAssertTrue(bounded.last!.text.contains("APP RESULT"))
    let request = try OpenAIAssistantClient.request(prompt: "Hello", context: .init(json: "{}", summary: "", projectIDs: []),
      history: history, model: "gpt-4.1-mini", apiKey: "test", retrieval: true)
    let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
    XCTAssertEqual(body["max_output_tokens"] as? Int, 3000)
    XCTAssertEqual(body["parallel_tool_calls"] as? Bool, false)
    XCTAssertEqual(body["store"] as? Bool, false)
  }

  func testCloudLookupLoopCachesDuplicatesAndDisablesToolsAtLimit() async throws {
    let transport = makeTransport()
    defer { transport.invalidateAndCancel() }
    var reads = 0
    let reply = try await OpenAIAssistantClient(session: transport).respond(prompt: "loop-test",
      context: .init(json: "{}", summary: "", projectIDs: []), history: [], model: "test", apiKey: "test") { query in
        reads += 1
        XCTAssertTrue(query.tasks)
        return AssistantContext(json: #"{"tasks":[{"title":"Retrieved"}]}"#, summary: "", projectIDs: [])
      }
    XCTAssertEqual(reads, 1)
    XCTAssertEqual(reply.message, "Used retrieved context; tools stopped.")
  }

  func testCloudGeneralAnswerNeedsNoLookupAndCancellationPropagates() async throws {
    let transport = makeTransport()
    defer { transport.invalidateAndCancel() }
    let client = OpenAIAssistantClient(session: transport)
    let context = AssistantContext(json: "{}", summary: "", projectIDs: [])
    let answer = try await client.respond(prompt: "general-test", context: context, history: [], model: "test", apiKey: "test") { _ in
      XCTFail("A general answer should not read the workspace")
      throw CancellationError()
    }
    XCTAssertEqual(answer.message, "General answer")
    do {
      _ = try await client.respond(prompt: "loop-test", context: context, history: [], model: "test", apiKey: "test") { _ in throw CancellationError() }
      XCTFail("Cancellation must stop the agent")
    } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
  }

  func testCloudRejectsUnknownToolsAndRepeatedCallsBeyondLimit() async throws {
    let transport = makeTransport()
    defer { transport.invalidateAndCancel() }
    for prompt in ["unsupported-test", "exhaust-test"] {
      var reads = 0
      do {
        _ = try await OpenAIAssistantClient(session: transport).respond(prompt: prompt,
          context: .init(json: "{}", summary: "", projectIDs: []), history: [], model: "test", apiKey: "test") { _ in
            reads += 1
            return AssistantContext(json: "{}", summary: "", projectIDs: [])
          }
        XCTFail("Unexpected tool must not succeed")
      } catch is AssistantFailure {} catch { XCTFail("Unexpected error: \(error)") }
      XCTAssertEqual(reads, prompt == "unsupported-test" ? 0 : 1)
    }
  }

  func testCloudCanCorrectMalformedLookupWithoutDiscardingRequest() async throws {
    let transport = makeTransport()
    defer { transport.invalidateAndCancel() }
    var reads = 0
    let reply = try await OpenAIAssistantClient(session: transport).respond(prompt: "malformed-test",
      context: .init(json: "{}", summary: "", projectIDs: []), history: [], model: "test", apiKey: "test") { _ in
        reads += 1
        return AssistantContext(json: #"{"tasks":[{"title":"Retrieved"}]}"#, summary: "", projectIDs: [])
      }
    XCTAssertEqual(reads, 1)
    XCTAssertEqual(reply.message, "Used retrieved context; tools stopped.")
  }

  func testReturnSendsShiftReturnInsertsNewlineAndMarkedTextDoesNotSend() throws {
    let view = AssistantTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
    let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = view
    window.makeFirstResponder(view)
    var sends = 0
    view.send = { sends += 1 }
    func press(_ flags: NSEvent.ModifierFlags = []) throws {
      view.keyDown(with: try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
        timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\r",
        charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)))
    }
    view.string = "First line"
    view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
    try press(.shift)
    XCTAssertEqual(view.string, "First line\n")
    XCTAssertEqual(sends, 0)
    try press()
    XCTAssertEqual(sends, 1)
    view.setMarkedText("仮", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    try press()
    XCTAssertEqual(sends, 1)
    view.unmarkText()
    view.isEditable = false
    try press()
    XCTAssertEqual(sends, 1)
  }

  private func makeTransport() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [RetrievalURLProtocol.self]
    return URLSession(configuration: config)
  }
}

private final class RetrievalURLProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    var data = request.httpBody ?? Data()
    if let stream = request.httpBodyStream {
      stream.open(); defer { stream.close() }
      var buffer = [UInt8](repeating: 0, count: 4096)
      while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        data.append(contentsOf: buffer.prefix(count))
      }
    }
    let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    let input = body["input"] as? [[String: Any]] ?? []
    func mode(_ name: String) -> Bool { input.contains { ($0["content"] as? String)?.contains(name) == true } }
    let general = mode("general-test")
    let outputs = input.filter { $0["type"] as? String == "function_call_output" }
    let output: [[String: Any]]
    if !general && (outputs.count < 2 || mode("exhaust-test")) {
      output = [["type": "function_call", "name": mode("unsupported-test") ? "delete_task" : "read_workspace", "call_id": "lookup-\(outputs.count)",
        "arguments": mode("malformed-test") && outputs.isEmpty ? "invalid JSON" : #"{"schedule":false,"tasks":true,"note":false,"spaces":false,"query":"","noteQuery":null,"startDate":null,"endDate":null}"#]]
    } else {
      let valid = general || (body["tools"] == nil && outputs.contains { ($0["output"] as? String)?.contains("Retrieved") == true }
        && outputs.allSatisfy {
          let text = $0["output"] as? String ?? ""
          return text.contains("Retrieved") || text.contains("alreadyRead") || (mode("malformed-test") && text.contains("Lookup failed"))
        })
      let message = general ? "General answer" : (valid ? "Used retrieved context; tools stopped." : "Invalid loop")
      let reply = String(decoding: try! JSONSerialization.data(withJSONObject: ["message": message, "actions": []]), as: UTF8.self)
      output = [["type": "message", "content": [["type": "output_text", "text": reply]]]]
    }
    let response = try! JSONSerialization.data(withJSONObject: ["status": "completed", "output": output])
    client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: response)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
