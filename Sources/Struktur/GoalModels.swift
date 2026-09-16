import Foundation

enum GoalPeriod: String, Codable, CaseIterable, Identifiable {
  case daily, weekly, ongoing
  var id: String { rawValue }
  var title: String { rawValue.capitalized }
}

enum GoalMetric: String, Codable, CaseIterable, Identifiable {
  case completedTasks, focusMinutes
  var id: String { rawValue }
  var title: String { self == .completedTasks ? "Completed tasks" : "Focus minutes" }
}

struct TrackedGoal: Identifiable, Codable, Equatable {
  var id = UUID()
  var title: String
  var detail = ""
  var period: GoalPeriod = .weekly
  var metric: GoalMetric = .completedTasks
  var target = 5
  var taskIDs: [UUID] = []
  var projectIDs: [UUID] = []
  var color: AccentToken = .mint
  var symbol: SuitSymbol = .club
}

struct GoalProgress {
  let amount: Double
  let target: Int
  let periodEnd: Date?
  var fraction: Double { min(1, max(0, amount / Double(max(1, target)))) }
  var achieved: Bool { amount >= Double(target) }
}

extension WorkspaceStore {
  var goals: [TrackedGoal] { workspace.goals ?? [] }

  func tasks(for goal: TrackedGoal) -> [TaskItem] {
    let selectedFamilies = Set(
      tasks.filter { goal.taskIDs.contains($0.id) }.map { $0.recurrenceID ?? $0.id }
    )
    .union(goal.taskIDs)
    return tasks.filter {
      goal.taskIDs.contains($0.id) || selectedFamilies.contains($0.recurrenceID ?? $0.id)
        || $0.projectID.map(goal.projectIDs.contains) == true
    }
  }

  func progress(for goal: TrackedGoal, on day: Date = Date()) -> GoalProgress {
    let start: Date
    let end: Date?
    switch goal.period {
    case .daily:
      start = day.startOfDay
      end = start.adding(days: 1)
    case .weekly:
      start = weekStart(for: day)
      end = start.adding(days: 7)
    case .ongoing:
      start = .distantPast
      end = nil
    }
    let selected = tasks(for: goal)
    let ids = Set(selected.map(\.id))
    func included(_ date: Date) -> Bool { date >= start && date < (end ?? .distantFuture) }
    let amount: Double
    switch goal.metric {
    case .completedTasks:
      amount = Double(
        selected.filter { $0.isCompleted && $0.completedAt.map(included) == true }.count)
    case .focusMinutes:
      amount =
        (workspace.focusHistory ?? []).filter {
          $0.taskID.map(ids.contains) == true && included($0.endedAt)
        }.reduce(0) { $0 + $1.seconds } / 60
    }
    return GoalProgress(amount: amount, target: goal.target, periodEnd: end)
  }
}
