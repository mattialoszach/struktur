import XCTest

@testable import Struktur

@MainActor
final class WorkspaceStoreTests: XCTestCase {
  func testWorkspaceRoundTripPreservesContent() throws {
    let workspace = WorkspaceStore.sampleWorkspace(now: Date(timeIntervalSince1970: 1_700_000_000))
    let encoded = try JSONEncoder.struktur.encode(workspace)
    let decoded = try JSONDecoder.struktur.decode(Workspace.self, from: encoded)
    XCTAssertEqual(decoded.projects, workspace.projects)
    XCTAssertEqual(decoded.calendarEntries.map(\.id), workspace.calendarEntries.map(\.id))
    XCTAssertEqual(decoded.tasks.map(\.title), workspace.tasks.map(\.title))
    XCTAssertEqual(decoded.preferences, workspace.preferences)
    XCTAssertEqual(decoded.scratchpad, workspace.scratchpad)
    XCTAssertEqual(
      decoded.tasks[0].createdAt.timeIntervalSince(workspace.tasks[0].createdAt), 0, accuracy: 1)
  }

  func testTaskCompletionIsPersisted() throws {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "struktur-tests-\(UUID().uuidString)")
      .appending(path: "workspace.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let store = WorkspaceStore(fileURL: url)
    let task = TaskItem(title: "Test the important path")
    store.add(task)
    store.toggleTask(task.id)

    let restored = WorkspaceStore(fileURL: url)
    XCTAssertEqual(restored.tasks.first(where: { $0.id == task.id })?.isCompleted, true)
  }

  func testOptionalTaskEstimatePersistsAndScheduledTasksRequireDuration() throws {
    let withoutEstimate = TaskItem(title: "Someday")
    let withEstimate = TaskItem(title: "Timed", estimateMinutes: 45)
    let workspace = Workspace(tasks: [withoutEstimate, withEstimate])
    try workspace.validate()
    let restored = try JSONDecoder.struktur.decode(
      Workspace.self, from: JSONEncoder.struktur.encode(workspace))
    XCTAssertNil(restored.tasks[0].estimateMinutes)
    XCTAssertEqual(restored.tasks[1].estimateMinutes, 45)

    var invalid = workspace
    invalid.tasks[0].plannedStart = Date()
    XCTAssertThrowsError(try invalid.validate())
  }

  func testImportedWorkspaceReplacesCurrentData() throws {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "struktur-tests-\(UUID().uuidString)")
      .appending(path: "workspace.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let store = WorkspaceStore(fileURL: url)
    let project = Project(name: "A focused project", color: .mint)
    let imported = Workspace(projects: [project])
    try store.importData(JSONEncoder.struktur.encode(imported))

    XCTAssertEqual(store.projects, [project])
    XCTAssertTrue(store.tasks.isEmpty)
    XCTAssertTrue(store.entries.isEmpty)
  }

  func testCompletingRecurringTaskCreatesNextOccurrence() {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "struktur-tests-\(UUID().uuidString)")
      .appending(path: "workspace.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let store = WorkspaceStore(fileURL: url)
    let due = Date().setting(hour: 18)
    let recurring = TaskItem(title: "Daily reset", dueDate: due, cadence: .daily)
    store.add(recurring)
    store.toggleTask(recurring.id)

    let next = store.tasks.first { !$0.isCompleted && $0.title == recurring.title }
    XCTAssertNotNil(next)
    XCTAssertEqual(next?.dueDate, due.adding(days: 1))
  }
}
