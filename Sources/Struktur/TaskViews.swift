import SwiftUI

enum TaskFilter: String, CaseIterable, Identifiable {
  case today, upcoming, open, completed
  var id: String { rawValue }
  var title: String { rawValue.capitalized }
}

struct TasksPage: View {
  @EnvironmentObject private var store: WorkspaceStore
  @State private var filter: TaskFilter = .today
  @State private var searchText = ""
  @State private var editingTask: TaskItem?
  @State private var showingNewTask = false

  private var filteredTasks: [TaskItem] {
    let now = Date()
    let tomorrow = now.startOfDay.adding(days: 1)
    let candidates = filter == .today ? store.tasks(on: now) : store.tasks
    return candidates.filter { task in
      let matchesSearch =
        searchText.isEmpty || task.title.localizedCaseInsensitiveContains(searchText)
        || task.notes.localizedCaseInsensitiveContains(searchText)
      guard matchesSearch else { return false }
      switch filter {
      case .today:
        return true
      case .upcoming:
        return !task.isCompleted
          && [task.dueDate, task.plannedStart].compactMap { $0 }.contains {
            $0 >= tomorrow
          }
      case .open:
        return !task.isCompleted
      case .completed:
        return task.isCompleted
      }
    }
    .sorted {
      ($0.dueDate ?? $0.plannedStart ?? .distantFuture)
        < ($1.dueDate ?? $1.plannedStart ?? .distantFuture)
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .bottom) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Tasks").font(.strukturSerif(30, weight: .semibold))
          EditableWording(.tasksSubtitle).font(.caption).foregroundStyle(
            .secondary)
        }
        Spacer()
        StrukturOptions(label: "Filter", selection: $filter, options: TaskFilter.allCases) {
          $0.title
        }
        .frame(width: 300)
        Button {
          showingNewTask = true
        } label: {
          Label("Add task", systemImage: "plus")
        }
        .buttonStyle(StrukturButtonStyle(primary: true))
      }
      .padding(24)

      Divider()

      HStack(spacing: 0) {
        VStack(spacing: 0) {
          HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search tasks", text: $searchText).textFieldStyle(.plain)
          }
          .padding(10)
          .background(StrukturTheme.hairline, in: RoundedRectangle(cornerRadius: 10))
          .padding(18)

          if filteredTasks.isEmpty {
            EmptyState(
              icon: "checkmark.circle", title: "No matching tasks",
              message: "No tasks match this view.")
          } else {
            ScrollView {
              LazyVStack(spacing: 8) {
                ForEach(filteredTasks) { task in
                  TaskRow(task: task)
                    .onTapGesture { editingTask = task }
                    .contextMenu {
                      Button("Edit") { editingTask = task }
                      Button(role: .destructive) {
                        store.removeTask(id: task.id)
                      } label: {
                        Label("Delete", systemImage: "trash").foregroundStyle(
                          StrukturTheme.destructive)
                      }
                    }
                }
              }
              .padding(.horizontal, 18).padding(.bottom, 24)
            }
          }
        }
        .frame(maxWidth: .infinity)

        Divider()

        TaskOverviewPanel(tasks: filteredTasks)
          .frame(width: 280)
      }
    }
    .sheet(isPresented: $showingNewTask) { TaskEditorSheet() }
    .sheet(item: $editingTask) { TaskEditorSheet(task: $0) }
  }
}

struct TaskRow: View {
  @EnvironmentObject private var store: WorkspaceStore
  let task: TaskItem
  var compact = false
  @State private var accessibleEditor = false

