import XCTest
@testable import Struktur

@MainActor
final class AssistantTaskContextTests: XCTestCase {
  private var directory: URL!
  private var store: WorkspaceStore!
  private var now: Date { try! XCTUnwrap(AssistantWireReply.date("2026-09-21T12:00:00+02:00")) }
  override func setUp() async throws {
    directory = FileManager.default.temporaryDirectory.appending(path: "struktur-task-context-\(UUID())")
    store = WorkspaceStore(fileURL: directory.appending(path: "workspace.json"))
    var workspace = Workspace()
    workspace.tasks = [
      TaskItem(title: "Ten-minute reset", notes: "PRIVATE BODY", dueDate: now.adding(days: -4), estimateMinutes: 10),
      TaskItem(title: "Ten-minute reset", dueDate: now.adding(days: -2), estimateMinutes: 10),
      TaskItem(title: "Finish App", estimateMinutes: 20),
      TaskItem(title: "Already completed", isCompleted: true),
    ]
    store.replaceWorkspace(workspace)
  }
  override func tearDown() async throws {
    store = nil
    try? FileManager.default.removeItem(at: directory)
  }
  private func snapshot(_ query: AssistantContextRequest, provider: AssistantProvider = .apple) throws -> AssistantContext {
    try store.assistantContext(request: query, anchor: now.adding(days: 1), now: now, provider: provider)
  }
  private func json(_ context: AssistantContext) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: Data(context.json.utf8)) as? [String: Any])
  }

  func testScheduleReadIncludesOverdueAndUnscheduledOpenTasksForBothProviders() throws {
    for provider: AssistantProvider in [.apple, .openAI] {
      let context = try snapshot(.init(schedule: true), provider: provider)
      let data = try json(context)
      XCTAssertEqual(data["openTaskCount"] as? Int, 3)
      XCTAssertEqual(data["taskSelection"] as? String, "allOpen")
      XCTAssertEqual((data["tasks"] as? [[String: Any]])?.count, 3)
      XCTAssertFalse(context.json.contains("PRIVATE BODY"))
      XCTAssertFalse(context.json.contains("Already completed"))
      let brief = try XCTUnwrap(AppleAssistantContext.scheduleBrief(context))
      XCTAssertTrue(brief.contains("Finish App — no deadline; unscheduled · 20 min estimate"))
      XCTAssertTrue(brief.contains("overdue"))
      XCTAssertTrue(brief.contains("3 total"))
    }
  }

  func testGenericTaskQueriesAreNotTreatedAsTitles() throws {
    for provider: AssistantProvider in [.apple, .openAI] {
      for query in ["", "tasks", "open tasks", "open todos", "my to-dos", "all unfinished tasks", "deadlines"] {
        let context = try snapshot(.init(tasks: true, query: query), provider: provider)
        let reply = try AssistantTaskContext.reply(context)
        XCTAssertTrue(reply.message.contains("Finish App"), query)
        XCTAssertEqual(reply.message.components(separatedBy: "Ten-minute reset").count - 1, 2)
      }
    }
    let filtered = try snapshot(.init(tasks: true, query: "Finish App"))
    XCTAssertEqual((try json(filtered)["tasks"] as? [[String: Any]])?.count, 1)
    XCTAssertEqual(try json(filtered)["taskSelection"] as? String, "matchingOpen")
    XCTAssertThrowsError(try AssistantTaskContext.reply(filtered))
  }

  func testPlainListsAreRecognizedWithoutInterceptingFiltersOrActions() {
    for prompt in ["what are my open todos", "Show my tasks", "List all my unfinished tasks.", "Do I have any to-dos?", "Which are my pending tasks?"] {
      XCTAssertTrue(AssistantTaskContext.isListing(prompt), prompt)
    }
    for prompt in ["Create tasks", "Show my completed tasks", "List my tasks due tomorrow", "What are my open todos in Thesis?", "Show my tasks and meetings"] {
      XCTAssertFalse(AssistantTaskContext.isListing(prompt), prompt)
    }
    XCTAssertTrue(AssistantTaskContext.needsContext("Summarize my day tomorrow, deadlines, and open tasks. What deserves my attention?"))
    XCTAssertFalse(AssistantTaskContext.needsContext("Create tasks from this note"))
  }

  func testMissingFilteredAndLimitedContextCannotMeanNoOpenTasks() throws {
    let overview = try store.assistantOverview(anchor: now, now: now)
    XCTAssertEqual(try json(overview)["openTaskCount"] as? Int, 3)
    XCTAssertThrowsError(try AssistantTaskContext.reply(overview))
    XCTAssertEqual(try AssistantTaskContext.section(json(overview)), "Open tasks were not retrieved.")
    let filtered = try snapshot(.init(tasks: true, query: "nonexistent title"))
    let filteredMessage = try AssistantTaskContext.section(json(filtered))
    XCTAssertTrue(filteredMessage.contains("No matching tasks"))
    XCTAssertFalse(filteredMessage.contains("No open tasks"))
    var limited = try json(snapshot(.init(tasks: true)))
    limited["tasks"] = [] as [[String: Any]]
    limited["omitted"] = ["tasks": 3]
    let limitedMessage = try AssistantTaskContext.section(limited)
    XCTAssertTrue(limitedMessage.contains("Open tasks exist"))
    XCTAssertTrue(limitedMessage.contains("3 more tasks"))
    XCTAssertFalse(limitedMessage.contains("No open tasks"))
  }

  func testRealEmptyListAndCompletedStateAreReadFresh() throws {
    for task in store.tasks where !task.isCompleted { store.toggleTask(task.id) }
    let context = try snapshot(.init(tasks: true))
    XCTAssertEqual(try json(context)["openTaskCount"] as? Int, 0)
    XCTAssertTrue(try AssistantTaskContext.reply(context).message.contains("No open tasks in Struktur"))
  }

  func testLargeListDisclosesTotalAndOmittedRecordsWithinBudget() throws {
    var workspace = Workspace()
    workspace.tasks = (0..<100).map { TaskItem(title: "Task \($0) " + String(repeating: "📚", count: 150)) }
    store.replaceWorkspace(workspace)
    for provider: AssistantProvider in [.apple, .openAI] {
      let merged = try AssistantTaskContext.merging(snapshot(.init(tasks: true), provider: provider),
        into: store.assistantOverview(anchor: now, now: now), provider: provider)
      XCTAssertLessThanOrEqual(merged.json.utf8.count, provider == .apple ? 5000 : 14000)
      let reply = try AssistantTaskContext.reply(merged)
      XCTAssertTrue(reply.message.contains("100 total"))
      XCTAssertTrue(reply.message.contains("more tasks omitted"))
      XCTAssertFalse(reply.message.contains("No open tasks"))
    }
  }

  func testSessionUsesFreshWorkspaceForBothProvidersWithoutModelGeneration() async throws {
    for provider: AssistantProvider in [.apple, .openAI] {
      store.updatePreferences { $0.assistant = AssistantPreferences(provider: provider) }
      let session = AssistantSession(client: TaskContextModel(), credentials: TaskContextCredentials(),
        appleClient: TaskContextModel(), appleAvailability: { .available })
      session.draft = "what are my open todos"
      session.send(store: store, anchor: now.adding(days: 1))
      await session.waitForResponse()
      XCTAssertNil(session.error)
      XCTAssertTrue(session.turns.last?.text.contains("3 total") == true)
      XCTAssertTrue(session.turns.last?.text.contains("Finish App") == true)
      XCTAssertTrue(session.lastContext?.contains("Finish App") == true)
      XCTAssertTrue(session.proposals.isEmpty)
      XCTAssertEqual(store.tasks.count, 4)
      let id = try XCTUnwrap(store.tasks.first { $0.title == "Finish App" }?.id)
      store.toggleTask(id)
      session.draft = "what are my open todos"
      session.send(store: store, anchor: now)
      await session.waitForResponse()
      XCTAssertNil(session.error)
      XCTAssertTrue(session.turns.last?.text.contains("2 total") == true)
      XCTAssertFalse(session.turns.last?.text.contains("Finish App") == true)
      store.toggleTask(id)
    }
  }

  func testCompoundTaskQuestionGetsRecordsEvenWhenModelSkipsTools() async throws {
    for provider: AssistantProvider in [.apple, .openAI] {
      store.updatePreferences { $0.assistant = AssistantPreferences(provider: provider) }
      let model = TaskContextModel(expectTasks: true)
      let session = AssistantSession(client: model, credentials: TaskContextCredentials(), appleClient: model, appleAvailability: { .available })
      session.draft = "Summarize my day tomorrow, deadlines, and open tasks. What deserves my attention?"
      session.send(store: store, anchor: now)
      await session.waitForResponse()
      XCTAssertNil(session.error)
      XCTAssertEqual(session.turns.last?.text, "Received all three open tasks")
    }
  }
}

private struct TaskContextModel: AssistantServing {
  var expectTasks = false
  func respond(prompt: String, context: AssistantContext, history: [AssistantTurn], model: String, apiKey: String) async throws -> AssistantReply {
    guard expectTasks else { throw AssistantFailure("Plain lists must not call a model.") }
    let snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(context.json.utf8)) as? [String: Any])
    XCTAssertEqual(snapshot["openTaskCount"] as? Int, 3)
    XCTAssertEqual((snapshot["tasks"] as? [[String: Any]])?.count, 3)
    XCTAssertTrue(context.json.contains("Finish App"))
    return AssistantReply(message: "Received all three open tasks", actions: [])
  }
}
private struct TaskContextCredentials: AssistantCredentialStore {
  func read() throws -> String? { "test-only" }
  func save(_ key: String) throws {}
  func remove() throws {}
}
