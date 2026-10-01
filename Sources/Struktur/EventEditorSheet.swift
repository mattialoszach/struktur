import SwiftUI

struct EventEditorSheet: View {
  @EnvironmentObject private var store: WorkspaceStore
  @Environment(\.dismiss) private var dismiss
  @State private var draft: CalendarEntry
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
            StrukturMenuPicker(
              title: "Apply changes to", selection: $scope,
              options: CalendarEditScope.allCases.map {
                StrukturMenuOption(value: $0, title: $0.title)
              })
            Text(
              "Choose the scope before editing. Series changes keep individually edited exceptions."
            )
            .font(.caption).foregroundStyle(StrukturTheme.muted)
          }
          TextField("What is happening?", text: $draft.title)
            .font(.strukturSerif(26, weight: .medium)).textFieldStyle(.plain)
          HStack(spacing: 12) {
            StrukturMenuPicker(
              title: "Project", selection: $draft.projectID,
              options: [StrukturMenuOption(value: UUID?.none, title: "None")]
                + store.projects.map {
                  StrukturMenuOption(value: Optional($0.id), title: $0.name)
                })
            StrukturMenuPicker(
              title: "Label", selection: $draft.kind,
              options: ItemKind.allCases.map {
                StrukturMenuOption(value: $0, title: $0.title)
              })
          }
          StrukturToggleRow("All-day", isOn: $draft.isAllDay)
          HStack(alignment: .bottom, spacing: 18) {
            StrukturDateField(
              "Starts", selection: $draft.start,
              displayedComponents: draft.isAllDay ? .date : [.date, .hourAndMinute])
            StrukturDateField(
              "Ends", selection: $draft.end, minimumDate: draft.start,
              displayedComponents: draft.isAllDay ? .date : [.date, .hourAndMinute])
          }
          if original?.seriesID == nil || scope == .series {
            RecurrenceControls(rule: $draft.recurrence, start: draft.start)
          } else {
            Label("Part of a repeating series", systemImage: "repeat").font(.caption)
              .foregroundStyle(StrukturTheme.muted)
          }
          TextField("Location or link", text: $draft.location).strukturInput()
          MarkdownComposer(text: $draft.notes)
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
          }.buttonStyle(StrukturButtonStyle())
        }
        Spacer()
        Button("Cancel") { dismiss() }.buttonStyle(StrukturButtonStyle()).keyboardShortcut(
          .cancelAction)
        Button("Save") {
          isNew ? store.add(draft.savedCopy) : store.update(draft.savedCopy)
          dismiss()
        }
        .buttonStyle(StrukturButtonStyle(primary: true)).disabled(
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
      StrukturToggleRow("Repeat this block", isOn: enabled)
      if let current = rule {
        HStack(spacing: 10) {
          StrukturMenuPicker(
            title: "Repeats", selection: field(\.frequency),
            options: RepeatFrequency.allCases.map {
              StrukturMenuOption(value: $0, title: $0.title)
            })
          StrukturValueStepper(
            title: "Interval", value: field(\.interval), range: 1...52,
            valueText: { "Every \($0)" })
        }
        if current.frequency == .weekly {
          HStack(spacing: 5) {
            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { weekday in
              let selected =
                current.weekdays.isEmpty
                ? current.calendar.component(.weekday, from: start) == weekday
                : current.weekdays.contains(weekday)
              Button {
                var days = Set(
                  current.weekdays.isEmpty
                    ? [current.calendar.component(.weekday, from: start)] : current.weekdays)
                if selected { days.remove(weekday) } else { days.insert(weekday) }
                if !days.isEmpty { rule?.weekdays = days.sorted() }
              } label: {
                Text(current.calendar.shortWeekdaySymbols[weekday - 1])
                  .font(.system(size: 10, weight: .medium)).frame(maxWidth: .infinity)
                  .padding(.vertical, 7)
                  .foregroundStyle(selected ? StrukturTheme.ink : StrukturTheme.muted)
                  .background(
                    selected ? StrukturTheme.surface : .clear,
                    in: RoundedRectangle(cornerRadius: 7))
                  .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(StrukturTheme.hairline) }
              }
              .buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
            }
          }
        }
        StrukturMenuPicker(
          title: "Ends",
          selection: Binding(
            get: { current.count != nil ? "count" : (current.until != nil ? "date" : "never") },
            set: { value in
              rule?.count = value == "count" ? 12 : nil
              rule?.until = value == "date" ? start.adding(days: 90) : nil
            }),
          options: [
            StrukturMenuOption(value: "never", title: "Never"),
            StrukturMenuOption(value: "date", title: "On date"),
            StrukturMenuOption(value: "count", title: "After occurrences"),
          ])
        if current.until != nil {
          StrukturDateField(
            "Last day",
            selection: Binding(get: { rule?.until ?? start }, set: { rule?.until = $0 }),
            minimumDate: start.startOfDay, displayedComponents: .date)
        }
        if current.count != nil {
          StrukturValueStepper(
            title: "Occurrences",
            value: Binding(get: { rule?.count ?? 12 }, set: { rule?.count = $0 }),
            range: 1...1000, valueText: { "\($0) total" })
        }
        Text(
          "Keeps local time in \(current.timeZoneIdentifier), including daylight-saving changes."
        )
        .font(.caption).foregroundStyle(StrukturTheme.muted)
      }
    }.padding(14).background(StrukturTheme.mint, in: RoundedRectangle(cornerRadius: 12))
      .onChange(of: start) { _, value in
        if let until = rule?.until {
          rule?.until = DateFieldValue.clamped(until, minimumDate: value.startOfDay)
        }
      }
  }
}