  var body: some View {
    HStack(spacing: 12) {
      Button {
        withAnimation(.snappy) { store.toggleTask(task.id) }
      } label: {
        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
          .font(.system(size: compact ? 16 : 19))
          .foregroundStyle(task.isCompleted ? task.color.color : .secondary)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(task.isCompleted ? "Reopen \(task.title)" : "Complete \(task.title)")

      VStack(alignment: .leading, spacing: compact ? 2 : 5) {
        Text((try? AttributedString(markdown: task.title)) ?? AttributedString(task.title))
          .font(compact ? .callout : .body.weight(.medium))
          .strikethrough(task.isCompleted)
          .foregroundStyle(task.isCompleted ? .secondary : .primary)
        HStack(spacing: 7) {
          if let project = store.project(task.projectID) {
            HStack(spacing: 4) {
              SuitIcon(symbol: project.symbol, color: project.color, size: 9)
              Text(project.name)
            }
          }
          if let due = task.dueDate {
            Label(dueLabel(due), systemImage: "calendar")
              .foregroundStyle(isOverdue(due) ? Color.red : Color.secondary)
          } else if task.cadence == .openEnded {
            Label("No deadline", systemImage: "infinity")
          }
          if !compact, let estimate = task.estimateMinutes {
            Label("\(estimate)m", systemImage: "clock")
          }
        }
        .font(.caption2).foregroundStyle(.secondary)
      }
      Spacer()
      if task.priority == .high {
        Image(systemName: "exclamationmark").font(.caption.bold()).foregroundStyle(
          AccentToken.rose.color)
      }
      if task.cadence != .once {
        Text(task.cadence == .openEnded ? "OPEN" : task.cadence.rawValue.uppercased())
          .font(.system(size: 8, weight: .bold, design: .rounded))
          .padding(.horizontal, 6).padding(.vertical, 3)
          .background(task.color.color.opacity(0.18), in: Capsule())
      }
    }
    .padding(compact ? 9 : 13)
    .background(
      compact ? Color.clear : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14)
    )
    .contentShape(Rectangle())
    .draggable("struktur-task:\(task.id.uuidString)")
    .accessibilityElement(children: .contain)
    .accessibilityAction(named: "Edit task") { accessibleEditor = true }
    .sheet(isPresented: $accessibleEditor) { TaskEditorSheet(task: task) }
  }

  private func dueLabel(_ date: Date) -> String {
    if Calendar.struktur.isDateInToday(date) {
      return "Today, " + date.formatted(.dateTime.hour().minute())
    }
    if Calendar.struktur.isDateInTomorrow(date) { return "Tomorrow" }
    return date.formatted(.dateTime.day().month(.abbreviated))
  }
  private func isOverdue(_ date: Date) -> Bool { !task.isCompleted && date < Date() }
}

struct TaskOverviewPanel: View {
  @EnvironmentObject private var store: WorkspaceStore
  let tasks: [TaskItem]

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      Text("At a glance").font(.strukturSerif(20, weight: .semibold))
      RingProgress(progress: completion, color: .mint, center: "\(Int(completion * 100))%")
        .frame(height: 145)
      VStack(spacing: 12) {
        metric("Open", value: store.tasks.filter { !$0.isCompleted }.count, color: .sky)
        metric(
          "Due today",
          value: store.tasks.filter {
            !$0.isCompleted && ($0.dueDate.map(Calendar.struktur.isDateInToday) ?? false)
          }.count, color: .peach)
        metric("Completed", value: store.tasks.filter(\.isCompleted).count, color: .mint)
      }
      Spacer()
      Text("Tip: Schedule a task to make it appear directly on your calendar.")
        .font(.caption).foregroundStyle(.secondary)
        .padding(12).background(
          AccentToken.butter.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
    }
    .padding(22)
  }

  private var completion: Double {
    guard !store.tasks.isEmpty else { return 0 }
    return Double(store.tasks.filter(\.isCompleted).count) / Double(store.tasks.count)
  }
  private func metric(_ title: String, value: Int, color: AccentToken) -> some View {
    HStack {
      AccentDot(color: color)
      Text(title)
      Spacer()
      Text("\(value)").monospacedDigit().foregroundStyle(.secondary)
    }
    .font(.callout)
  }
}

struct RingProgress: View {
  let progress: Double
  let color: AccentToken
  var center: String
  var body: some View {
    ZStack {
      Circle().stroke(StrukturTheme.hairline, lineWidth: 11)
      Circle().trim(from: 0, to: min(1, max(0, progress)))
        .stroke(color.color, style: StrokeStyle(lineWidth: 11, lineCap: .round))
        .rotationEffect(.degrees(-90))
      Text(center).font(.strukturSerif(22, weight: .semibold)).monospacedDigit()
    }
    .padding(8)
  }
}

