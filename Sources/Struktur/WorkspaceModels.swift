import SwiftUI

enum SuitSymbol: String, CaseIterable, Codable, Identifiable {
  case heart, diamond, spade, club
  var id: String { rawValue }
  var icon: String { "suit.\(rawValue).fill" }
  var title: String { rawValue.capitalized }
  var color: AccentToken {
    switch self {
    case .heart: .rose
    case .diamond: .butter
    case .spade: .lilac
    case .club: .mint
    }
  }
}

extension AccentToken {
  var symbol: SuitSymbol {
    switch self {
    case .rose, .peach: .heart
    case .butter: .diamond
    case .lilac, .sky, .graphite: .spade
    case .mint: .club
    }
  }
}

struct WidgetConfiguration: Identifiable, Codable, Equatable {
  var id = UUID()
  var kind: DashboardWidgetKind
  var columns = 1
  var rows = 1
  var projectID: UUID?
  var goalID: UUID?

  static var starterLayout: [Self] {
    [
      Self(kind: .dayFlow, columns: 2, rows: 2),
      Self(kind: .tasks, rows: 2), Self(kind: .focus), Self(kind: .deadlines),
      Self(kind: .connections, columns: 2), Self(kind: .momentum), Self(kind: .projectPulse),
    ]
  }
}

extension DashboardWidgetKind {
  var detail: String {
    switch self {
    case .dayFlow: "Your schedule, breathing room, and clear end times."
    case .tasks: "Check off the next step. Keep the deadline in sight."
    case .focus: "A shared focus timer that stays with you."
    case .deadlines: "See what's approaching before it becomes urgent."
    case .connections: "Follow the threads between your spaces, tasks, and time."
    case .momentum: "An honest picture of your week, built from completed work."
    case .todayProgress: "Today's finished work, at a glance."
    case .upcoming: "The next calendar block, and exactly when it ends."
    case .projectPulse: "Pin a space and watch its goal take shape."
    case .quickNote: "A small home for big ideas, with live Markdown checklists."
    case .goals: "Daily, weekly, or ongoing goals linked to the tasks you choose."
    }
  }
  var accent: AccentToken {
    switch self {
    case .focus, .momentum: .lilac
    case .deadlines, .upcoming: .peach
    case .projectPulse, .todayProgress: .mint
    case .quickNote: .butter
    default: .sky
    }
  }
}

struct FocusSession: Codable, Equatable {
  var id = UUID()
  var taskID: UUID?
  var startedAt: Date
  var duration: TimeInterval
  var endDate: Date?
  var pausedRemaining: TimeInterval?
  func remaining(at date: Date) -> TimeInterval {
    max(0, pausedRemaining ?? endDate?.timeIntervalSince(date) ?? 0)
  }
  var isPaused: Bool { pausedRemaining != nil }
}

struct FocusRecord: Identifiable, Codable, Equatable {
  var id: UUID
  var taskID: UUID?
  var endedAt: Date
  var seconds: TimeInterval
  var completed: Bool
}

struct DayBlock: Identifiable {
  var id: UUID
  var title: String
  var start: Date
  var end: Date
  var color: AccentToken
  var projectID: UUID?
  var entry: CalendarEntry?
  var task: TaskItem?
  var isAllDay: Bool { entry?.isAllDay == true }
}

enum ScheduleMath {
  static func merged(_ intervals: [DateInterval], within window: DateInterval) -> [DateInterval] {
    let clipped = intervals.compactMap { interval -> DateInterval? in
      let start = max(interval.start, window.start)
      let end = min(interval.end, window.end)
      return end > start ? DateInterval(start: start, end: end) : nil
    }.sorted { $0.start < $1.start }
    var result: [DateInterval] = []
    for interval in clipped {
      if let last = result.last, interval.start <= last.end {
        result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
      } else {
        result.append(interval)
      }
    }
    return result
  }
  static func freeSlots(_ intervals: [DateInterval], within window: DateInterval) -> [DateInterval]
  {
    var cursor = window.start
    var result: [DateInterval] = []
    for interval in merged(intervals, within: window) {
      if interval.start > cursor { result.append(DateInterval(start: cursor, end: interval.start)) }
      cursor = interval.end
    }
    if cursor < window.end { result.append(DateInterval(start: cursor, end: window.end)) }
    return result
  }
  static func lanes(for blocks: [DayBlock]) -> [UUID: (index: Int, count: Int)] {
    let ordered = blocks.sorted { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }
    var result: [UUID: (index: Int, count: Int)] = [:]
    var group: [DayBlock] = []
    var groupEnd = Date.distantPast
    func flush() {
      var ends: [Date] = []
      var positions: [UUID: Int] = [:]
      for block in group {
        let lane = ends.firstIndex { $0 <= block.start } ?? ends.count
        if lane == ends.count { ends.append(block.end) } else { ends[lane] = block.end }
        positions[block.id] = lane
      }
      for (id, lane) in positions { result[id] = (lane, max(1, ends.count)) }
    }
    for block in ordered {
      if block.start >= groupEnd, !group.isEmpty {
        flush()
        group = []
      }
      group.append(block)
      groupEnd = group.count == 1 ? block.end : max(groupEnd, block.end)
    }
    flush()
    return result
  }
}

func durationText(_ seconds: TimeInterval) -> String {
  let minutes = max(0, Int(seconds / 60))
  if minutes < 60 { return "\(minutes)m" }
  return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
}

extension CalendarEntry {
  var editorCopy: Self {
    guard isAllDay else { return self }
    var copy = self
    copy.start = start.startOfDay
    copy.end = max(copy.start, end.addingTimeInterval(-1).startOfDay)
    return copy
  }
  var savedCopy: Self {
    guard isAllDay else { return self }
    var copy = self
    copy.start = start.startOfDay
    copy.end = max(copy.start, end.startOfDay).adding(days: 1)
    return copy
  }
}

func deadlineText(_ date: Date, relativeTo now: Date = Date()) -> String {
  if date < now {
    let days = Int(now.timeIntervalSince(date) / 86400)
    return "\(days > 0 ? "\(days)d" : durationText(now.timeIntervalSince(date))) overdue"
  }
  if Calendar.struktur.isDate(date, inSameDayAs: now) {
    return "Due " + date.formatted(.dateTime.hour().minute())
  }
  if Calendar.struktur.isDate(date, inSameDayAs: now.adding(days: 1)) { return "Tomorrow" }
  let days =
    Calendar.struktur.dateComponents([.day], from: now.startOfDay, to: date.startOfDay).day ?? 0
  if days < 7 { return "In \(days) days" }
  return date.formatted(.dateTime.day().month(.abbreviated))
}
