import XCTest

@testable import Struktur

@MainActor
final class WordingTests: XCTestCase {
  private func withStore(_ body: (WorkspaceStore, URL) throws -> Void) rethrows {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "struktur-wording-tests-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "workspace.json")
    let store = WorkspaceStore(fileURL: url)
    store.replaceWorkspace(Workspace())
    try body(store, url)
  }

  func testLegacyPreferencesUseDefaultWordingAndPreserveChoices() throws {
    let preferences = try JSONDecoder.struktur.decode(
      UserPreferences.self,
      from: Data(#"{"appearance":"dark","displayName":"Alex","showWeekends":false}"#.utf8))
    XCTAssertNil(preferences.wordingOverrides)
    withStore { store, _ in
      store.updatePreferences { $0 = preferences }
      for key in WordingKey.allCases {
        XCTAssertEqual(store.wording(key), key.defaultValue)
      }
      store.setWording("My desk", for: .dashboardTitle)
      XCTAssertEqual(store.preferences.appearance, .dark)
      XCTAssertEqual(store.preferences.displayName, "Alex")
      XCTAssertFalse(store.preferences.showWeekends)
    }
  }

  func testWordingSurvivesRelaunchAndExportImportWithoutChangingWorkspaceContent() throws {
    try withStore { store, url in
      store.replaceWorkspace(WorkspaceStore.sampleWorkspace())
      let original = store.workspace
      // The existing JSON date format rounds subsecond timestamps on disk.
      let persistedOriginal = WorkspaceStore(fileURL: url).workspace
      store.setWording("Alex’s desk ☕️", for: .dashboardTitle)
      store.setWording("Read, write, repeat.", for: .dashboardFooter)
      let restored = WorkspaceStore(fileURL: url)
      XCTAssertNil(restored.lastSaveError)
      XCTAssertEqual(restored.wording(.dashboardTitle), "Alex’s desk ☕️")
      XCTAssertEqual(restored.wording(.dashboardFooter), "Read, write, repeat.")
      var expected = original
      expected.preferences.wordingOverrides = store.preferences.wordingOverrides
      XCTAssertEqual(store.workspace, expected)
      expected = persistedOriginal
      expected.preferences.wordingOverrides = store.preferences.wordingOverrides
      XCTAssertEqual(restored.workspace, expected)

      let exported = try store.exportData()
      restored.setWording("Temporary", for: .dashboardTitle)
      try restored.importData(exported)
      XCTAssertEqual(restored.workspace, expected)
      XCTAssertEqual(WorkspaceStore(fileURL: url).workspace, expected)
    }
  }

  func testBlankAndDefaultTextResetOnlyTheChosenWording() {
    withStore { store, url in
      store.setWording("My desk", for: .dashboardTitle)
      store.setWording("Later", for: .tasksTitle)
      store.setWording(" \n\t\u{00A0} ", for: .dashboardTitle)
      XCTAssertEqual(store.wording(.dashboardTitle), WordingKey.dashboardTitle.defaultValue)
      XCTAssertNil(store.preferences.wordingOverrides?[WordingKey.dashboardTitle.rawValue])
      XCTAssertEqual(store.wording(.tasksTitle), "Later")
      store.setWording(WordingKey.tasksTitle.defaultValue, for: .tasksTitle)
      XCTAssertNil(store.preferences.wordingOverrides)
      XCTAssertNil(WorkspaceStore(fileURL: url).preferences.wordingOverrides)
    }
  }

  func testPastedAndImportedWordingIsBoundedWithoutSplittingUnicodeCharacters() throws {
    try withStore { store, _ in
      store.setWording("  Read\n\n and\t write  ", for: .focusTitle)
      XCTAssertEqual(store.wording(.focusTitle), "Read and write")
      let emoji = "👩🏽‍💻"
      let oversized = String(repeating: emoji, count: 200)
      store.setWording(oversized, for: .dashboardTitle)
      XCTAssertEqual(
        store.wording(.dashboardTitle),
        String(repeating: emoji, count: WordingKey.dashboardTitle.characterLimit))

      var imported = Workspace()
      imported.preferences.wordingOverrides = [
        "focusTitle": oversized, "tasksTitle": "\n\t", "futureKey": "Keep this",
      ]
      try store.importData(JSONEncoder.struktur.encode(imported))
      XCTAssertEqual(store.wording(.focusTitle).count, WordingKey.focusTitle.characterLimit)
      XCTAssertEqual(store.wording(.tasksTitle), WordingKey.tasksTitle.defaultValue)
      store.setWording("Notes for later", for: .notesTitle)
      XCTAssertEqual(store.preferences.wordingOverrides?["futureKey"], "Keep this")
    }
  }
}