struct TaskEditorSheet: View {
  @EnvironmentObject private var store: WorkspaceStore
  @Environment(\.dismiss) private var dismiss
  @State private var draft: TaskItem
  @State private var hasDueDate: Bool
  @State private var hasPlannedStart: Bool
  @State private var hasEstimate: Bool
  @State private var showingPreview = false
  private let isNew: Bool

  private var linkableEntries: [CalendarEntry] {
    let around = draft.plannedStart ?? draft.dueDate ?? Date()
    var choices = store.calendarEntries(
      in: DateInterval(start: around.adding(days: -30), end: around.adding(days: 90)),
      projectID: draft.projectID)
    if let id = draft.linkedEventID, !choices.contains(where: { $0.id == id }),
      let linked = store.resolveEntry(id)
    {
      choices.insert(linked, at: 0)
    }
    return choices
  }

  init(task: TaskItem? = nil, projectID: UUID? = nil) {
    let value =
      task
      ?? TaskItem(title: "", dueDate: Date().setting(hour: 17), projectID: projectID, color: .sky)
    _draft = State(initialValue: value)
    _hasDueDate = State(initialValue: task?.dueDate != nil)
    _hasPlannedStart = State(initialValue: task?.plannedStart != nil)
    _hasEstimate = State(initialValue: value.estimateMinutes != nil)
    isNew = task == nil
  }

  var body: some View {
    VStack(spacing: 0) {
      SheetHeader(
        title: isNew ? "New task" : "Edit task",
        subtitle: "Set a deadline, schedule time, or add notes.")
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          TextField("What needs doing?", text: $draft.title)
            .font(.strukturSerif(26, weight: .medium)).textFieldStyle(.plain)
          HStack(spacing: 12) {
            StrukturMenuPicker(
              title: "Project", selection: $draft.projectID,
              options: [StrukturMenuOption(value: UUID?.none, title: "None")]
                + store.projects.map {
                  StrukturMenuOption(value: Optional($0.id), title: $0.name)
                })
            StrukturMenuPicker(
              title: "Priority", selection: $draft.priority,
              options: TaskPriority.allCases.map {
                StrukturMenuOption(value: $0, title: $0.title)
              })
            StrukturMenuPicker(
              title: "Rhythm", selection: $draft.cadence,
              options: TaskCadence.allCases.map {
                StrukturMenuOption(value: $0, title: $0.title)
              })
          }
          VStack(spacing: 12) {
            taskTimingRow(isOn: hasDueDate) {
              StrukturToggleRow("Deadline", isOn: $hasDueDate)
            } value: {
              StrukturDateField(
                "Deadline",
                selection: Binding(get: { draft.dueDate ?? Date() }, set: { draft.dueDate = $0 }),
                showsLabel: false, fillsWidth: true)
            }
            taskTimingRow(isOn: hasEstimate) {
              StrukturToggleRow(
                "Estimate duration",
                isOn: Binding(
                  get: { hasEstimate },
                  set: { enabled in
                    hasEstimate = enabled
                    draft.estimateMinutes = enabled ? (draft.estimateMinutes ?? 30) : nil
                  })
              )
              .disabled(hasPlannedStart)
            } value: {
              StrukturValueStepper(
                title: "Estimated duration",
                value: Binding(
                  get: { draft.estimateMinutes ?? 30 }, set: { draft.estimateMinutes = $0 }),
                range: 5...480, step: 5, valueText: { "\($0) min" })
            }
            taskTimingRow(isOn: hasPlannedStart) {
              StrukturToggleRow(
                "Place on calendar",
                isOn: Binding(
                  get: { hasPlannedStart },
                  set: { enabled in
                    hasPlannedStart = enabled
                    if enabled {
                      hasEstimate = true
                      draft.estimateMinutes = draft.estimateMinutes ?? 30
                    }
                  }))
            } value: {
              StrukturDateField(
                "Scheduled start",
                selection: Binding(
                  get: { draft.plannedStart ?? Date() }, set: { draft.plannedStart = $0 }),
                showsLabel: false, fillsWidth: true)
            }
          }

          StrukturMenuPicker(
            title: "Related calendar block", selection: $draft.linkedEventID,
            options: [StrukturMenuOption(value: UUID?.none, title: "No linked block")]
              + linkableEntries.map {
                StrukturMenuOption(
                  value: Optional($0.id),
                  title: $0.title + " · "
                    + $0.start.formatted(.dateTime.day().month(.abbreviated)))
              })
          .onChange(of: draft.linkedEventID) { _, id in
            if let id, let entry = store.resolveEntry(id), draft.projectID == nil {
              draft.projectID = entry.projectID
            }
          }
          .onChange(of: draft.projectID) { _, id in
            if let linked = draft.linkedEventID,
              let entry = store.resolveEntry(linked),
              id != nil && entry.projectID != id
            {
              draft.linkedEventID = nil
            }
          }

          MarkdownComposer(text: $draft.notes, showingPreview: $showingPreview)

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
          if !isNew { ItemReferenceRow(kind: "task", id: draft.id) }
        }
        .padding(24)
      }
      Divider()
      HStack {
        if !isNew {
          Button("Delete task", role: .destructive) {
            store.removeTask(id: draft.id)
            dismiss()
          }
          .buttonStyle(StrukturButtonStyle())
          .padding(.leading, 18)
        }
        SheetActions(canSave: !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        {
          draft.dueDate = hasDueDate ? (draft.dueDate ?? Date()) : nil
          draft.plannedStart = hasPlannedStart ? (draft.plannedStart ?? Date()) : nil
          isNew ? store.add(draft) : store.update(draft)
          dismiss()
        }
      }
    }
    .frame(width: 680, height: 650).background(StrukturTheme.canvas).tint(StrukturTheme.darkButton)
  }

  private func taskTimingRow<ToggleContent: View, ValueContent: View>(
    isOn: Bool, @ViewBuilder toggle: () -> ToggleContent,
    @ViewBuilder value: () -> ValueContent
  ) -> some View {
    HStack(alignment: .center, spacing: 12) {
      toggle().frame(maxWidth: .infinity)
      Group {
        if isOn {
          value()
        } else {
          Color.clear.frame(height: 40).accessibilityHidden(true)
        }
      }
      .frame(maxWidth: .infinity)
    }
  }
}

