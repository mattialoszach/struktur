import XCTest

@testable import Struktur

@MainActor
final class RedesignTests: XCTestCase {
  private func withStore(_ action: (WorkspaceStore, URL) throws -> Void) rethrows {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "struktur-redesign-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "workspace.json")
    let store = WorkspaceStore(fileURL: url)
    store.replaceWorkspace(Workspace())
    try action(store, url)
  }

  func testLegacyPreferencesMigrateWithoutLosingChoices() throws {
    let json = Data(
      #"{"defaultCalendarMode":"month","taskRailPosition":"hidden","appearance":"dark","enabledWidgets":["quickNote","momentum"],"workingDayStart":8,"workingDayEnd":20}"#
        .utf8)
    let preferences = try JSONDecoder.struktur.decode(UserPreferences.self, from: json)
    XCTAssertEqual(preferences.defaultCalendarMode, .month)
    XCTAssertEqual(preferences.appearance, .dark)
    XCTAssertEqual(preferences.workingDayStart, 8)
    XCTAssertEqual(preferences.widgetLayout?.map(\.kind), [.dayFlow, .quickNote, .momentum])
  }

  func testWidgetIdentitySizingOrderAndPinsSurviveRelaunch() throws {
    try withStore { store, url in
      let project = Project(name: "Thesis", color: .lilac, suit: .spade)
      store.add(project)
      let first = WidgetConfiguration(kind: .projectPulse, projectID: project.id)
      let second = WidgetConfiguration(kind: .projectPulse)
      store.setWidgets([first, second])
      store.resizeWidget(first.id, columns: 2, rows: 2)
      store.moveWidget(second.id, before: first.id)
      let restored = WorkspaceStore(fileURL: url)
      XCTAssertEqual(restored.widgets.map(\.id), [second.id, first.id])
      XCTAssertEqual(restored.widgets[1].columns, 2)
      XCTAssertEqual(restored.widgets[1].rows, 2)
      XCTAssertEqual(restored.widgets[1].projectID, project.id)
      let decoded = try JSONDecoder.struktur.decode(Workspace.self, from: store.exportData())
      XCTAssertEqual(decoded.preferences.widgetLayout, restored.widgets)
    }
  }

  func testOriginalDefaultLayoutUpgradesToTheNewWorkspace() throws {
    let json = Data(
      #"{"enabledWidgets":["momentum","todayProgress","upcoming","projectPulse"],"taskRailPosition":"trailing","appearance":"dark","defaultCalendarMode":"month"}"#
        .utf8)
    let preferences = try JSONDecoder.struktur.decode(UserPreferences.self, from: json)
    XCTAssertEqual(
      preferences.widgetLayout?.map(\.kind), WidgetConfiguration.starterLayout.map(\.kind))
    XCTAssertEqual(preferences.appearance, .dark)
    XCTAssertEqual(preferences.defaultCalendarMode, .month)
  }

