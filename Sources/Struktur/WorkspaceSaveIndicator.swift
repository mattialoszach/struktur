import SwiftUI

/// Saving status belongs to this label, not the entire workspace view tree.
struct WorkspaceSaveIndicator: View {
  @ObservedObject var status: WorkspaceSaveStatus
  var failed: Bool
  var savedText = "Saved locally"

  var body: some View {
    Text(failed ? "Could not save" : status.isPending ? "Saving…" : savedText)
  }
}
