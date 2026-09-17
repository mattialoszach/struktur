import XCTest

@testable import Struktur

@MainActor
final class FocusNotesArchiveTests: XCTestCase {
  private func withStore(_ action: (WorkspaceStore, URL) throws -> Void) rethrows {
    let directory = FileManager.default.temporaryDirectory.appending(path: "struktur-focus-notes-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "workspace.json")
    let store = WorkspaceStore(fileURL: url)
    store.replaceWorkspace(Workspace())
    try action(store, url)
  }

  func testEarlyFinishPersistsActualTimeAndLeavesTaskOpen() throws {
    try withStore { store, url in
      let now = Date(timeIntervalSince1970: 1_800_000_000)
      let task = TaskItem(title: "Read", notes: "Task notes stay separate", createdAt: now)
      store.add(task)
      store.updateScratchpad("Shared notes stay here")
      store.startFocus(minutes: 25, taskID: task.id, now: now)
      store.toggleFocusPause(now: now.addingTimeInterval(90))
      store.toggleFocusPause(now: now.addingTimeInterval(300))
      store.finishFocus(now: now.addingTimeInterval(330))
      store.finishFocus(now: now.addingTimeInterval(400))
      let restored = WorkspaceStore(fileURL: url)
      let record = try XCTUnwrap(restored.workspace.focusHistory?.first)
      XCTAssertEqual(record.seconds, 120)
      XCTAssertFalse(record.completed)
      XCTAssertEqual(record.taskID, task.id)
      XCTAssertEqual(restored.workspace.focusHistory?.count, 1)
      XCTAssertEqual(restored.tasks, [task])
      XCTAssertEqual(restored.scratchpad, "Shared notes stay here")
      XCTAssertNil(restored.workspace.focusSession)
    }
  }

  func testPauseAndFinishAfterExpiryRecordTimerCompletionOnce() {
    withStore { store, _ in
      let now = Date(timeIntervalSince1970: 1_800_000_000)
      store.startFocus(minutes: 1, now: now)
      store.toggleFocusPause(now: now.addingTimeInterval(70))
      store.finishFocus(now: now.addingTimeInterval(80))
      XCTAssertNil(store.workspace.focusSession)
      XCTAssertEqual(store.workspace.focusHistory?.count, 1)
      XCTAssertEqual(store.workspace.focusHistory?.first?.seconds, 60)
      XCTAssertEqual(store.workspace.focusHistory?.first?.endedAt, now.addingTimeInterval(60))
      XCTAssertEqual(store.workspace.focusHistory?.first?.completed, true)
      store.startFocus(minutes: 1, now: now)
      store.finishFocus(now: now.addingTimeInterval(70))
      XCTAssertEqual(store.workspace.focusHistory?.last?.completed, true)
    }
  }

  func testScratchpadAutosavesLatestEditAndCheckboxAcrossRelaunch() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "struktur-autosave-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "workspace.json")
    let store = WorkspaceStore(fileURL: url)
    store.replaceWorkspace(Workspace())
    store.updateScratchpad("Draft")
    let source = "# Focus\n\n- [ ] Review notes\n"
    let checked = MarkdownChecklist.toggling(line: 2, in: source)
    store.updateScratchpad(checked)
    XCTAssertTrue(store.isSavePending)
    for _ in 0..<40 where store.isSavePending {
      try await Task.sleep(for: .milliseconds(50))
    }
    XCTAssertFalse(store.isSavePending)
    XCTAssertNil(store.lastSaveError)
    XCTAssertEqual(WorkspaceStore(fileURL: url).scratchpad, checked)
    store.updateScratchpad(source)
    store.saveNow()
    XCTAssertFalse(store.isSavePending)
    XCTAssertEqual(WorkspaceStore(fileURL: url).scratchpad, source)
  }

  func testScratchpadSaveFailureDoesNotReportPendingOrOverwriteUnreadableData() throws {
    try withStore { store, url in
      let invalid = Data("unreadable workspace".utf8)
      try invalid.write(to: url)
      let recovered = WorkspaceStore(fileURL: url)
      recovered.updateScratchpad("Keep the original file")
      recovered.saveNow()
      XCTAssertFalse(recovered.isSavePending)
      XCTAssertNotNil(recovered.lastSaveError)
      XCTAssertEqual(try Data(contentsOf: url), invalid)
    }
  }