  func testLegacyWorkspacePreservesContentAndIdentifiers() throws {
    var original = WorkspaceStore.sampleWorkspace()
    original.schemaVersion = 1
    var json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder.struktur.encode(original)) as? [String: Any])
    for key in ["focusSession", "focusHistory", "isDemo"] { json.removeValue(forKey: key) }
    var preferences = try XCTUnwrap(json["preferences"] as? [String: Any])
    for key in ["widgetLayout", "displayName", "dashboardCalendarMode", "focusDurationMinutes"] {
      preferences.removeValue(forKey: key)
    }
    json["preferences"] = preferences
    for (collection, keys) in [
      ("tasks", ["linkedEventID", "recurrenceID"]), ("projects", ["suit"]),
    ] {
      json[collection] = try XCTUnwrap(json[collection] as? [[String: Any]]).map { item in
        var legacy = item
        for key in keys { legacy.removeValue(forKey: key) }
        return legacy
      }
    }
    let decoded = try JSONDecoder.struktur.decode(
      Workspace.self, from: JSONSerialization.data(withJSONObject: json))
    try decoded.validate()
    XCTAssertEqual(decoded.tasks.map(\.id), original.tasks.map(\.id))
    XCTAssertEqual(decoded.tasks.map(\.title), original.tasks.map(\.title))
    XCTAssertEqual(decoded.projects.map(\.id), original.projects.map(\.id))
    XCTAssertEqual(decoded.calendarEntries, original.calendarEntries)
    XCTAssertEqual(decoded.scratchpad, original.scratchpad)
    XCTAssertEqual(decoded.preferences.appearance, original.preferences.appearance)
    XCTAssertNotNil(decoded.preferences.widgetLayout)
    XCTAssertNil(decoded.isDemo)
  }

  func testGridPacksEveryWidgetWithoutOverlapAtAllSupportedWidths() {
    let sizes = [(2, 2), (1, 2), (1, 1), (1, 1), (2, 1), (1, 1), (4, 3), (1, 2)]
    for width: CGFloat in [700, 800, 1040, 1400] {
      let frames = WidgetGridGeometry.frames(width: width, sizes: sizes)
      XCTAssertEqual(frames.count, sizes.count)
      for (index, frame) in frames.enumerated() {
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertLessThanOrEqual(frame.maxX, width + 0.01)
        for other in frames.dropFirst(index + 1) { XCTAssertFalse(frame.intersects(other)) }
      }
    }
  }

  func testDeadlinesDoNotBecomeCalendarBlocksAndOverdueWorkStaysVisible() {
    withStore { store, _ in
      let day = Date().startOfDay
      let dueOnly = TaskItem(title: "Deadline only", dueDate: day.setting(hour: 17))
      let overdue = TaskItem(
        title: "Still needs attention", dueDate: day.adding(days: -1).setting(hour: 17))
      let scheduled = TaskItem(
        title: "Work on it", plannedStart: day.setting(hour: 10), estimateMinutes: 45)
      store.add(dueOnly)
      store.add(overdue)
      store.add(scheduled)
      XCTAssertEqual(store.blocks(on: day).map(\.id), [scheduled.id])
      XCTAssertEqual(
        Set(store.tasks(on: day).map(\.id)), Set([dueOnly.id, overdue.id, scheduled.id]))
      XCTAssertEqual(store.blocks(on: day).first?.end, day.setting(hour: 10, minute: 45))
    }
  }

  func testDailyTaskWithoutDeadlineCreatesOneFutureOccurrence() {
    withStore { store, _ in
      let daily = TaskItem(title: "Reset", cadence: .daily)
      store.add(daily)
      store.toggleTask(daily.id)
      let generated = store.tasks.filter { !$0.isCompleted }
      XCTAssertEqual(generated.count, 1)
      XCTAssertEqual(generated.first?.dueDate?.startOfDay, Date().adding(days: 1).startOfDay)
      XCTAssertTrue(store.tasks(on: Date()).isEmpty)
      store.toggleTask(daily.id)
      store.toggleTask(daily.id)
      XCTAssertEqual(store.tasks.filter { !$0.isCompleted }.count, 1)
    }
  }

  func testDifferentRecurringTasksWithSameTitleStayIndependent() {
    withStore { store, _ in
      let first = TaskItem(title: "Review", dueDate: Date().setting(hour: 19), cadence: .daily)
      let second = TaskItem(title: "Review", dueDate: Date().setting(hour: 19), cadence: .daily)
      store.add(first)
      store.add(second)
      store.toggleTask(first.id)
      store.toggleTask(second.id)
      XCTAssertEqual(store.tasks.filter { !$0.isCompleted }.count, 2)
    }
  }

  func testFocusPauseRelaunchResumeAndCompletionAreAccurate() {
    withStore { store, url in
      let now = Date(timeIntervalSince1970: 1_780_000_000)
      store.startFocus(minutes: 25, now: now)
      store.toggleFocusPause(now: now.addingTimeInterval(100))
      let restored = WorkspaceStore(fileURL: url)
      XCTAssertEqual(
        restored.workspace.focusSession?.remaining(at: now.addingTimeInterval(500)), 1400)
      XCTAssertEqual(restored.workspace.focusSession?.isPaused, true)
      restored.toggleFocusPause(now: now.addingTimeInterval(500))
      restored.reconcileFocus(now: now.addingTimeInterval(1900))
      XCTAssertNil(restored.workspace.focusSession)
      XCTAssertEqual(restored.workspace.focusHistory?.count, 1)
      XCTAssertEqual(restored.workspace.focusHistory?.first?.seconds, 1500)
      XCTAssertEqual(restored.workspace.focusHistory?.first?.completed, true)
      restored.reconcileFocus(now: now.addingTimeInterval(2000))
      XCTAssertEqual(restored.workspace.focusHistory?.count, 1)
    }
  }

  func testEarlyFocusFinishStoresOnlyTimeActuallySpent() {
    withStore { store, _ in
      let now = Date(timeIntervalSince1970: 1_780_000_000)
      store.startFocus(minutes: 25, now: now)
      store.toggleFocusPause(now: now.addingTimeInterval(120))
      store.finishFocus(now: now.addingTimeInterval(900))
      XCTAssertEqual(store.workspace.focusHistory?.first?.seconds, 120)
      XCTAssertEqual(store.workspace.focusHistory?.first?.completed, false)
    }
  }

  func testInvalidImportLeavesSavedDataUntouched() throws {
    try withStore { store, url in
      store.add(TaskItem(title: "Keep me"))
      let before = try Data(contentsOf: url)
      var invalid = Workspace()
      let now = Date()
      invalid.calendarEntries = [
        CalendarEntry(title: "Invalid", start: now, end: now.addingTimeInterval(-60))
      ]
      XCTAssertThrowsError(try store.importData(JSONEncoder.struktur.encode(invalid)))
      XCTAssertEqual(try Data(contentsOf: url), before)
      XCTAssertEqual(store.tasks.map(\.title), ["Keep me"])
    }
  }

  func testImportCreatesRecoverableBackup() throws {
    try withStore { store, url in
      store.add(TaskItem(title: "Before import"))
      let before = try Data(contentsOf: url)
      try store.importData(JSONEncoder.struktur.encode(Workspace()))
      let backups = try FileManager.default.contentsOfDirectory(
        at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil
      )
      .filter { $0.lastPathComponent.hasPrefix("workspace-backup-") }
      XCTAssertEqual(backups.count, 1)
      XCTAssertEqual(try Data(contentsOf: backups[0]), before)
      XCTAssertTrue(store.tasks.isEmpty)
    }
  }

  func testUnreadableWorkspaceIsNotSilentlyOverwritten() throws {
    try withStore { _, url in
      let invalid = Data("broken workspace".utf8)
      try invalid.write(to: url)
      let recovered = WorkspaceStore(fileURL: url)
      recovered.add(TaskItem(title: "Cannot overwrite the original"))
      recovered.saveNow()
      XCTAssertNotNil(recovered.lastSaveError)
      XCTAssertEqual(try Data(contentsOf: url), invalid)
    }
  }

  func testSpaceExportIncludesOnlyItsData() throws {
    try withStore { store, _ in
      let first = Project(name: "Thesis", color: .lilac)
      let second = Project(name: "Personal", color: .mint)
      store.add(first)
      store.add(second)
      store.add(TaskItem(title: "Thesis task", projectID: first.id))
      store.add(TaskItem(title: "Personal task", projectID: second.id))
      let result = try JSONDecoder.struktur.decode(
        Workspace.self, from: store.exportData(projectID: first.id))
      XCTAssertEqual(result.projects.map(\.id), [first.id])
      XCTAssertEqual(result.tasks.map(\.title), ["Thesis task"])
      XCTAssertTrue(result.scratchpad.isEmpty)
    }
  }

  func testDeletingAnEventClearsTaskReferences() {
    withStore { store, _ in
      let entry = CalendarEntry(
        title: "Seminar", start: Date(), end: Date().addingTimeInterval(3600))
      let task = TaskItem(title: "Prepare", linkedEventID: entry.id)
      store.add(entry)
      store.add(task)
      store.removeEntry(id: entry.id)
      XCTAssertNil(store.tasks.first?.linkedEventID)
    }
  }

  func testScheduleMergesOverlapsAndFindsActualFreeTime() {
    let day = Date().startOfDay
    let window = DateInterval(start: day.setting(hour: 9), end: day.setting(hour: 17))
    let intervals = [
      DateInterval(start: day.setting(hour: 8), end: day.setting(hour: 10)),
      DateInterval(start: day.setting(hour: 9), end: day.setting(hour: 11)),
      DateInterval(start: day.setting(hour: 13), end: day.setting(hour: 14)),
    ]
    XCTAssertEqual(
      ScheduleMath.merged(intervals, within: window).reduce(0) { $0 + $1.duration }, 3 * 3600)
    XCTAssertEqual(
      ScheduleMath.freeSlots(intervals, within: window).map(\.duration), [2 * 3600, 3 * 3600])
  }

  func testOverlapsGetLanesWhileTouchingEventsShareOneLane() {
    let day = Date().startOfDay
    func block(_ start: Int, _ end: Int) -> DayBlock {
      DayBlock(
        id: UUID(), title: "", start: day.setting(hour: start), end: day.setting(hour: end),
        color: .lilac)
    }
    let first = block(9, 11)
    let second = block(10, 12)
    let third = block(12, 13)
    let lanes = ScheduleMath.lanes(for: [third, second, first])
    XCTAssertEqual(lanes[first.id]?.count, 2)
    XCTAssertNotEqual(lanes[first.id]?.index, lanes[second.id]?.index)
    XCTAssertEqual(lanes[third.id]?.count, 1)
  }

  func testMultiDayEventsAppearOnEachCoveredDayButNotAtExclusiveEnd() {
    withStore { store, _ in
      let day = Date().startOfDay
      store.add(
        CalendarEntry(title: "Conference", start: day, end: day.adding(days: 2), isAllDay: true))
      XCTAssertEqual(store.blocks(on: day).count, 1)
      XCTAssertEqual(store.blocks(on: day.adding(days: 1)).count, 1)
      XCTAssertTrue(store.blocks(on: day.adding(days: 2)).isEmpty)
      XCTAssertEqual(store.scheduledSeconds(on: day), 0)
    }
  }

  func testMarkdownCheckboxRoundTripPreservesEverythingElse() {
    let source = "# Notes\n\n  - [ ] First **step**\n- [x] Second\nA normal line"
    let checked = MarkdownChecklist.toggling(line: 2, in: source)
    XCTAssertEqual(checked, "# Notes\n\n  - [x] First **step**\n- [x] Second\nA normal line")
    XCTAssertEqual(MarkdownChecklist.toggling(line: 2, in: checked), source)
    XCTAssertEqual(MarkdownChecklist.toggling(line: 99, in: source), source)
  }

  func testAppleRecurringOccurrencesHaveDistinctImportKeys() {
    let day = Date().startOfDay
    let first = CalendarEntry(
      title: "Lecture", start: day, end: day.addingTimeInterval(3600),
      externalIdentifier: "same-series")
    var next = first
    next.start = day.adding(days: 7)
    next.end = next.start.addingTimeInterval(3600)
    XCTAssertNotEqual(first.appleOccurrenceKey, next.appleOccurrenceKey)
    XCTAssertEqual(first.appleOccurrenceKey, first.appleOccurrenceKey)
  }

  func testAllDayEditorUsesInclusiveDatesWithoutExtendingEventOnEachSave() {
    let start = Date().startOfDay
    let event = CalendarEntry(
      title: "One whole day", start: start, end: start.adding(days: 1), isAllDay: true)
    XCTAssertEqual(event.editorCopy.start, event.editorCopy.end)
    XCTAssertEqual(event.editorCopy.savedCopy, event)
    XCTAssertEqual(event.editorCopy.savedCopy.editorCopy.savedCopy, event)
    let multiDay = CalendarEntry(
      title: "Three days", start: start, end: start.adding(days: 3), isAllDay: true)
    XCTAssertEqual(multiDay.editorCopy.end, start.adding(days: 2))
    XCTAssertEqual(multiDay.editorCopy.savedCopy, multiDay)
  }
}
