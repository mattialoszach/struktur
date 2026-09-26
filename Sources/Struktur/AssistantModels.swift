import Foundation
import CoreGraphics

enum AssistantPanelPosition: String, Codable, CaseIterable, Identifiable, Sendable {
  case left, middle, right

  var id: String { rawValue }
  var title: String { rawValue.capitalized }

  func centerX(in availableWidth: CGFloat, panelWidth: CGFloat, margin: CGFloat = 12) -> CGFloat {
    let left = margin + panelWidth / 2
    let right = max(left, availableWidth - margin - panelWidth / 2)
    switch self {
    case .left: return left
    case .middle: return (left + right) / 2
    case .right: return right
    }
  }

  static func nearest(to centerX: CGFloat, in availableWidth: CGFloat,
    panelWidth: CGFloat, margin: CGFloat = 12) -> Self {
    allCases.min {
      abs($0.centerX(in: availableWidth, panelWidth: panelWidth, margin: margin) - centerX)
        < abs($1.centerX(in: availableWidth, panelWidth: panelWidth, margin: margin) - centerX)
    } ?? .right
  }

  func draggedCenterX(_ translation: CGFloat, in availableWidth: CGFloat, panelWidth: CGFloat) -> CGFloat {
    let left = Self.left.centerX(in: availableWidth, panelWidth: panelWidth)
    let right = Self.right.centerX(in: availableWidth, panelWidth: panelWidth)
    return min(right, max(left, centerX(in: availableWidth, panelWidth: panelWidth) + translation))
  }

  func destination(after translation: CGFloat, in availableWidth: CGFloat, panelWidth: CGFloat) -> Self {
    let left = Self.left.centerX(in: availableWidth, panelWidth: panelWidth)
    let right = Self.right.centerX(in: availableWidth, panelWidth: panelWidth)
    // Clicking the title or fitting the panel into a narrow area must not change
    // the saved preference just because multiple anchors coincide.
    guard abs(translation) >= 4, right > left else { return self }
    return Self.nearest(to: draggedCenterX(translation, in: availableWidth, panelWidth: panelWidth),
      in: availableWidth, panelWidth: panelWidth)
  }
}

struct AssistantPreferences: Codable, Equatable, Sendable {
  var model = "gpt-4.1-mini"
  var provider: AssistantProvider = .apple
  var position: AssistantPanelPosition = .right

  init(model: String = "gpt-4.1-mini", provider: AssistantProvider = .apple,
    position: AssistantPanelPosition = .right) {
    self.model = model
    self.provider = provider
    self.position = position
  }

  private enum CodingKeys: String, CodingKey { case model, provider, position }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    model = try values.decodeIfPresent(String.self, forKey: .model) ?? "gpt-4.1-mini"
    provider = try values.decodeIfPresent(AssistantProvider.self, forKey: .provider) ?? .apple
    position = try values.decodeIfPresent(AssistantPanelPosition.self, forKey: .position) ?? .right
  }
}

enum AssistantProvider: String, Codable, CaseIterable, Identifiable, Sendable {
  case apple, openAI
  var id: String { rawValue }
  var title: String { self == .apple ? "Apple · On this Mac" : "OpenAI · Cloud" }
  var messageLimit: Int { self == .apple ? 2_000 : 8_000 }
}

enum AssistantScope: String, CaseIterable, Identifiable {
  case schedule, note, message
  var id: String { rawValue }
  var title: String {
    switch self {
    case .schedule: "Schedule & tasks"
    case .note: "Current note"
    case .message: "Message only"
    }
  }
}

struct AssistantFailure: LocalizedError, Equatable {
  let message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}

/// A constrained creation tool. Identifiers are assigned by the app, never by the model.
struct AssistantAction: Identifiable, Equatable, Sendable {
  enum Kind: String, Codable, Sendable { case task, event }
  var id = UUID()
  var kind: Kind
  var title: String
  var notes = ""
  var projectID: UUID?
  var dueDate: Date?
  var start: Date?
  var end: Date?
  var estimateMinutes: Int?
  var priority: TaskPriority = .normal
  var eventKind: ItemKind = .personal
  var location = ""

