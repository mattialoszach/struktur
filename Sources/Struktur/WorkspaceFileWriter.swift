import Foundation

/// One serial writer orders autosaves, explicit saves, and import backups.
/// Only immutable value snapshots cross threads; all store/UI state stays on main.
final class WorkspaceFileWriter: Sendable {
  struct Snapshot: Sendable {
    let workspace: Workspace
    let url: URL
    let migrationBackup: URL?
  }

  private let queue = DispatchQueue(label: "app.struktur.workspace-writer", qos: .utility)
  private let encode: @Sendable (Workspace) throws -> Data

  init(
    encode: @escaping @Sendable (Workspace) throws -> Data = { try JSONEncoder.struktur.encode($0) }
  ) {
    self.encode = encode
  }

  func save(_ snapshot: Snapshot) async -> String? {
    await withCheckedContinuation { continuation in
      queue.async { continuation.resume(returning: self.write(snapshot)) }
    }
  }

  // Navigation/termination can explicitly flush before the process/view closes.
  // Waiting on the same queue prevents an older autosave overwriting this save.
  func saveNow(_ snapshot: Snapshot) -> String? {
    queue.sync { write(snapshot) }
  }

  func backupForImport(_ url: URL) throws {
    try queue.sync {
      if FileManager.default.fileExists(atPath: url.path) {
        let backup = url.deletingLastPathComponent().appending(
          path: "workspace-backup-\(UUID().uuidString).json")
        try FileManager.default.copyItem(at: url, to: backup)
      }
    }
  }

  private func write(_ snapshot: Snapshot) -> String? {
    do {
      if let backup = snapshot.migrationBackup,
        !FileManager.default.fileExists(atPath: backup.path)
      {
        try FileManager.default.copyItem(at: snapshot.url, to: backup)
      }
      let data = try encode(snapshot.workspace)
      try FileManager.default.createDirectory(
        at: snapshot.url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: snapshot.url, options: .atomic)
      return nil
    } catch {
      return error.localizedDescription
    }
  }
}