struct MarkdownComposer: View {
  @Binding var text: String
  @Binding var showingPreview: Bool
  var title = "Notes"
  var editorHeight: CGFloat = 160
  var showsLivePreview = true
  var showsHelp = true
  var editorLabel = "Notes editor"

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        if !title.isEmpty {
          Label(title, systemImage: "text.alignleft").font(.caption.weight(.semibold))
        }
        Spacer()
        StrukturOptions(label: "Mode", selection: $showingPreview, options: [false, true]) {
          $0 ? "Preview" : "Write"
        }.frame(width: 150)
      }
      Group {
        if showingPreview {
          ScrollView { MarkdownContent(text: $text).padding(12) }
        } else {
          GeometryReader { geometry in
            HStack(spacing: 0) {
              TextEditor(text: $text)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden).padding(8)
                .accessibilityLabel(editorLabel)
              if showsLivePreview && geometry.size.width >= 600 {
                Divider()
                ScrollView { MarkdownContent(text: $text).padding(12) }
                  .frame(maxWidth: .infinity)
              }
            }
          }
        }
      }
      .frame(height: editorHeight)
      .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
      if showsHelp {
        Text(verbatim: "Markdown: **bold**, # headings, - [ ] checkboxes, [title](URL).")
          .font(.caption2).foregroundStyle(StrukturTheme.muted)
        Text("In Preview, click a checkbox to update the note. Note checklists are separate from tasks.")
          .font(.caption2).foregroundStyle(StrukturTheme.muted)
      }
    }
  }

}

struct SheetHeader: View {
  let title: String
  let subtitle: String
  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.strukturSerif(23, weight: .semibold))
        Text(subtitle).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
    }.padding(20)
  }
}

struct SheetActions: View {
  @Environment(\.dismiss) private var dismiss
  let canSave: Bool
  let save: () -> Void
  var body: some View {
    HStack {
      Spacer()
      Button("Cancel") { dismiss() }.buttonStyle(StrukturButtonStyle()).keyboardShortcut(
        .cancelAction)
      Button("Save", action: save).buttonStyle(StrukturButtonStyle(primary: true)).disabled(
        !canSave
      )
      .keyboardShortcut(.defaultAction)
    }
    .padding(16)
  }
}

struct LabeledPicker<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content
  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title).font(.caption2).foregroundStyle(.secondary)
      content
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}
