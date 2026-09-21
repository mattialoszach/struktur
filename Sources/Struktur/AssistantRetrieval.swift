import Foundation

/// Read-only retrieval selected by the model, with limits enforced by the app.
struct AssistantContextRequest: Codable, Equatable, Sendable {
  var schedule = false
  var tasks = false
  var note = false
  var spaces = false
  var query = ""
  var noteQuery: String?
  var startDate: String?
  var endDate: String?
  var calendarOnly: Bool?
  var eventKind: ItemKind?
}

typealias AssistantRetrieve = @MainActor @Sendable (AssistantContextRequest) throws -> AssistantContext

@MainActor
extension WorkspaceStore {
  func assistantOverview(anchor: Date, now: Date = Date()) throws -> AssistantContext {
    var context = try assistantContext(scope: .message, anchor: anchor, now: now)
    var json = try JSONSerialization.jsonObject(with: Data(context.json.utf8)) as! [String: Any]
    json["available"] = ["schedule": true, "tasks": true, "spaces": true,
      "currentNote": note(noteLibrary.selectedNoteID)?.deletedAt == nil && note(noteLibrary.selectedNoteID) != nil]
    json["openTaskCount"] = tasks.filter { !$0.isCompleted }.count
    context.json = String(decoding: try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]), as: UTF8.self)
    return context
  }

  func assistantContext(request: AssistantContextRequest, anchor: Date, now: Date = Date(),
    provider: AssistantProvider) throws -> AssistantContext {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = Calendar.struktur.timeZone
    func stamp(_ date: Date) -> String { formatter.string(from: date) }
    let query = String(request.query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
    func matches(_ text: String) -> Bool { query.isEmpty || text.localizedStandardContains(query) }
    let start = try AssistantWireReply.date(request.startDate) ?? anchor.startOfDay
    let end = try AssistantWireReply.date(request.endDate) ?? start.adding(days: 1)
    guard end > start, end <= start.adding(days: 31),
      start.timeIntervalSince1970 >= 0, end.timeIntervalSince1970 <= 7_258_118_400 else {
      throw AssistantFailure("Request a calendar range of at most 31 days, between 1970 and 2200.")
    }
    var json: [String: Any] = ["now": stamp(now), "selectedDate": stamp(start.startOfDay),
      "timeZone": Calendar.struktur.timeZone.identifier, "scope": "automatic", "query": query]
    var omitted: [String: Int] = [:]
    var parts: [String] = []
    let rowLimit = provider == .apple ? 10 : 30
    // All overlapping blocks are necessary for conflict/free-time questions, even with a task query.
    if request.schedule {
      let entries = calendarEntries(in: DateInterval(start: start, end: end))
        .filter { request.eventKind == nil || $0.kind == request.eventKind }
      json["window"] = ["start": stamp(start), "endExclusive": stamp(end)]
      json["workingHours"] = ["start": preferences.workingDayStart, "end": preferences.workingDayEnd]
      json["events"] = entries.prefix(rowLimit).map { entry -> [String: Any] in
        ["id": entry.id.uuidString, "title": String(entry.title.prefix(200)), "start": stamp(entry.start),
          "end": stamp(entry.end), "allDay": entry.isAllDay, "kind": entry.kind.rawValue,
          "spaceID": entry.projectID?.uuidString ?? ""]
      }
      omitted["events"] = max(0, entries.count - rowLimit)
      parts.append("\(min(entries.count, rowLimit)) blocks")
    }
    if request.tasks || (request.schedule && request.calendarOnly != true) {
      let taskQuery = request.tasks ? AssistantTaskContext.searchTerm(query) : ""
      func taskMatches(_ text: String) -> Bool { taskQuery.isEmpty || text.localizedStandardContains(taskQuery) }
      let matchingSpaces = Set(projects.filter { taskMatches($0.name) }.map(\.id))
      json["openTaskCount"] = tasks.filter { !$0.isCompleted }.count
      json["taskSelection"] = taskQuery.isEmpty ? "allOpen" : "matchingOpen"
      json["taskQuery"] = taskQuery
      let candidates = tasks.filter { task in
        guard !task.isCompleted else { return false }
        if request.schedule, let planned = task.plannedStart,
          planned < end, planned.addingTimeInterval(Double(task.estimateMinutes ?? 30) * 60) > start { return true }
        return taskMatches(task.title) || (!taskQuery.isEmpty && task.projectID.map(matchingSpaces.contains) == true)
      }.sorted { a, b in
        func rank(_ task: TaskItem) -> Int {
          if let planned = task.plannedStart, planned < end,
            planned.addingTimeInterval(Double(task.estimateMinutes ?? 30) * 60) > start { return 0 }
          if let due = task.dueDate, due < end { return 1 }
          return task.priority == .high ? 2 : 3
        }
        if rank(a) != rank(b) { return rank(a) < rank(b) }
        let x = a.dueDate ?? a.plannedStart ?? .distantFuture
        let y = b.dueDate ?? b.plannedStart ?? .distantFuture
        return x == y ? a.id.uuidString < b.id.uuidString : x < y
      }
      json["tasks"] = candidates.prefix(rowLimit).map { task -> [String: Any] in
        ["id": task.id.uuidString, "title": String(task.title.prefix(200)),
          "deadline": task.dueDate.map(stamp) ?? "", "scheduledStart": task.plannedStart.map(stamp) ?? "",
          "minutes": task.estimateMinutes.map { $0 as Any } ?? NSNull(), "priority": task.priority.rawValue,
          "spaceID": task.projectID?.uuidString ?? "", "linkedEventID": task.linkedEventID?.uuidString ?? ""]
      }
      omitted["tasks"] = max(0, candidates.count - rowLimit)
      parts.append("\(min(candidates.count, rowLimit)) tasks")
    }
    if request.spaces {
      let candidates = projects.filter { matches($0.name) }
      json["spaces"] = candidates.prefix(provider == .apple ? 8 : 20).map {
        ["id": $0.id.uuidString, "name": String($0.name.prefix(200))]
      }
      omitted["spaces"] = max(0, candidates.count - (provider == .apple ? 8 : 20))
      parts.append("space names")
    }
    if request.note {
      let noteQuery = String((request.noteQuery ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
      func noteMatches(_ value: String) -> Bool { value.localizedStandardContains(noteQuery) }
      let candidates = notes.filter { $0.deletedAt == nil && (noteQuery.isEmpty
        ? $0.id == noteLibrary.selectedNoteID : noteMatches($0.title) || noteMatches($0.markdown)) }
        .sorted { a, b in
          if noteMatches(a.title) != noteMatches(b.title) { return noteMatches(a.title) }
          return a.id.uuidString < b.id.uuidString
        }
      if let note = candidates.first {
        let limit = provider == .apple ? 3_200 : 6_000
        var text = note.markdown
        // Search excerpts include the matching passage, even in long notes.
        if !noteQuery.isEmpty, let range = text.range(of: noteQuery, options: [.caseInsensitive, .diacriticInsensitive]),
          text.distance(from: text.startIndex, to: range.lowerBound) > limit / 2 {
          let begin = text.index(range.lowerBound, offsetBy: -200, limitedBy: text.startIndex) ?? text.startIndex
          text = String(text[begin...])
        }
        let excerpt = String(text.prefix(limit))
        json["note"] = ["id": note.id.uuidString, "title": String(note.title.prefix(200)),
          "markdown": excerpt, "truncated": excerpt != note.markdown]
        parts.append("note text")
      } else { json["noteStatus"] = "No matching note. Ask which note the user means." }
      omitted["notes"] = max(0, candidates.count - 1)
    }
    json["omitted"] = omitted
    return try Self.boundAssistantContext(json, maximumBytes: provider == .apple ? 5_000 : 14_000,
      summary: parts.isEmpty ? "Date and timezone" : parts.joined(separator: " · "))
  }

  static func boundAssistantContext(_ original: [String: Any], maximumBytes: Int,
    summary: String) throws -> AssistantContext {
    var json = original
    var omitted = json["omitted"] as? [String: Int] ?? [:]
    func encode() throws -> Data { try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .withoutEscapingSlashes]) }
    while try encode().count > maximumBytes {
      if var note = json["note"] as? [String: Any], let text = note["markdown"] as? String, !text.isEmpty {
        note["markdown"] = String(text.prefix(max(0, text.count - 200)))
        note["truncated"] = true
        json["note"] = note
      } else if let key = ["tasks", "events", "spaces"].max(by: {
        (json[$0] as? [[String: Any]] ?? []).count < (json[$1] as? [[String: Any]] ?? []).count
      }), var rows = json[key] as? [[String: Any]], !rows.isEmpty {
        rows.removeLast(); json[key] = rows
        omitted[key, default: 0] += 1; json["omitted"] = omitted
      } else { throw AssistantFailure("The requested context is too large. Try a more specific request.") }
    }
    let spaces = json["spaces"] as? [[String: Any]] ?? []
    let limited = omitted.values.contains { $0 > 0 } || (json["note"] as? [String: Any])?["truncated"] as? Bool == true
    return AssistantContext(json: String(decoding: try encode(), as: UTF8.self),
      summary: summary + (limited ? " · limited context" : ""),
      projectIDs: Set(spaces.compactMap { ($0["id"] as? String).flatMap(UUID.init(uuidString:)) }))
  }
}
