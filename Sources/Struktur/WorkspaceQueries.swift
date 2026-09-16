import Foundation

extension Workspace {
  func validate() throws {
    guard (1...3).contains(schemaVersion) else {
      throw WorkspaceValidationError.invalid(
        "This workspace was created by a newer version of Struktur.")
    }
    guard Set(projects.map(\.id)).count == projects.count,
      Set(tasks.map(\.id)).count == tasks.count,
      Set(calendarEntries.map(\.id)).count == calendarEntries.count
    else {
      throw WorkspaceValidationError.invalid("The workspace contains duplicate identifiers.")
    }
    guard calendarEntries.allSatisfy({ $0.end > $0.start }),
      tasks.allSatisfy({ (1...1440).contains($0.estimateMinutes) })
    else {
      throw WorkspaceValidationError.invalid(
        "An event has an invalid time range or a task has an invalid duration.")
    }
    if let widgets = preferences.widgetLayout {
      guard Set(widgets.map(\.id)).count == widgets.count,
        widgets.allSatisfy({ (1...4).contains($0.columns) && (1...3).contains($0.rows) })
      else {
        throw WorkspaceValidationError.invalid(
          "The widget layout contains invalid sizes or duplicate identifiers.")
      }
    }
    for event in calendarEntries {
      if let rule = event.recurrence {
        guard (1...52).contains(rule.interval), rule.weekdays.allSatisfy({ (1...7).contains($0) }),
          rule.count.map({ (1...1_000_000).contains($0) }) ?? true,
          rule.until.map({ $0 >= rule.calendar.startOfDay(for: event.start) }) ?? true,
          TimeZone(identifier: rule.timeZoneIdentifier) != nil, event.seriesID == nil,
          (event.excludedOccurrences ?? []).allSatisfy({ $0 >= 0 && $0 <= 1_000_000 })
        else {
          throw WorkspaceValidationError.invalid("A calendar repeat rule is invalid.")
        }
      }
      if let seriesID = event.seriesID {
        guard
          let master = calendarEntries.first(where: { $0.id == seriesID && $0.recurrence != nil }),
          let index = event.occurrenceIndex, (0...1_000_000).contains(index),
          master.occurrenceID(at: index) == event.id
        else {
          throw WorkspaceValidationError.invalid(
            "A calendar exception has an invalid series reference.")
        }
      }
    }
    let tracked = goals ?? []
    guard Set(tracked.map(\.id)).count == tracked.count,
      tracked.allSatisfy({
        !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          && (1...100_000).contains($0.target)
      })
    else {
      throw WorkspaceValidationError.invalid(
        "A goal has an invalid title, target, or duplicate identifier.")
    }
    if let session = focusSession {
      guard session.duration.isFinite, (60...10800).contains(session.duration),
        (session.endDate != nil) != (session.pausedRemaining != nil),
        session.pausedRemaining.map({ $0.isFinite && (0...session.duration).contains($0) }) ?? true
      else {
        throw WorkspaceValidationError.invalid("The focus session has an invalid duration.")
      }
    }
    let history = focusHistory ?? []
    guard Set(history.map(\.id)).count == history.count,
      history.allSatisfy({ $0.seconds.isFinite && (0...10800).contains($0.seconds) })
    else {
      throw WorkspaceValidationError.invalid(
        "Focus history contains invalid durations or duplicate sessions.")
    }
  }
}

enum WorkspaceValidationError: LocalizedError {
  case invalid(String)
  var errorDescription: String? { if case .invalid(let message) = self { message } else { nil } }
}

extension WorkspaceStore {
  var widgets: [WidgetConfiguration] {
    preferences.widgetLayout ?? WidgetConfiguration.starterLayout
  }

  func setWidgets(_ widgets: [WidgetConfiguration]) {
    updatePreferences { preferences in
      preferences.widgetLayout = widgets.map { widget in
        var value = widget
        value.columns = min(4, max(1, value.columns))
        value.rows = min(3, max(1, value.rows))
        return value
      }
      preferences.enabledWidgets = Array(Set(widgets.map(\.kind))).sorted {
        $0.rawValue < $1.rawValue
      }
    }
  }

  func resizeWidget(_ id: UUID, columns: Int, rows: Int) {
    var layout = widgets
    guard let index = layout.firstIndex(where: { $0.id == id }) else { return }
    layout[index].columns = columns
    layout[index].rows = rows
    setWidgets(layout)
  }

