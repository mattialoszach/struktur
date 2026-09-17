import SwiftUI

struct EventEditorSheet: View {
  @EnvironmentObject private var store: WorkspaceStore
  @Environment(\.dismiss) private var dismiss
  @State private var draft: CalendarEntry
  @State private var showingPreview = false
  @State private var editingTask: TaskItem?
  @State private var scope: CalendarEditScope = .occurrence
  @State private var confirmingDelete = false
  private let original: CalendarEntry?
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
    original = entry
  }

  var body: some View {
    VStack(spacing: 0) {
      SheetHeader(
        title: isNew ? "New calendar block" : "Edit calendar block",
        subtitle: "Set the start and end time for this block.")
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          if original?.seriesID != nil {
            Picker("Apply changes to", selection: $scope) {
              ForEach(CalendarEditScope.allCases) { Text($0.title).tag($0) }
            }
            Text(
              "Choose the scope before editing. Series changes keep individually edited exceptions."
            )
            .font(.caption).foregroundStyle(StrukturTheme.muted)
          }
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
          if original?.seriesID == nil || scope == .series {
            RecurrenceControls(rule: $draft.recurrence, start: draft.start)
          } else {
            Label("Part of a repeating series", systemImage: "repeat").font(.caption)
              .foregroundStyle(StrukturTheme.muted)
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
            confirmingDelete = true
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
            || (draft.recurrence?.until.map { $0 < draft.start.startOfDay } ?? false)
        ).keyboardShortcut(.defaultAction)
      }.padding(16)
    }
    .frame(width: 680, height: 680).background(StrukturTheme.canvas).tint(StrukturTheme.darkButton)
    .sheet(item: $editingTask) { TaskEditorSheet(task: $0) }
    .confirmationDialog(
      draft.recurrence != nil
        ? "Delete the entire series and its exceptions?" : "Delete this calendar block?",
      isPresented: $confirmingDelete
    ) {
      Button(draft.recurrence != nil ? "Delete entire series" : "Delete block", role: .destructive)
      {
        if draft.seriesID != nil {
          store.deleteOccurrence(draft)
        } else {
          store.removeEntry(id: draft.id)
        }
        dismiss()
      }
    }
    .onChange(of: scope) { _, value in
      if value == .series, let id = original?.seriesID,
        let master = store.entries.first(where: { $0.id == id })
      {
        draft = master.editorCopy
      } else if let original {
        draft = original.editorCopy
      }
    }
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

struct RecurrenceControls: View {
  @Binding var rule: CalendarRecurrence?
  let start: Date
  private var enabled: Binding<Bool> {
    Binding(get: { rule != nil }, set: { rule = $0 ? CalendarRecurrence() : nil })
  }
  private func field<Value>(_ key: WritableKeyPath<CalendarRecurrence, Value>) -> Binding<Value> {
    Binding(
      get: { (rule ?? CalendarRecurrence())[keyPath: key] },
      set: { value in
        var copy = rule ?? CalendarRecurrence()
        copy[keyPath: key] = value
        rule = copy
      })
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Toggle("Repeat this block", isOn: enabled)
      if let current = rule {
        HStack {
          Picker("Repeats", selection: field(\.frequency)) {
            ForEach(RepeatFrequency.allCases) { Text($0.title).tag($0) }
          }
          Stepper("Every \(current.interval)", value: field(\.interval), in: 1...52)
        }
        if current.frequency == .weekly {
          HStack {
            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { weekday in
              let selected =
                current.weekdays.isEmpty
                ? current.calendar.component(.weekday, from: start) == weekday
                : current.weekdays.contains(weekday)
              Toggle(
                current.calendar.shortWeekdaySymbols[weekday - 1],
                isOn: Binding(
                  get: { selected },
                  set: { value in
                    var days = Set(
                      current.weekdays.isEmpty
                        ? [current.calendar.component(.weekday, from: start)] : current.weekdays)
                    if value { days.insert(weekday) } else { days.remove(weekday) }
                    if !days.isEmpty { rule?.weekdays = days.sorted() }
                  })
              ).toggleStyle(.button)
            }
          }
        }
        Picker(
          "Ends",
          selection: Binding(
            get: { current.count != nil ? "count" : (current.until != nil ? "date" : "never") },
            set: { value in
              rule?.count = value == "count" ? 12 : nil
              rule?.until = value == "date" ? start.adding(days: 90) : nil
            })
        ) {
          Text("Never").tag("never")
          Text("On date").tag("date")
          Text("After occurrences").tag("count")
        }
        if current.until != nil {
          DatePicker(
            "Last day",
            selection: Binding(get: { rule?.until ?? start }, set: { rule?.until = $0 }),
            in: start.startOfDay..., displayedComponents: .date)
        }
        if let count = current.count {
          Stepper(
            "\(count) occurrences",
            value: Binding(get: { rule?.count ?? 12 }, set: { rule?.count = $0 }), in: 1...1000)
        }
        Text(
          "Keeps local time in \(current.timeZoneIdentifier), including daylight-saving changes."
        )
        .font(.caption).foregroundStyle(StrukturTheme.muted)
      }
    }.padding(14).background(StrukturTheme.mint, in: RoundedRectangle(cornerRadius: 12))
  }
}