  func testCheckboxOnlyTogglesLeadingMarkerAndPreservesIndentationAndLinks() {
    let source = "Example - [ ] stays literal\n\t  - [X] [Read](https://example.com)\n- [ ] **Next**\n"
    XCTAssertEqual(MarkdownChecklist.toggling(line: 0, in: source), source)
    let changed = MarkdownChecklist.toggling(line: 1, in: source)
    XCTAssertEqual(changed, source.replacingOccurrences(of: "- [X]", with: "- [ ]"))
    XCTAssertEqual(MarkdownChecklist.toggling(line: -1, in: source), source)
  }

  func testWorkspaceReferencesRejectPlaceholderAndMalformedLinks() throws {
    let id = UUID()
    for kind in ["task", "event", "goal", "space"] {
      let reference = try XCTUnwrap(WorkspaceReference(url: URL(string: "struktur://\(kind)/\(id)")!))
      XCTAssertEqual(reference.id, id)
      XCTAssertEqual(reference.kind.rawValue, kind)
    }
    for value in [
      "struktur://task/UID", "struktur://unknown/\(id)", "struktur://task/extra/\(id)",
      "https://task/\(id)", "struktur://task/\(id)?other=1", "struktur://task/\(id)#other",
    ] {
      XCTAssertNil(WorkspaceReference(url: URL(string: value)!))
    }
  }

  func testDeletingArchivedSpacePreservesContentsRelationshipsGoalsAndPreferences() throws {
    try withStore { store, url in
      var archived = Project(name: "Finished course", color: .lilac)
      archived.isArchived = true
      let other = Project(name: "Current course", color: .mint)
      store.add(archived)
      store.add(other)
      let now = Date(timeIntervalSince1970: 1_800_000_000)
      let series = CalendarEntry(title: "Lecture", start: now, end: now.addingTimeInterval(3600),
        projectID: archived.id, recurrence: CalendarRecurrence())
      store.add(series)
      let task = TaskItem(title: "Read", notes: "Keep notes", createdAt: now, cadence: .weekly,
        projectID: archived.id, linkedEventID: series.id)
      let unrelated = TaskItem(title: "Keep this too", createdAt: now, projectID: other.id)
      store.add(task)
      store.add(unrelated)
      store.saveGoal(TrackedGoal(title: "Reading", projectIDs: [archived.id, other.id]))
      let widget = WidgetConfiguration(kind: .tasks, columns: 2, rows: 2, projectID: archived.id)
      store.setWidgets([widget])
      store.updatePreferences { $0.appearance = .dark }
      store.updateScratchpad("Shared notes")
      store.startFocus(minutes: 25, taskID: task.id, now: now)
      XCTAssertTrue(store.removeArchivedProject(id: archived.id))
      XCTAssertFalse(store.removeArchivedProject(id: archived.id))
      let restored = WorkspaceStore(fileURL: url)
      XCTAssertNil(restored.project(archived.id))
      XCTAssertEqual(restored.workspace.projects, [other])
      var detachedTask = task
      detachedTask.projectID = nil
      XCTAssertEqual(restored.tasks, [detachedTask, unrelated])
      var detachedSeries = series
      detachedSeries.projectID = nil
      XCTAssertEqual(restored.entries, [detachedSeries])
      XCTAssertEqual(restored.workspace.focusSession?.taskID, task.id)
      XCTAssertEqual(restored.goals.first?.projectIDs, [other.id])
      XCTAssertEqual(restored.goals.first?.taskIDs, [task.id])
      var detachedWidget = widget
      detachedWidget.projectID = nil
      XCTAssertEqual(restored.widgets, [detachedWidget])
      XCTAssertEqual(restored.preferences.appearance, .dark)
      XCTAssertEqual(restored.scratchpad, "Shared notes")
      try restored.workspace.validate()
      let taskReference = try XCTUnwrap(WorkspaceReference(url: URL(string: "struktur://task/\(task.id)")!))
      XCTAssertTrue(restored.contains(taskReference))
      let deletedReference = try XCTUnwrap(WorkspaceReference(url: URL(string: "struktur://space/\(archived.id)")!))
      XCTAssertFalse(restored.contains(deletedReference))
    }
  }

  func testActiveSpaceCannotBePermanentlyDeleted() throws {
    try withStore { store, _ in
      let project = Project(name: "Active", color: .mint)
      store.add(project)
      let before = try store.exportData()
      XCTAssertFalse(store.removeArchivedProject(id: project.id))
      XCTAssertEqual(try store.exportData(), before)
    }
  }
}