  func moveWidget(_ id: UUID, before target: UUID) {
    guard id != target else { return }
    var layout = widgets
    guard let source = layout.firstIndex(where: { $0.id == id }) else { return }
    let widget = layout.remove(at: source)
    guard let destination = layout.firstIndex(where: { $0.id == target }) else { return }
    layout.insert(widget, at: destination)
    setWidgets(layout)
  }

  func reorderWidget(_ id: UUID, to position: Int) {
    var layout = widgets
    guard let source = layout.firstIndex(where: { $0.id == id }) else { return }
    let item = layout.remove(at: source)
    layout.insert(item, at: max(0, min(layout.count, position)))
    setWidgets(layout)
  }

  func blocks(on day: Date, projectID: UUID? = nil) -> [DayBlock] {
    let start = day.startOfDay
    let end = start.adding(days: 1)
    let events = calendarEntries(in: DateInterval(start: start, end: end), projectID: projectID)
      .map {
        DayBlock(
          id: $0.id, title: $0.title, start: $0.start, end: $0.end,
          color: project($0.projectID)?.color ?? $0.color, projectID: $0.projectID, entry: $0)
      }
    let planned = tasks.compactMap { task -> DayBlock? in
      guard !task.isCompleted, let time = task.plannedStart,
        projectID == nil || task.projectID == projectID
      else { return nil }
      let finish = time.addingTimeInterval(TimeInterval(task.estimateMinutes * 60))
      guard time < end && finish > start else { return nil }
      return DayBlock(
        id: task.id, title: task.title, start: time, end: finish,
        color: project(task.projectID)?.color ?? task.color, projectID: task.projectID, task: task)
    }
    return (events + planned).sorted {
      $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start
    }
  }

  func tasks(on day: Date, includeOverdue: Bool = true, projectID: UUID? = nil) -> [TaskItem] {
    tasks.filter { task in
      guard !task.isCompleted, projectID == nil || task.projectID == projectID else { return false }
      let due =
        task.dueDate.map {
          Calendar.struktur.isDate($0, inSameDayAs: day) || (includeOverdue && $0 < day.startOfDay)
        } ?? false
      let scheduled =
        task.plannedStart.map { Calendar.struktur.isDate($0, inSameDayAs: day) } ?? false
      return due || scheduled
        || (task.cadence == .daily && task.dueDate == nil && task.plannedStart == nil)
    }.sorted {
      if $0.priority != $1.priority {
        let rank: [TaskPriority: Int] = [.high: 0, .normal: 1, .low: 2]
        return rank[$0.priority, default: 1] < rank[$1.priority, default: 1]
      }
      return ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
    }
  }

  func workingWindow(on day: Date) -> DateInterval {
    let start = day.setting(hour: preferences.workingDayStart)
    let end =
      preferences.workingDayEnd == 24
      ? day.startOfDay.adding(days: 1) : day.setting(hour: preferences.workingDayEnd)
    return DateInterval(start: start, end: max(start.addingTimeInterval(3600), end))
  }

  func scheduledSeconds(on day: Date, projectID: UUID? = nil) -> TimeInterval {
    let intervals = blocks(on: day, projectID: projectID).filter { !$0.isAllDay }.map {
      DateInterval(start: $0.start, end: $0.end)
    }
    return ScheduleMath.merged(intervals, within: workingWindow(on: day)).reduce(0) {
      $0 + $1.duration
    }
  }

  func completions(on day: Date) -> [TaskItem] {
    tasks.filter {
      $0.isCompleted
        && ($0.completedAt.map { Calendar.struktur.isDate($0, inSameDayAs: day) } ?? false)
    }
  }

  var streak: Int {
    let days = Set(tasks.filter(\.isCompleted).compactMap { $0.completedAt?.startOfDay })
    var date = Date().startOfDay
    if !days.contains(date) { date = date.adding(days: -1) }
    var total = 0
    while days.contains(date) {
      total += 1
      date = date.adding(days: -1)
    }
    return total
  }

  func weekStart(for date: Date) -> Date {
    var calendar = Calendar.autoupdatingCurrent
    calendar.firstWeekday = preferences.weekStartsMonday ? 2 : 1
    return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date.startOfDay
  }
}
