import XCTest

@testable import Struktur

@MainActor
final class FocusSessionLibraryTests: XCTestCase {
  private func withStore(_ action: (WorkspaceStore, URL) throws -> Void) rethrows {
    let directory = FileManager.default.temporaryDirectory.appending(path: "struktur-session-tests-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "workspace.json")
    let store = WorkspaceStore(fileURL: url)
    store.replaceWorkspace(Workspace())
    try action(store, url)
  }

  func testSessionTitleAndNoteSnapshotSurviveFinishClearAndRelaunch() throws {
    try withStore { store, url in
      let now = Date(timeIntervalSince1970: 1_800_000_000)
      store.updateFocusTitle("  Read chapter one  ")
      store.updateScratchpad("# Draft\n- [] Check references")
      store.startFocus(minutes: 25, now: now)
      store.toggleFocusPause(now: now.addingTimeInterval(120))
      let resumed = WorkspaceStore(fileURL: url)
      XCTAssertEqual(resumed.focusTitle, "Read chapter one")
      resumed.updateFocusTitle("Chapter one summary")
      resumed.updateScratchpad("# Summary\n- [x] Check references")
      resumed.finishFocus(now: now.addingTimeInterval(900))
      let record = try XCTUnwrap(resumed.savedFocusSessions().first)
      XCTAssertEqual(record.title, "Chapter one summary")
      XCTAssertEqual(record.notes, "# Summary\n- [x] Check references")
      XCTAssertEqual(record.seconds, 120)
      resumed.clearScratchpad()
      resumed.updateFocusTitle("Next chapter")
      resumed.startFocus(minutes: 25, now: now.addingTimeInterval(1000))
      resumed.finishFocus(now: now.addingTimeInterval(1060))
      let restored = WorkspaceStore(fileURL: url)
      XCTAssertEqual(restored.workspace.focusHistory?.first, record)
      XCTAssertEqual(restored.workspace.focusHistory?.last?.notes, "")
      XCTAssertEqual(restored.workspace.focusHistory?.last?.title, "Next chapter")
      XCTAssertEqual(restored.focusTitle, "")
      XCTAssertEqual(restored.scratchpad, "")
    }
  }

  func testDraftTitlePersistsAndTimedCompletionCapturesNotesWithoutClearingWorkingText() {
    withStore { store, url in
      store.updateFocusTitle("An idea")
      store.updateScratchpad("An unfinished thought")
      store.saveNow()
      let restored = WorkspaceStore(fileURL: url)
      XCTAssertEqual(restored.focusTitle, "An idea")
      let now = Date(timeIntervalSince1970: 1_800_000_000)
      restored.startFocus(minutes: 1, now: now)
      restored.reconcileFocus(now: now.addingTimeInterval(90))
      let saved = restored.savedFocusSessions().first
      XCTAssertEqual(saved?.title, "An idea")
      XCTAssertEqual(saved?.notes, "An unfinished thought")
      XCTAssertEqual(saved?.completed, true)
      XCTAssertEqual(restored.scratchpad, "An unfinished thought")
      XCTAssertNil(restored.workspace.focusDraftTitle)
    }
  }

  func testLegacyRecordsDoNotAcquireUnrelatedWorkingNotes() throws {
    try withStore { store, _ in
      let task = TaskItem(title: "Old reading session")
      var workspace = Workspace()
      workspace.tasks = [task]
      workspace.scratchpad = "These notes belong to today"
      workspace.focusHistory = [FocusRecord(id: UUID(), taskID: task.id,
        endedAt: Date(timeIntervalSince1970: 1_700_000_000), seconds: 300, completed: false)]
      workspace.focusSession = FocusSession(startedAt: Date(), duration: 60,
        pausedRemaining: 30)
      let decoded = try JSONDecoder.struktur.decode(Workspace.self, from: JSONEncoder.struktur.encode(workspace))
      try decoded.validate()
      store.replaceWorkspace(decoded)
      let record = try XCTUnwrap(store.savedFocusSessions().first)
      XCTAssertNil(record.notes)
      XCTAssertNil(record.title)
      XCTAssertEqual(store.focusRecordTitle(record), task.title)
      XCTAssertNil(store.workspace.focusSession?.title)
      XCTAssertNil(store.workspace.focusDraftTitle)
      XCTAssertEqual(store.scratchpad, "These notes belong to today")
    }
  }

  func testSessionTitleKeepsTaskNameAfterTaskChangesOrDeletion() throws {
    try withStore { store, _ in
      var task = TaskItem(title: "Original task")
      store.add(task)
      let now = Date()
      store.startFocus(minutes: 1, taskID: task.id, now: now)
      task.title = "Renamed task"
      store.update(task)
      store.finishFocus(now: now.addingTimeInterval(20))
      store.removeTask(id: task.id)
      let record = try XCTUnwrap(store.savedFocusSessions().first)
      XCTAssertEqual(store.focusRecordTitle(record), "Original task")
      XCTAssertEqual(record.taskID, task.id)
    }
  }

  func testEditingAndDeletingRecordOnlyChangesThatSessionAndRecalculatesGoal() throws {
    try withStore { store, url in
      let now = Date().startOfDay.addingTimeInterval(3600)
      let task = TaskItem(title: "Read")
      store.add(task)
      let goal = TrackedGoal(title: "Focus target", metric: .focusMinutes, taskIDs: [task.id])
      store.saveGoal(goal)
      store.updateScratchpad("Working notes")
      store.startFocus(minutes: 25, taskID: task.id, now: now)
      store.finishFocus(now: now.addingTimeInterval(120))
      let original = try XCTUnwrap(store.savedFocusSessions().first)
      store.startFocus(minutes: 25, now: now.addingTimeInterval(180))
      let active = store.workspace.focusSession
      store.updateFocusRecord(id: original.id, title: " Renamed session ", notes: "Edited saved notes")
      let edited = try XCTUnwrap(store.savedFocusSessions().first)
      XCTAssertEqual(edited.title, "Renamed session")
      XCTAssertEqual(edited.notes, "Edited saved notes")
      XCTAssertEqual(edited.seconds, original.seconds)
      XCTAssertEqual(edited.endedAt, original.endedAt)
      XCTAssertEqual(edited.taskID, original.taskID)
      XCTAssertEqual(store.progress(for: goal, on: now).amount, 2)
      XCTAssertEqual(store.scratchpad, "Working notes")
      store.removeFocusRecord(id: original.id)
      store.removeFocusRecord(id: original.id)
      store.updateFocusRecord(id: original.id, title: "Do not recreate", notes: "")
      XCTAssertTrue(store.savedFocusSessions().isEmpty)
      XCTAssertEqual(store.workspace.focusSession, active)
      XCTAssertEqual(store.progress(for: goal, on: now).amount, 0)
      XCTAssertEqual(store.scratchpad, "Working notes")
      let restored = WorkspaceStore(fileURL: url)
      XCTAssertTrue(restored.savedFocusSessions().isEmpty)
      XCTAssertNotNil(restored.workspace.focusSession)
      XCTAssertFalse(restored.tasks[0].isCompleted)
    }
  }

  func testAllSavedSessionsAreSearchableIncludingOlderNotes() {
    withStore { store, _ in
      var workspace = Workspace()
      workspace.focusHistory = (0..<24).map { index in
        FocusRecord(id: UUID(), endedAt: Date(timeIntervalSince1970: Double(index * 3600)),
          seconds: 60, completed: true, title: "Session \(index)",
          notes: index == 0 ? "Thesis café references" : "Some notes")
      }
      store.replaceWorkspace(workspace)
      XCTAssertEqual(store.savedFocusSessions().count, 24)
      XCTAssertEqual(store.savedFocusSessions().first?.title, "Session 23")
      XCTAssertEqual(store.savedFocusSessions().last?.title, "Session 0")
      XCTAssertEqual(store.savedFocusSessions(matching: "thesis").first?.title, "Session 0")
      XCTAssertEqual(store.savedFocusSessions(matching: " SESSION 23 ").count, 1)
      XCTAssertTrue(store.savedFocusSessions(matching: "missing").isEmpty)
    }
  }

  func testExportsPreserveSessionNotesAndScopeDraftTitles() throws {
    try withStore { store, url in
      let project = Project(name: "Writing", color: .mint)
      let task = TaskItem(title: "Write", projectID: project.id)
      store.add(project)
      store.add(task)
      let now = Date()
      store.updateFocusTitle("Writing session")
      store.updateScratchpad("Saved with writing")
      store.startFocus(minutes: 1, taskID: task.id, now: now)
      store.finishFocus(now: now.addingTimeInterval(15))
      store.updateFocusTitle("Private next session")
      let whole = try store.exportData()
      let scoped = try JSONDecoder.struktur.decode(Workspace.self, from: store.exportData(projectID: project.id))
      XCTAssertNil(scoped.focusDraftTitle)
      XCTAssertEqual(scoped.scratchpad, "")
      XCTAssertEqual(scoped.focusHistory?.first?.notes, "Saved with writing")
      let restored = WorkspaceStore(fileURL: url)
      try restored.importData(whole)
      XCTAssertEqual(restored.focusTitle, "Private next session")
      XCTAssertEqual(restored.savedFocusSessions().first?.title, "Writing session")
      XCTAssertEqual(restored.savedFocusSessions().first?.notes, "Saved with writing")
    }
  }

  func testCompactAndEmptyChecklistMarkersRenderAndToggle() throws {
    for source in ["- [] Test", "- [ ] Test", "  - []", "- [ ]", "\t- [X] Done"] {
      let item = try XCTUnwrap(MarkdownChecklist.item(in: source))
      let changed = MarkdownChecklist.toggling(line: 0, in: source)
      let toggled = try XCTUnwrap(MarkdownChecklist.item(in: changed))
      XCTAssertEqual(toggled.title, item.title)
      XCTAssertNotEqual(toggled.isChecked, item.isChecked)
    }
    XCTAssertNil(MarkdownChecklist.item(in: "- []inline"))
    XCTAssertNil(MarkdownChecklist.item(in: "Example - [] text"))
  }
}
