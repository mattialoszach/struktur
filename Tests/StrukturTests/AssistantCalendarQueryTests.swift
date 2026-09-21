import XCTest
@testable import Struktur

@MainActor
final class AssistantCalendarQueryTests: XCTestCase {
  private var directory: URL!
  private var store: WorkspaceStore!
  private let context = AssistantContext(json: #"{"now":"2026-09-21T12:00:00+02:00","selectedDate":"2026-09-01T00:00:00+02:00","timeZone":"Europe/Zurich"}"#, summary: "", projectIDs: [])
  override func setUp() async throws {
    directory = FileManager.default.temporaryDirectory.appending(path: "struktur-calendar-query-\(UUID())")
    store = WorkspaceStore(fileURL: directory.appending(path: "workspace.json"))
    store.replaceWorkspace(Workspace())
  }
  override func tearDown() async throws {
    store = nil
    try? FileManager.default.removeItem(at: directory)
  }
  private func date(_ value: String) throws -> Date { try XCTUnwrap(AssistantWireReply.date(value)) }
  private func query(_ text: String, history: [AssistantTurn] = []) throws -> AssistantCalendarQuery {
    try XCTUnwrap(AssistantCalendarQuery.resolve(prompt: text, history: history, context: context))
  }

  func testExactScreenshotRequestsResolveTuesdayRatherThanSelectedDay() throws {
    for text in ["What meetings do I have tomorrow?", "What meetings on Tue 22.", "What meetings on Tuesday 22 September?", "Show my meetings on September 22, 2026."] {
      let plan = try query(text)
      XCTAssertNil(plan.clarification, text)
      XCTAssertEqual(plan.kind, .meeting)
      XCTAssertEqual(plan.window?.start, try date("2026-09-22T00:00:00+02:00"), text)
      XCTAssertEqual(plan.window?.end, try date("2026-09-23T00:00:00+02:00"), text)
      XCTAssertEqual(plan.request?.calendarOnly, true)
    }
  }

  func testRelativeDatesUseCurrentDayAndRespectDaylightSaving() throws {
    let dst = AssistantContext(json: #"{"now":"2026-10-24T23:30:00+02:00","selectedDate":"2026-01-01T00:00:00+01:00","timeZone":"Europe/Zurich"}"#, summary: "", projectIDs: [])
    let plan = try XCTUnwrap(AssistantCalendarQuery.resolve(prompt: "What meetings do I have tomorrow?", history: [], context: dst))
    XCTAssertEqual(plan.window?.start, try date("2026-10-25T00:00:00+02:00"))
    XCTAssertEqual(plan.window?.end, try date("2026-10-26T00:00:00+01:00"))
    XCTAssertEqual(plan.window?.duration, 25 * 3600)
    XCTAssertEqual(try query("Show my calendar next week").window?.start, try date("2026-09-28T00:00:00+02:00"))
    XCTAssertEqual(try query("Show my calendar next week").window?.duration, 7 * 86400)
    XCTAssertEqual(try query("Show my calendar on the selected day").window?.start, try date("2026-09-01T00:00:00+02:00"))
  }

  func testNamedWeekdayTakesPrecedenceOverWholeWeek() throws {
    for prompt in ["Show meetings Thursday this week", "What meetings this week Thursday?", "Show meetings this Thursday"] {
      XCTAssertEqual(try query(prompt).window?.start, try date("2026-09-24T00:00:00+02:00"), prompt)
      XCTAssertEqual(try query(prompt).window?.duration, 86400, prompt)
    }
    XCTAssertEqual(try query("Show meetings Thursday next week").window?.start, try date("2026-10-01T00:00:00+02:00"))
  }

  func testScreenshotLunchUsesThursdayAndPreservesRequestedClockTimes() throws {
    let prompt = "I've lunch with my Coworker Matteo on Thursday this week from 12:30 to 13 take to calendar"
    let constraint = try XCTUnwrap(AssistantEventDate.resolve(prompt: prompt, context: context))
    XCTAssertTrue(constraint.guidance.contains("2026-09-24 Thursday"))
    let wrong = AssistantAction(kind: .event, title: "Lunch with Matteo", start: try date("2026-09-21T12:30:00+02:00"), end: try date("2026-09-21T13:00:00+02:00"))
    let fixed = try XCTUnwrap(constraint.ground([wrong]).first)
    XCTAssertEqual(fixed.id, wrong.id)
    XCTAssertEqual(fixed.start, try date("2026-09-24T12:30:00+02:00"))
    XCTAssertEqual(fixed.end, try date("2026-09-24T13:00:00+02:00"))
    XCTAssertEqual(try constraint.ground([fixed]), [fixed])
    XCTAssertEqual(try AssistantEventDate.resolve(prompt: "Lunch this week Thursday from 12:30 to 13", context: context)?.day, constraint.day)
    for prompt in ["Lunch Thursday this week or Friday", "Lunch Thursday this week on 2026-09-25", "Lunch every Thursday this week", "Lunch tomorrow"] {
      XCTAssertNil(try AssistantEventDate.resolve(prompt: prompt, context: context), prompt)
    }
  }

  func testEventDateGroundingPreservesOvernightAndAvoidsOtherActions() throws {
    let constraint = try XCTUnwrap(AssistantEventDate.resolve(prompt: "Study Thursday this week from 23:30 to 00:30", context: context))
    let event = AssistantAction(kind: .event, title: "Study", start: try date("2026-09-21T23:30:00+02:00"), end: try date("2026-09-22T00:30:00+02:00"))
    let grounded = try XCTUnwrap(constraint.ground([event]).first)
    XCTAssertEqual(grounded.start, try date("2026-09-24T23:30:00+02:00"))
    XCTAssertEqual(grounded.end, try date("2026-09-25T00:30:00+02:00"))
    let task = AssistantAction(kind: .task, title: "Read", dueDate: try date("2026-09-21T23:30:00+02:00"))
    XCTAssertEqual(try constraint.ground([task]), [task])
    XCTAssertEqual(try constraint.ground([event, event]), [event, event])
  }

  func testEventDateRejectsMissingAndRepeatedDaylightSavingTimes() throws {
    for (now, source) in [("2026-03-23T12:00:00+01:00", "2026-03-23T02:30:00+01:00"),
      ("2026-10-19T12:00:00+02:00", "2026-10-19T02:30:00+02:00")] {
      let input = AssistantContext(json: "{\"now\":\"\(now)\",\"selectedDate\":\"\(now)\",\"timeZone\":\"Europe/Zurich\"}", summary: "", projectIDs: [])
      let constraint = try XCTUnwrap(AssistantEventDate.resolve(prompt: "Meeting Sunday this week from 02:30 to 03:30", context: input))
      let start = try date(source)
      let event = AssistantAction(kind: .event, title: "Meeting", start: start, end: start.addingTimeInterval(3600))
      XCTAssertThrowsError(try constraint.ground([event]))
    }
  }

  func testAmbiguousAndContradictoryDatesNeverDefaultToSelectedDay() throws {
    for text in ["What meetings on Tue 23?", "What meetings on 22/09?", "What meetings on 2026-02-30?",
      "List all my meetings", "What meetings tomorrow and Friday?", "What meetings tomorrow, Friday?", "What meetings next month?"] {
      let plan = try query(text)
      XCTAssertNotNil(plan.clarification, text)
      XCTAssertNil(plan.request, text)
      XCTAssertTrue(try plan.reply(context: context).actions.isEmpty)
    }
  }

  func testFollowUpsUseUserCalendarIntentAndPreserveMeetingFilter() throws {
    let previous = [AssistantTurn(role: "user", text: "What meetings do I have tomorrow?"),
      AssistantTurn(role: "assistant", text: "An incorrect date in old history must not override the user.")]
    for text in ["And on Wednesday?", "What about Wednesday?", "Wednesday?"] {
      let plan = try query(text, history: previous)
      XCTAssertEqual(plan.kind, .meeting)
      XCTAssertEqual(plan.window?.start, try date("2026-09-23T00:00:00+02:00"))
    }
    let chain = previous + [AssistantTurn(role: "user", text: "And on Wednesday?")]
    XCTAssertEqual(try query("And on Thursday?", history: chain).window?.start, try date("2026-09-24T00:00:00+02:00"))
    let thursday = AssistantContext(json: #"{"now":"2026-09-24T12:00:00+02:00","selectedDate":"2026-09-01T00:00:00+02:00","timeZone":"Europe/Zurich"}"#, summary: "", projectIDs: [])
    XCTAssertEqual(try AssistantCalendarQuery.resolve(prompt: "What meetings this Tuesday?", history: [], context: thursday)?.window?.start,
      try date("2026-09-22T00:00:00+02:00"))
    XCTAssertNil(try AssistantCalendarQuery.resolve(prompt: "And on Wednesday?", history: [.init(role: "user", text: "Create a meeting")], context: context))
    XCTAssertNil(try AssistantCalendarQuery.resolve(prompt: "And on Wednesday should I travel?", history: previous, context: context))
  }

  func testActionsAndComplexQuestionsRemainWithTheAssistant() throws {
    for text in ["Create a meeting tomorrow", "What are meetings?", "Show meetings with Alex tomorrow", "What meetings after 3pm tomorrow?",
      "What meetings tomorrow morning?", "Show meetings about design tomorrow", "What is my next meeting?", "Summarize my selected day, deadlines, and open tasks."] {
      XCTAssertNil(try AssistantCalendarQuery.resolve(prompt: text, history: [], context: context), text)
    }
  }

  func testMeetingFilterRunsBeforeRecordLimitAndOmitsUnrelatedTasks() throws {
    let start = try date("2026-09-22T09:00:00+02:00")
    var workspace = Workspace()
    workspace.calendarEntries = (0..<15).map { i in
      CalendarEntry(title: "Not a meeting \(i)", start: start, end: start.addingTimeInterval(1800), kind: .personal)
    }
    workspace.calendarEntries.append(CalendarEntry(title: "Planning review", start: start.addingTimeInterval(7200), end: start.addingTimeInterval(10800), kind: .meeting))
    workspace.tasks = [TaskItem(title: "UNRELATED TASK", plannedStart: start, estimateMinutes: 30)]
    store.replaceWorkspace(workspace)
    let plan = try query("What meetings do I have tomorrow?")
    let snapshot = try store.assistantContext(request: XCTUnwrap(plan.request), anchor: date("2026-09-01T00:00:00+02:00"), provider: .apple)
    let reply = try plan.reply(context: snapshot)
    XCTAssertTrue(reply.message.contains("Planning review"))
    XCTAssertTrue(reply.message.contains("11:00"))
    XCTAssertTrue(reply.message.contains("12:00"))
    XCTAssertFalse(reply.message.contains("Not a meeting"))
    XCTAssertFalse(snapshot.json.contains("UNRELATED TASK"))
    XCTAssertFalse(reply.message.contains("No meetings"))
    XCTAssertFalse(reply.message.contains("omitted"))
  }

  func testEmptyAnswersRequireVerifiedWindowAndDiscloseOmittedRecords() throws {
    let plan = try query("What meetings do I have tomorrow?")
    XCTAssertThrowsError(try plan.reply(context: context), "Unread context must never mean empty calendar")
    let request = try XCTUnwrap(plan.request)
    let snapshot = try store.assistantContext(request: request, anchor: Date(), provider: .apple)
    XCTAssertTrue(try plan.reply(context: snapshot).message.contains("No meetings in Struktur"))
    let otherDay = try store.assistantContext(request: .init(schedule: true), anchor: try date("2026-09-21T00:00:00+02:00"), provider: .apple)
    XCTAssertThrowsError(try plan.reply(context: otherDay))
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(snapshot.json.utf8)) as? [String: Any])
    json["omitted"] = ["events": 2]
    let limited = AssistantContext(json: String(decoding: try JSONSerialization.data(withJSONObject: json), as: UTF8.self), summary: "", projectIDs: [])
    let message = try plan.reply(context: limited).message
    XCTAssertFalse(message.contains("No meetings in Struktur"))
    XCTAssertTrue(message.contains("2 more meetings were omitted"))
  }

  func testSessionAnswersFromWorkspaceWithoutCallingEitherModel() async throws {
    let start = try date("2026-09-22T11:00:00+02:00")
    store.add(CalendarEntry(title: "Planning review", start: start, end: start.addingTimeInterval(3600), kind: .meeting))
    for provider: AssistantProvider in [.apple, .openAI] {
      store.updatePreferences { $0.assistant = AssistantPreferences(provider: provider) }
      let session = AssistantSession(client: NoCalendarModel(), credentials: CalendarCredentials(), appleClient: NoCalendarModel(), appleAvailability: { .available })
      session.draft = "What meetings on 2026-09-22?"
      session.send(store: store, anchor: try date("2026-09-01T00:00:00+02:00"))
      await session.waitForResponse()
      XCTAssertNil(session.error)
      XCTAssertTrue(session.turns.last?.text.contains("Planning review") == true)
      XCTAssertTrue(session.lastContext?.contains("Planning review") == true)
      XCTAssertTrue(session.proposals.isEmpty)
      XCTAssertEqual(store.entries.count, 1)
      session.draft = "And on 2026-09-23?"
      session.send(store: store, anchor: start)
      await session.waitForResponse()
      XCTAssertNil(session.error)
      XCTAssertTrue(session.turns.last?.text.contains("No meetings in Struktur") == true)
    }
  }
}

private struct NoCalendarModel: AssistantServing {
  func respond(prompt: String, context: AssistantContext, history: [AssistantTurn], model: String, apiKey: String) async throws -> AssistantReply {
    throw AssistantFailure("A direct calendar read must not call a model.")
  }
}
private struct CalendarCredentials: AssistantCredentialStore {
  func read() throws -> String? { "test-only" }
  func save(_ key: String) throws {}
  func remove() throws {}
}
