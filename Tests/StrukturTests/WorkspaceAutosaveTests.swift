import Combine
import Foundation
import Synchronization
import XCTest

@testable import Struktur

@MainActor final class WorkspaceAutosaveTests: XCTestCase {
  func testCleanNavigationFlushDoesNotWriteOrPublish() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let writes = Mutex(0)
    let writer = WorkspaceFileWriter {
      writes.withLock { $0 += 1 }
      return try JSONEncoder.struktur.encode($0)
    }
    let url = folder.appending(path: "workspace.json")
    let store = WorkspaceStore(fileURL: url, writer: writer)
    store.replaceWorkspace(Workspace())
    var notifications = 0
    let observer = store.objectWillChange.sink { notifications += 1 }
    defer { observer.cancel() }
    for _ in 0..<5 { store.saveNow() }
    XCTAssertEqual(writes.withLock { $0 }, 1)
    XCTAssertEqual(notifications, 0, "Navigation must not trigger a new workspace refresh")
    let reopened = WorkspaceStore(fileURL: url, writer: writer)
    reopened.saveNow()
    XCTAssertEqual(
      writes.withLock { $0 }, 1, "An already saved workspace needs no rewrite on leaving a page")
    store.updateScratchpad("Latest text")
    store.saveNow()
    XCTAssertEqual(writes.withLock { $0 }, 2)
    XCTAssertEqual(WorkspaceStore(fileURL: url).scratchpad, "Latest text")
  }

  private func waitForSave(_ store: WorkspaceStore) async throws {
    for _ in 0..<100 where store.isSavePending {
      try await Task.sleep(for: .milliseconds(20))
    }
    XCTAssertFalse(store.isSavePending)
  }

  func testAutosaveEncodesOffMainAndKeepsNewTypingPending() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let started = Mutex(false)
    let release = DispatchSemaphore(value: 0)
    defer { release.signal() }
    let writer = WorkspaceFileWriter { workspace in
      if workspace.scratchpad == "slow snapshot" {
        XCTAssertFalse(Thread.isMainThread)
        started.withLock { $0 = true }
        guard release.wait(timeout: .now() + 5) == .success else {
          throw CocoaError(.fileWriteUnknown)
        }
      }
      return try JSONEncoder.struktur.encode(workspace)
    }
    let url = folder.appending(path: "workspace.json")
    let store = WorkspaceStore(fileURL: url, writer: writer)
    store.replaceWorkspace(Workspace())
    store.updateScratchpad("slow snapshot")
    for _ in 0..<100 where !started.withLock({ $0 }) {
      try await Task.sleep(for: .milliseconds(20))
    }
    XCTAssertTrue(started.withLock { $0 })
    // The UI actor remains usable while encoding is deliberately blocked.
    store.updateScratchpad("new typing")
    XCTAssertEqual(store.scratchpad, "new typing")
    XCTAssertTrue(store.isSavePending)
    release.signal()
    try await Task.sleep(for: .milliseconds(60))
    XCTAssertTrue(store.isSavePending, "An old completion must not report new edits as saved")
    try await waitForSave(store)
    XCTAssertEqual(WorkspaceStore(fileURL: url).scratchpad, "new typing")
    XCTAssertNil(store.lastSaveError)
  }

  func testExplicitSaveAndImportCannotBeOverwrittenByOlderAutosave() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let started = Mutex(false)
    let release = DispatchSemaphore(value: 0)
    defer { release.signal() }
    let writer = WorkspaceFileWriter { workspace in
      if workspace.scratchpad == "old snapshot" {
        started.withLock { $0 = true }
        guard release.wait(timeout: .now() + 5) == .success else {
          throw CocoaError(.fileWriteUnknown)
        }
      }
      return try JSONEncoder.struktur.encode(workspace)
    }
    let url = folder.appending(path: "workspace.json")
    let store = WorkspaceStore(fileURL: url, writer: writer)
    store.replaceWorkspace(Workspace())
    store.updateScratchpad("old snapshot")
    for _ in 0..<100 where !started.withLock({ $0 }) {
      try await Task.sleep(for: .milliseconds(20))
    }
    XCTAssertTrue(started.withLock { $0 })
    store.updateScratchpad("flush on quit")
    release.signal()
    store.saveNow()
    XCTAssertEqual(WorkspaceStore(fileURL: url).scratchpad, "flush on quit")
    // Let the superseded completion reach the main actor after the explicit save.
    try await Task.sleep(for: .milliseconds(60))
    XCTAssertFalse(store.isSavePending)
    XCTAssertNil(store.lastSaveError)
    var imported = Workspace()
    imported.scratchpad = "imported"
    store.updateScratchpad("queued but canceled")
    try store.importData(JSONEncoder.struktur.encode(imported))
    try await Task.sleep(for: .milliseconds(450))
    XCTAssertEqual(WorkspaceStore(fileURL: url).scratchpad, "imported")
    let backups = try FileManager.default.contentsOfDirectory(
      at: folder, includingPropertiesForKeys: nil
    )
    .filter { $0.lastPathComponent.hasPrefix("workspace-backup-") }
    XCTAssertEqual(backups.count, 1)
    let previous = try JSONDecoder.struktur.decode(
      Workspace.self, from: Data(contentsOf: XCTUnwrap(backups.first)))
    XCTAssertEqual(previous.scratchpad, "flush on quit")
  }

  func testAutosaveFailureReportsErrorAndCanRetry() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appending(path: "workspace.json")
    let writer = WorkspaceFileWriter { workspace in
      if workspace.scratchpad == "fail" { throw CocoaError(.fileWriteOutOfSpace) }
      return try JSONEncoder.struktur.encode(workspace)
    }
    let store = WorkspaceStore(fileURL: url, writer: writer)
    store.replaceWorkspace(Workspace())
    let original = try Data(contentsOf: url)
    store.updateScratchpad("fail")
    try await waitForSave(store)
    XCTAssertNotNil(store.lastSaveError)
    XCTAssertEqual(try Data(contentsOf: url), original)
    store.updateScratchpad("retry")
    try await waitForSave(store)
    XCTAssertNil(store.lastSaveError)
    XCTAssertEqual(WorkspaceStore(fileURL: url).scratchpad, "retry")
  }

  func testAutosavePreservesMigrationBackupAndUnreadableFile() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appending(path: "workspace.json")
    var legacy = Workspace()
    legacy.schemaVersion = 1
    let original = try JSONEncoder.struktur.encode(legacy)
    try original.write(to: url)
    let store = WorkspaceStore(fileURL: url)
    store.updateScratchpad("migrated")
    try await waitForSave(store)
    store.updateScratchpad("second save")
    try await waitForSave(store)
    let backups = try FileManager.default.contentsOfDirectory(
      at: folder, includingPropertiesForKeys: nil
    )
    .filter { $0.lastPathComponent.hasPrefix("workspace-before-v3-") }
    XCTAssertEqual(backups.count, 1)
    XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), original)
    let unreadable = Data("unreadable".utf8)
    try unreadable.write(to: url)
    let recovered = WorkspaceStore(fileURL: url)
    recovered.updateScratchpad("must not overwrite")
    try await waitForSave(recovered)
    XCTAssertNotNil(recovered.lastSaveError)
    XCTAssertEqual(try Data(contentsOf: url), unreadable)
  }
}