  func validate(projectIDs: Set<UUID>) throws {
    guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      title.count <= 300, notes.count <= 12_000, location.count <= 500
    else { throw AssistantFailure("Give each item a title of 1–300 characters and keep its notes under 12,000 characters.") }
    if let projectID, !projectIDs.contains(projectID) {
      throw AssistantFailure("A proposed space is no longer available. Choose another space or None.")
    }
    if let estimateMinutes, !(1...1440).contains(estimateMinutes) {
      throw AssistantFailure("Estimated duration must be between 1 minute and 24 hours.")
    }
    let supported = Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 7_258_118_400)
    guard [dueDate, start, end].compactMap({ $0 }).allSatisfy({ supported.contains($0) }) else {
      throw AssistantFailure("A proposed date is outside the supported range (1970–2200).")
    }
    if kind == .event {
      guard let start, let end, end > start, end.timeIntervalSince(start) <= 31 * 86400 else {
        throw AssistantFailure("Calendar blocks need a start and a later end, at most 31 days apart.")
      }
      guard dueDate == nil else { throw AssistantFailure("Use a task deadline separately from a calendar block.") }
    } else {
      guard end == nil else { throw AssistantFailure("Scheduled tasks use their estimated duration, not a separate end date.") }
      guard start == nil || estimateMinutes != nil else {
        throw AssistantFailure("A scheduled task needs an estimated duration so its end time is clear.")
      }
      if let dueDate, let interval, interval.end > dueDate {
        throw AssistantFailure("This task would finish after its deadline. Adjust its scheduled time or deadline.")
      }
    }
  }

  var interval: DateInterval? {
    guard let start else { return nil }
    let finish = kind == .event ? end : estimateMinutes.map { start.addingTimeInterval(Double($0) * 60) }
    guard let finish, finish > start else { return nil }
    return DateInterval(start: start, end: finish)
  }

  var task: TaskItem {
    TaskItem(id: id, title: title.trimmingCharacters(in: .whitespacesAndNewlines), notes: notes,
      dueDate: dueDate, plannedStart: start, priority: priority, projectID: projectID,
      estimateMinutes: estimateMinutes)
  }
  var event: CalendarEntry {
    CalendarEntry(id: id, title: title.trimmingCharacters(in: .whitespacesAndNewlines), notes: notes,
      start: start ?? .distantPast, end: end ?? .distantPast, kind: eventKind,
      projectID: projectID, location: location)
  }
}

struct AssistantReply: Sendable {
  var message: String
  var actions: [AssistantAction]
}

/// Decode independently of UI and reject unsupported or ambiguous tool arguments.
struct AssistantWireReply: Decodable {
  var message: String
  var actions: [Action]
  struct Action: Decodable {
    var kind: AssistantAction.Kind
    var title: String
    var notes: String
    var projectID: String?
    var dueDate: String?
    var start: String?
    var end: String?
    var estimateMinutes: Int?
    var priority: TaskPriority
    var eventKind: ItemKind
    var location: String
  }

  func validated(projectIDs: Set<UUID>) throws -> AssistantReply {
    guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      message.count <= 20_000, actions.count <= 12
    else { throw AssistantFailure("The answer was too large or empty. Try a smaller request.") }
    let values = try actions.map { action in
      var project: UUID?
      if let value = action.projectID {
        guard let id = UUID(uuidString: value), projectIDs.contains(id) else {
          throw AssistantFailure("The assistant suggested an unknown space. Please try again.")
        }
        project = id
      }
      let value = AssistantAction(kind: action.kind, title: action.title, notes: action.notes,
        projectID: project, dueDate: try Self.date(action.dueDate), start: try Self.date(action.start),
        end: try Self.date(action.end), estimateMinutes: action.estimateMinutes,
        priority: action.priority, eventKind: action.eventKind, location: action.location)
      try value.validate(projectIDs: projectIDs)
      return value
    }
    return AssistantReply(message: message, actions: values)
  }

  static func date(_ value: String?) throws -> Date? {
    guard let value else { return nil }
    // A timezone is mandatory: relative/local strings must never silently become UTC.
    guard value.range(of: #"(Z|[+-]\d{2}:\d{2})$"#, options: .regularExpression) != nil else {
      throw AssistantFailure("The assistant returned an ambiguous time. Please try again with a date and time.")
    }
    let formatter = ISO8601DateFormatter()
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions.insert(.withFractionalSeconds)
    guard let date = formatter.date(from: value) else {
      throw AssistantFailure("The assistant returned an invalid date. Please try again.")
    }
    return date
  }
}

struct AssistantContext: Sendable {
  var json: String
  var summary: String
  var projectIDs: Set<UUID>
}

