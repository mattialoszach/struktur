import SwiftUI

struct EventEditorSheet: View {
  @EnvironmentObject private var store: WorkspaceStore
  @Environment(\.dismiss) private var dismiss
  @State private var draft: CalendarEntry
  @State private var showingPreview = false
  @State private var editingTask: TaskItem?
  private let isNew: Bool

  init(entry: CalendarEntry? = nil, suggestedDate: Date = Date(), projectID: UUID? = nil) {
    let hour = Calendar.struktur.component(.hour, from: suggestedDate)
    let minute = Calendar.struktur.component(.minute, from: suggestedDate) / 15 * 15
    let start = suggestedDate.setting(
      hour: suggestedDate == suggestedDate.startOfDay ? 9 : hour, minute: minute)
    _draft = State(
      initialValue: entry?.editorCopy
        ?? CalendarEntry(
          title: "", start: start, end: start.addingTimeInterval(3600), projectID: projectID))
    isNew = entry == nil
  }

  var body: some View {
    VStack(spacing: 0) {
      SheetHeader(
        title: isNew ? "New calendar block" : "Edit calendar block",
        subtitle: "Protect the time before the day fills itself")
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          TextField("What is happening?", text: $draft.title)
            .font(.strukturSerif(26, weight: .medium)).textFieldStyle(.plain)
          HStack(spacing: 12) {
            LabeledPicker(title: "Project") {
              Picker("Project", selection: $draft.projectID) {
                Text("None").tag(UUID?.none)
                ForEach(store.projects) { Text($0.name).tag(Optional($0.id)) }
              }.labelsHidden()
            }
            LabeledPicker(title: "Label") {
              Picker("Label", selection: $draft.kind) {
                ForEach(ItemKind.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
              }.labelsHidden()
            }
          }
          Toggle("All-day", isOn: $draft.isAllDay)
          HStack {
            DatePicker(
              "Starts", selection: $draft.start,
              displayedComponents: draft.isAllDay ? .date : [.date, .hourAndMinute])
            DatePicker(
              "Ends", selection: $draft.end, in: draft.start...,
              displayedComponents: draft.isAllDay ? .date : [.date, .hourAndMinute])
          }
          TextField("Location or link", text: $draft.location)
          MarkdownComposer(text: $draft.notes, showingPreview: $showingPreview)
          if !isNew {
            let linked = store.tasks.filter { $0.linkedEventID == draft.id }
            if !linked.isEmpty {
              VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Connected next steps")
                ForEach(linked) { task in
                  TaskRow(task: task, compact: true).onTapGesture { editingTask = task }
                }
              }
            }
            ItemReferenceRow(kind: "event", id: draft.id)
          }
          HStack(spacing: 10) {
            Text("Color").font(.caption).foregroundStyle(.secondary)
            ForEach(AccentToken.allCases) { token in
              Button {
                draft.color = token
              } label: {
                Circle().fill(token.color).frame(width: 19, height: 19)
                  .overlay {
                    if draft.color == token {
                      Circle().stroke(Color.primary, lineWidth: 2).padding(-3)
                    }
                  }
              }.buttonStyle(.plain).accessibilityLabel("Use \(token.name) color")
            }
          }
        }.padding(24)
      }
      Divider()
      HStack {
        if !isNew {
          Button("Delete", role: .destructive) {
            store.removeEntry(id: draft.id)
            dismiss()
          }
        }
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Save") {
          isNew ? store.add(draft.savedCopy) : store.update(draft.savedCopy)
          dismiss()
        }
        .buttonStyle(.borderedProminent).disabled(
          draft.title.trimmingCharacters(in: .whitespaces).isEmpty
            || (draft.isAllDay ? draft.end < draft.start : draft.end <= draft.start)
        ).keyboardShortcut(.defaultAction)
      }.padding(16)
    }
    .frame(width: 680, height: 680).background(StrukturTheme.canvas)
    .sheet(item: $editingTask) { TaskEditorSheet(task: $0) }
    .onChange(of: draft.start) { old, value in
      if draft.isAllDay {
        if draft.end < value { draft.end = value }
      } else if draft.end <= value {
        draft.end = value.addingTimeInterval(max(900, draft.end.timeIntervalSince(old)))
      }
    }
    .onChange(of: draft.isAllDay) { _, value in
      if value {
        draft.start = draft.start.startOfDay
        draft.end = max(draft.start, draft.end.addingTimeInterval(-1).startOfDay)
      } else if draft.end <= draft.start {
        draft.end = draft.start.addingTimeInterval(3600)
      }
    }
  }
}
