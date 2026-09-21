import Foundation

enum AssistantTaskContext {
  /// Only whole-list requests bypass generation. Filters, actions, and compound questions still use it.
  static func isListing(_ prompt: String) -> Bool {
    let text = prompt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    return text.range(of: #"^(?:(?:please )?(?:show|list)(?: me)?|what are|which are|do i have|can you (?:show|list)(?: me)?)(?: all)?(?: of)?(?: my| the| any)?(?: open| unfinished| incomplete| pending)? (?:tasks|todos|to-dos|to dos)(?: please)?$"#,
      options: .regularExpression) != nil
  }

  static func needsContext(_ prompt: String) -> Bool {
    let text = prompt.lowercased()
    return text.range(of: #"\b(tasks?|to[ -]?dos?|deadlines?)\b"#, options: .regularExpression) != nil
      && text.range(of: #"\b(what|which|show|list|summari[sz]e|prioriti[sz]e|review|remaining|overdue|open|unfinished|incomplete)\b"#, options: .regularExpression) != nil
      && text.range(of: #"\b(create|add|delete|remove|complete|extract)\b"#, options: .regularExpression) == nil
  }

  static func searchTerm(_ value: String) -> String {
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized = text.lowercased().replacingOccurrences(of: "-", with: " ")
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    let generic = #"^(?:(?:all|my|the|open|unfinished|incomplete|pending)\s+)*(?:tasks?|todos?|to dos?|deadlines?)?$"#
    return normalized.range(of: generic, options: .regularExpression) != nil
      || ["all", "open", "unfinished", "incomplete", "pending"].contains(normalized) ? "" : text
  }

  @MainActor
  static func merging(_ tasks: AssistantContext, into overview: AssistantContext, provider: AssistantProvider) throws -> AssistantContext {
    guard var json = try JSONSerialization.jsonObject(with: Data(overview.json.utf8)) as? [String: Any],
      let records = try JSONSerialization.jsonObject(with: Data(tasks.json.utf8)) as? [String: Any] else {
      throw AssistantFailure("The task context could not be read. Please try again.")
    }
    json.merge(records) { _, new in new }
    return try WorkspaceStore.boundAssistantContext(json, maximumBytes: provider == .apple ? 5_000 : 14_000,
      summary: tasks.summary)
  }

  static func reply(_ context: AssistantContext) throws -> AssistantReply {
    guard let json = try JSONSerialization.jsonObject(with: Data(context.json.utf8)) as? [String: Any],
      json["taskSelection"] as? String == "allOpen",
      let total = json["openTaskCount"] as? Int, let rows = json["tasks"] as? [[String: Any]],
      total == rows.count + ((json["omitted"] as? [String: Int])?["tasks"] ?? 0) else {
      throw AssistantFailure("I couldn't verify the complete open-task list. Please try again.")
    }
    return AssistantReply(message: try section(json), actions: [])
  }

  static func section(_ json: [String: Any]) throws -> String {
    guard let tasks = json["tasks"] as? [[String: Any]] else { return "Open tasks were not retrieved." }
    let selection = json["taskSelection"] as? String ?? "allOpen" // Legacy explicit schedule snapshots.
    let omitted = (json["omitted"] as? [String: Int])?["tasks"] ?? 0
    let total = json["openTaskCount"] as? Int
    let heading = selection == "allOpen" ? "Open tasks" : "Matching open tasks"
    let date = DateFormatter()
    date.locale = .autoupdatingCurrent
    date.timeZone = (json["timeZone"] as? String).flatMap(TimeZone.init(identifier:)) ?? .current
    date.dateStyle = .medium; date.timeStyle = .short
    let now = try AssistantWireReply.date(json["now"] as? String)
    let lines = try tasks.map { task in
      var facts: [String] = []
      if let value = task["deadline"] as? String, !value.isEmpty, let deadline = try AssistantWireReply.date(value) {
        facts.append("\(now.map { deadline < $0 } == true ? "overdue · " : "")due \(date.string(from: deadline))")
      } else { facts.append("no deadline") }
      let minutes = task["minutes"] as? Int
      if let value = task["scheduledStart"] as? String, !value.isEmpty, let start = try AssistantWireReply.date(value) {
        facts.append("scheduled \(date.string(from: start))" + (minutes.map { " → \(date.string(from: start.addingTimeInterval(Double($0) * 60)))" } ?? "; duration missing"))
      } else { facts.append("unscheduled" + (minutes.map { " · \($0) min estimate" } ?? " · no duration estimate")) }
      if task["priority"] as? String == "high" { facts.append("high priority") }
      return "• \(task["title"] as? String ?? "Task") — \(facts.joined(separator: "; "))"
    }
    let body: String
    if !lines.isEmpty { body = lines.joined(separator: "\n") }
    else if selection != "allOpen" { body = "No matching tasks in this result. This is not the complete open-task list." }
    else if omitted > 0 || (total ?? 0) > 0 { body = "Open tasks exist, but their details were omitted from this snapshot." }
    else { body = "No open tasks in Struktur." }
    let count = selection == "allOpen" ? total.map { " · \($0) total" } ?? "" : ""
    return heading + count + "\n" + body + (omitted > 0 ? "\n\n\(omitted) more tasks omitted; open Tasks for the complete list." : "")
  }
}