@MainActor
extension WorkspaceStore {
  func assistantContext(scope: AssistantScope, anchor: Date, now: Date = Date(),
    provider: AssistantProvider = .openAI) throws -> AssistantContext {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = Calendar.struktur.timeZone
    func stamp(_ date: Date) -> String { formatter.string(from: date) }
    var context: [String: Any] = ["now": stamp(now), "timeZone": Calendar.struktur.timeZone.identifier,
      "selectedDate": stamp(anchor.startOfDay), "scope": scope.rawValue]
    var summary = "Only your message, date, and timezone."
    var projectIDs: Set<UUID> = []
    switch scope {
    case .message: break
    case .note:
      guard let note = note(noteLibrary.selectedNoteID), note.deletedAt == nil else {
        throw AssistantFailure("Open a note first, or choose another context.")
      }
      let limit = 24_000
      context["note"] = ["id": note.id.uuidString, "title": String(note.title.prefix(300)),
        "markdown": String(note.markdown.prefix(limit)), "truncated": note.markdown.count > limit]
      summary = "“\(note.displayTitle)” · text only\(note.markdown.count > limit ? " · first 24,000 characters" : "")"
    case .schedule:
      let window = DateInterval(start: anchor.startOfDay, end: anchor.startOfDay.adding(days: 14))
      let allEvents = calendarEntries(in: window)
      let openTasks = tasks.filter { !$0.isCompleted }.sorted {
        let a = $0.dueDate ?? $0.plannedStart ?? .distantFuture
        let b = $1.dueDate ?? $1.plannedStart ?? .distantFuture
        return a == b ? $0.id.uuidString < $1.id.uuidString : a < b
      }
      let spaces = Array(projects.prefix(100))
      projectIDs = Set(spaces.map(\.id))
      context["spaces"] = spaces.map { ["id": $0.id.uuidString, "name": String($0.name.prefix(300))] }
      context["workingHours"] = ["start": preferences.workingDayStart, "end": preferences.workingDayEnd]
      context["window"] = ["start": stamp(window.start), "endExclusive": stamp(window.end)]
      context["events"] = allEvents.prefix(150).map { entry -> [String: Any] in
        ["id": entry.id.uuidString, "title": String(entry.title.prefix(300)), "start": stamp(entry.start),
          "end": stamp(entry.end), "allDay": entry.isAllDay, "kind": entry.kind.rawValue,
          "spaceID": entry.projectID?.uuidString ?? ""]
      }
      context["tasks"] = openTasks.prefix(100).map { task -> [String: Any] in
        ["id": task.id.uuidString, "title": String(task.title.prefix(300)),
          "deadline": task.dueDate.map(stamp) ?? "", "scheduledStart": task.plannedStart.map(stamp) ?? "",
          "minutes": task.estimateMinutes.map { $0 as Any } ?? NSNull(),
          "priority": task.priority.rawValue,
          "spaceID": task.projectID?.uuidString ?? "", "linkedEventID": task.linkedEventID?.uuidString ?? ""]
      }
      context["omitted"] = ["events": max(0, allEvents.count - 150), "tasks": max(0, openTasks.count - 100),
        "spaces": max(0, projects.count - 100)]
      summary = "\(min(100, openTasks.count)) open tasks · \(min(150, allEvents.count)) blocks · 14 days from \(anchor.formatted(date: .abbreviated, time: .omitted))"
      if openTasks.count > 100 || allEvents.count > 150 || projects.count > 100 { summary += " · limited context" }
    }
    if provider == .apple {
      return try AppleAssistantContext.compact(context)
    }
    let data = try JSONSerialization.data(withJSONObject: context, options: [.prettyPrinted, .sortedKeys])
    return AssistantContext(json: String(decoding: data, as: UTF8.self), summary: summary, projectIDs: projectIDs)
  }

  func assistantConflicts(_ action: AssistantAction, among proposals: [AssistantAction]) -> [String] {
    guard let interval = action.interval else { return [] }
    func overlaps(_ start: Date, _ end: Date) -> Bool { start < interval.end && end > interval.start }
    var titles = calendarEntries(in: interval).filter { $0.id != action.id && overlaps($0.start, $0.end) }.map(\.title)
    titles += tasks.compactMap { task -> String? in
      guard task.id != action.id, !task.isCompleted, let start = task.plannedStart,
        let estimate = task.estimateMinutes,
        overlaps(start, start.addingTimeInterval(Double(estimate) * 60)) else { return nil }
      return task.title
    }
    titles += proposals.compactMap { other -> String? in
      guard other.id != action.id, let span = other.interval, overlaps(span.start, span.end) else { return nil }
      return other.title
    }
    return Array(Set(titles)).sorted()
  }
}

struct AssistantReceipt: Equatable {
  var generation: UUID
  var tasks: [TaskItem]
  var events: [CalendarEntry]
}
