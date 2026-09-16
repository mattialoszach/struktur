import XCTest

@testable import Struktur

@MainActor
final class CompletionTests: XCTestCase {
  private func withStore(_ body: (WorkspaceStore, URL) throws -> Void) rethrows {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "struktur-completion-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "workspace.json")
    let store = WorkspaceStore(fileURL: url)
    store.replaceWorkspace(Workspace())
    try body(store, url)
  }
  private var zurich: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
    calendar.firstWeekday = 2
    return calendar
  }
  private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
    zurich.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
  }
  private func series(_ start: Date, frequency: RepeatFrequency = .weekly) -> CalendarEntry {
    CalendarEntry(
      title: "Lecture", start: start, end: start.addingTimeInterval(3600),
      recurrence: CalendarRecurrence(frequency: frequency, timeZoneIdentifier: "Europe/Zurich"))
  }

  func testWeeklyWallClockTimeSurvivesBothDSTTransitions() throws {
    for start in [date(2026, 3, 23), date(2026, 10, 19)] {
      let master = series(start)
      let next = try XCTUnwrap(master.occurrence(at: 1))
      XCTAssertEqual(zurich.component(.hour, from: next.start), 9)
      XCTAssertEqual(next.end.timeIntervalSince(next.start), 3600)
      XCTAssertNotEqual(next.start.timeIntervalSince(start), 7 * 86400)
    }
  }

  func testMultiWeekdayRulesRespectIntervalAndPartialFirstWeek() throws {
    var rule = CalendarRecurrence(
      interval: 2, weekdays: [2, 4, 6], timeZoneIdentifier: "Europe/Zurich")
    let start = date(2026, 9, 16)  // Wednesday.
    XCTAssertEqual(rule.start(at: 0, from: start), date(2026, 9, 16))
    XCTAssertEqual(rule.start(at: 1, from: start), date(2026, 9, 18))
    XCTAssertEqual(rule.start(at: 2, from: start), date(2026, 9, 28))
    rule.count = 3
    XCTAssertNil(rule.start(at: 3, from: start))
  }

  func testMonthlyEndOfMonthDoesNotDrift() {
    let master = series(date(2026, 1, 31), frequency: .monthly)
    XCTAssertEqual(master.occurrence(at: 1)?.start, date(2026, 2, 28))
    XCTAssertEqual(master.occurrence(at: 2)?.start, date(2026, 3, 31))
  }

  func testUntilDateIsInclusiveInSeriesTimeZone() {
    var master = series(date(2026, 9, 16), frequency: .daily)
    master.recurrence?.until = date(2026, 9, 18, 0)
    XCTAssertNotNil(master.occurrence(at: 2))
    XCTAssertNil(master.occurrence(at: 3))
  }

  func testRepeatingAllDayEventKeepsCalendarDaysAcrossDST() throws {
    var master = series(date(2026, 3, 28, 0), frequency: .daily)
    master.isAllDay = true
    master.end = date(2026, 3, 29, 0)
    let next = try XCTUnwrap(master.occurrence(at: 1))
    XCTAssertEqual(next.end, date(2026, 3, 30, 0))
    XCTAssertEqual(next.end.timeIntervalSince(next.start), 23 * 3600)
  }

  func testFarFutureQueriesDoNotMaterializeHistoryAndUIDsResolve() throws {
    try withStore { store, url in
      let master = series(date(2000, 1, 1), frequency: .daily)
      store.add(master)
      let occurrences = store.calendarEntries(on: date(2040, 1, 1))
      XCTAssertEqual(occurrences.count, 1)
      XCTAssertEqual(store.entries.count, 1)
      let occurrence = try XCTUnwrap(occurrences.first)
      XCTAssertEqual(store.resolveEntry(occurrence.id)?.start, occurrence.start)
      XCTAssertEqual(
        WorkspaceStore(fileURL: url).resolveEntry(occurrence.id)?.start, occurrence.start)
      XCTAssertEqual(master.index(for: occurrence.id), occurrence.occurrenceIndex)
    }
  }

  func testMovedExceptionAppearsOnlyAtItsNewTimeAndPersists() throws {
    try withStore { store, url in
      let master = series(date(2026, 9, 16))
      store.add(master)
      var occurrence = try XCTUnwrap(master.occurrence(at: 1))
      occurrence.start = date(2026, 9, 24, 11)
      occurrence.end = occurrence.start.addingTimeInterval(1800)
      occurrence.title = "Moved seminar"
      store.update(occurrence)
      XCTAssertTrue(store.calendarEntries(on: date(2026, 9, 23)).isEmpty)
      XCTAssertEqual(store.calendarEntries(on: date(2026, 9, 24)).map(\.title), ["Moved seminar"])
      let restored = WorkspaceStore(fileURL: url)
      try restored.workspace.validate()
      XCTAssertEqual(restored.resolveEntry(occurrence.id)?.title, "Moved seminar")
    }
  }

  func testDeleteFirstOccurrenceDoesNotDeleteSeriesAndWholeDeleteClearsReferences() throws {
    try withStore { store, _ in
      let master = series(date(2026, 9, 16))
      store.add(master)
      let first = try XCTUnwrap(master.occurrence(at: 0))
      let second = try XCTUnwrap(master.occurrence(at: 1))
      store.add(TaskItem(title: "Prepare", linkedEventID: second.id))
      store.deleteOccurrence(first)
      XCTAssertNil(store.resolveEntry(first.id))
      XCTAssertEqual(store.entries.count, 1)
      XCTAssertEqual(store.calendarEntries(on: date(2026, 9, 23)).count, 1)
      store.removeEntry(id: master.id)
      XCTAssertTrue(store.entries.isEmpty)
      XCTAssertNil(store.tasks.first?.linkedEventID)
    }
  }

  func testWholeSeriesChangesKeepExceptionAndOccurrenceIdentity() throws {
    try withStore { store, _ in
      var master = series(date(2026, 9, 16))
      store.add(master)
      var exception = try XCTUnwrap(master.occurrence(at: 1))
      exception.title = "Special session"
      store.update(exception)
      let futureID = master.occurrenceID(at: 2)
      master.title = "Renamed lecture"
      master.start = master.start.addingTimeInterval(3600)
      master.end = master.end.addingTimeInterval(3600)
      store.update(master)
      XCTAssertEqual(store.resolveEntry(exception.id)?.title, "Special session")
      XCTAssertEqual(store.resolveEntry(futureID)?.title, "Renamed lecture")
      XCTAssertEqual(zurich.component(.hour, from: store.resolveEntry(futureID)!.start), 10)
    }
  }

  func testInvalidRecurrenceAndOrphanExceptionAreRejected() throws {
    var workspace = Workspace()
    var invalid = series(date(2026, 9, 16))
    invalid.recurrence?.interval = 0
    workspace.calendarEntries = [invalid]
    XCTAssertThrowsError(try workspace.validate())
    workspace.calendarEntries = [series(date(2026, 9, 16)).occurrence(at: 1)!]
    XCTAssertThrowsError(try workspace.validate())
  }

  func testScopedSeriesExportKeepsMovedExceptionsWithoutLeakingOtherSpaces() throws {
    try withStore { store, _ in
      let a = Project(name: "University", color: .lilac)
      let b = Project(name: "Research", color: .mint)
      store.add(a)
      store.add(b)
      var master = series(date(2026, 9, 16))
      master.projectID = a.id
      store.add(master)
      var moved = try XCTUnwrap(master.occurrence(at: 1))
      moved.projectID = b.id
      store.update(moved)
      store.add(TaskItem(title: "Prepare research", projectID: b.id, linkedEventID: moved.id))
      let source = try JSONDecoder.struktur.decode(
        Workspace.self, from: store.exportData(projectID: a.id))
      let destination = try JSONDecoder.struktur.decode(
        Workspace.self, from: store.exportData(projectID: b.id))
      try source.validate()
      try destination.validate()
      XCTAssertEqual(source.calendarEntries.count, 1)
      XCTAssertNil(source.calendarEntries.first?.occurrence(at: 1))
      XCTAssertEqual(destination.calendarEntries.count, 1)
      XCTAssertEqual(destination.calendarEntries.first?.id, moved.id)
      XCTAssertNil(destination.calendarEntries.first?.seriesID)
      XCTAssertEqual(destination.tasks.first?.linkedEventID, moved.id)
      XCTAssertEqual(store.resolveEntry(moved.id)?.seriesID, master.id)
    }
  }

  func testShorteningAndStoppingSeriesClearOnlyMissingTaskReferences() throws {
    try withStore { store, url in
      var master = series(date(2026, 9, 16))
      store.add(master)
      let first = try XCTUnwrap(master.occurrence(at: 0))
      var exception = try XCTUnwrap(master.occurrence(at: 1))
      exception.title = "Keep exception"
      store.update(exception)
      let removed = try XCTUnwrap(master.occurrence(at: 3))
      store.add(TaskItem(title: "First", linkedEventID: first.id))
      store.add(TaskItem(title: "Exception", linkedEventID: exception.id))
      store.add(TaskItem(title: "Too late", linkedEventID: removed.id))
      master.recurrence?.count = 2
      store.update(master)
      XCTAssertEqual(store.tasks[0].linkedEventID, first.id)
      XCTAssertEqual(store.tasks[1].linkedEventID, exception.id)
      XCTAssertNil(store.tasks[2].linkedEventID)
      master.recurrence = nil
      store.update(master)
      XCTAssertNil(store.tasks[0].linkedEventID)
      XCTAssertEqual(store.tasks[1].linkedEventID, exception.id)
      XCTAssertNil(store.resolveEntry(exception.id)?.seriesID)
      XCTAssertNil(WorkspaceStore(fileURL: url).lastSaveError)
    }
  }

  func testNextBlockHasNoOneYearHorizonAndRespectsExceptionsAndProjectScope() throws {
    try withStore { store, _ in
      let project = Project(name: "Study", color: .lilac)
      store.add(project)
      var master = series(date(2026, 1, 1), frequency: .monthly)
      master.recurrence?.interval = 24
      master.projectID = project.id
      store.add(master)
      XCTAssertEqual(
        store.nextCalendarEntry(after: date(2026, 9, 16))?.start, date(2028, 1, 1))
      let next = try XCTUnwrap(master.occurrence(at: 1))
      store.deleteOccurrence(next)
      var moved = try XCTUnwrap(master.occurrence(at: 2))
      moved.start = date(2027, 5, 1)
      moved.end = moved.start.addingTimeInterval(3600)
      moved.projectID = nil
      store.update(moved)
      XCTAssertEqual(store.nextCalendarEntry(after: date(2026, 9, 16))?.id, moved.id)
      XCTAssertEqual(
        store.nextCalendarEntry(after: date(2026, 9, 16), projectID: project.id)?.start,
        date(2032, 1, 1))
      master.recurrence?.count = 3
      store.update(master)
      XCTAssertNil(store.nextCalendarEntry(after: date(2026, 9, 16), projectID: project.id))
    }
  }

  func testDailyAndWeeklyGoalsUseCompletionDatesAndDoNotDoubleCountReferences() {
    withStore { store, _ in
      let project = Project(name: "Study", color: .lilac)
      store.add(project)
      let day = date(2026, 9, 16)
      let today = TaskItem(
        title: "Today", isCompleted: true, completedAt: day, projectID: project.id)
      let yesterday = TaskItem(
        title: "Yesterday", isCompleted: true, completedAt: day.adding(days: -1),
        projectID: project.id)
      store.add(today)
      store.add(yesterday)
      var goal = TrackedGoal(
        title: "Study", period: .daily, target: 2, taskIDs: [today.id], projectIDs: [project.id])
      XCTAssertEqual(store.progress(for: goal, on: day).amount, 1)
      goal.period = .weekly
      XCTAssertEqual(store.progress(for: goal, on: day).amount, 2)
      XCTAssertTrue(store.progress(for: goal, on: day).achieved)
      XCTAssertEqual(store.progress(for: goal, on: day.adding(days: 7)).amount, 0)
    }
  }

  func testGoalReferencesFollowRecurringTaskFamily() throws {
    try withStore { store, _ in
      let task = TaskItem(title: "Read", cadence: .daily)
      store.add(task)
      let goal = TrackedGoal(title: "Keep reading", period: .ongoing, taskIDs: [task.id])
      store.toggleTask(task.id)
      let next = try XCTUnwrap(store.tasks.first { !$0.isCompleted })
      store.toggleTask(next.id)
      XCTAssertEqual(store.progress(for: goal).amount, 2)
    }
  }

  func testFocusGoalCountsActualAssignedTimeOnlyAndHonorsWeekStart() {
    withStore { store, _ in
      let task = TaskItem(title: "Read")
      store.add(task)
      let day = date(2026, 9, 20)
      store.startFocus(minutes: 25, taskID: task.id, now: day)
      store.finishFocus(now: day.addingTimeInterval(120))
      store.startFocus(minutes: 25, now: day)
      store.finishFocus(now: day.addingTimeInterval(120))
      let goal = TrackedGoal(title: "Focus", metric: .focusMinutes, taskIDs: [task.id])
      XCTAssertEqual(store.progress(for: goal, on: day).amount, 2)
      XCTAssertEqual(store.progress(for: goal, on: day.adding(days: 1)).amount, 0)
      store.updatePreferences { $0.weekStartsMonday = false }
      XCTAssertEqual(store.progress(for: goal, on: day.adding(days: 1)).amount, 2)
    }
  }

  func testGoalsAndWidgetPinsSurviveRelaunchAndScopedExport() throws {
    try withStore { store, url in
      let project = Project(name: "Study", color: .lilac)
      store.add(project)
      let task = TaskItem(title: "Read", projectID: project.id)
      store.add(task)
      let goal = TrackedGoal(title: "Read more", taskIDs: [task.id])
      store.saveGoal(goal)
      let widget = WidgetConfiguration(kind: .goals, rows: 2, goalID: goal.id)
      store.setWidgets([widget])
      let restored = WorkspaceStore(fileURL: url)
      XCTAssertEqual(restored.goals, [goal])
      XCTAssertEqual(restored.widgets.first?.goalID, goal.id)
      let export = try JSONDecoder.struktur.decode(
        Workspace.self, from: restored.exportData(projectID: project.id))
      XCTAssertEqual(export.goals, [goal])
      restored.removeGoal(goal.id)
      XCTAssertNil(restored.widgets.first?.goalID)
      XCTAssertEqual(restored.tasks.count, 1)
    }
  }

  func testMissingNewFieldsStillDecodeLegacyWorkspace() throws {
    let original = WorkspaceStore.sampleWorkspace()
    let baseline = try JSONDecoder.struktur.decode(
      Workspace.self, from: JSONEncoder.struktur.encode(original))
    var json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder.struktur.encode(original)) as? [String: Any])
    json["schemaVersion"] = 2
    json.removeValue(forKey: "goals")
    let restored = try JSONDecoder.struktur.decode(
      Workspace.self, from: JSONSerialization.data(withJSONObject: json))
    try restored.validate()
    XCTAssertNil(restored.goals)
    XCTAssertEqual(restored.tasks, baseline.tasks)
  }

  func testResizeUsesVisibleSpanAndClampsAtEveryGridWidth() {
    let narrow = WidgetGridGeometry.resized(
      columns: 4, rows: 2, displayedColumns: 2, width: 700,
      translation: CGSize(width: -358, height: 212))
    XCTAssertEqual(narrow.columns, 1)
    XCTAssertEqual(narrow.rows, 3)
    let tiny = WidgetGridGeometry.resized(
      columns: 1, rows: 1, displayedColumns: 4, width: 250,
      translation: CGSize(width: -10000, height: -10000))
    XCTAssertEqual(tiny.columns, 1)
    XCTAssertEqual(tiny.rows, 1)
  }

  func testPointerReorderMovesBothForwardAndBackward() {
    withStore { store, _ in
      let a = WidgetConfiguration(kind: .focus)
      let b = WidgetConfiguration(kind: .tasks)
      let c = WidgetConfiguration(kind: .goals)
      store.setWidgets([a, b, c])
      store.reorderWidget(a.id, to: 1)
      XCTAssertEqual(store.widgets.map(\.id), [b.id, a.id, c.id])
      store.reorderWidget(c.id, to: 0)
      XCTAssertEqual(store.widgets.map(\.id), [c.id, b.id, a.id])
    }
  }

  func testInvalidFocusStatesAndDuplicateHistoryAreRejected() {
    var workspace = Workspace()
    workspace.focusSession = FocusSession(startedAt: Date(), duration: 1500)
    XCTAssertThrowsError(try workspace.validate())
    workspace.focusSession = nil
    let record = FocusRecord(id: UUID(), endedAt: Date(), seconds: 60, completed: false)
    workspace.focusHistory = [record, record]
    XCTAssertThrowsError(try workspace.validate())
  }

  func testFirstSchemaUpgradeSavesOneRecoverableOriginalBackup() throws {
    try withStore { _, url in
      var legacy = Workspace()
      legacy.schemaVersion = 2
      legacy.tasks = [TaskItem(title: "Keep this")]
      let data = try JSONEncoder.struktur.encode(legacy)
      try data.write(to: url)
      let upgraded = WorkspaceStore(fileURL: url)
      upgraded.saveNow()
      upgraded.saveNow()
      let files = try FileManager.default.contentsOfDirectory(
        at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil
      )
      .filter { $0.lastPathComponent.hasPrefix("workspace-before-v3-") }
      XCTAssertEqual(files.count, 1)
      XCTAssertEqual(try Data(contentsOf: files[0]), data)
      XCTAssertEqual(upgraded.workspace.schemaVersion, 3)
    }
  }

  func testStressSaveRelaunchAndCalendarQueriesPreserveTenThousandTasks() throws {
    try withStore { store, url in
      var workspace = Workspace()
      let today = Date().startOfDay
      workspace.tasks = (0..<10_000).map {
        TaskItem(title: "Task \($0)", dueDate: today.adding(days: $0 % 30), estimateMinutes: 15)
      }
      workspace.calendarEntries = (0..<100).map {
        var event = series(today.setting(hour: 9).adding(days: $0 % 7))
        event.title = "Series \($0)"
        return event
      }
      store.replaceWorkspace(workspace)
      let restored = WorkspaceStore(fileURL: url)
      XCTAssertEqual(restored.tasks.count, 10_000)
      XCTAssertEqual(Set(restored.tasks.map(\.id)), Set(workspace.tasks.map(\.id)))
      XCTAssertEqual(
        restored.calendarEntries(in: DateInterval(start: today, end: today.adding(days: 7))).count,
        100)
      try restored.workspace.validate()
    }
  }
}
