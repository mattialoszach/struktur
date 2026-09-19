import SwiftUI

struct GoalsPage: View {
  @EnvironmentObject private var store: WorkspaceStore
  @State private var newGoal = false
  @State private var editing: TrackedGoal?
  @State private var date = Date()

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        HStack(alignment: .bottom) {
          VStack(alignment: .leading, spacing: 8) {
            Eyebrow(wording: .goalsEyebrow)
            EditableWording(.goalsTitle).font(.strukturSerif(32))
            EditableWording(.goalsSubtitle)
              .font(.callout).foregroundStyle(StrukturTheme.muted)
          }
          Spacer()
          Button("New goal", systemImage: "plus") { newGoal = true }
            .buttonStyle(StrukturButtonStyle(primary: true))
        }
        HStack(alignment: .bottom) {
          StrukturDateField("View progress for", selection: $date, displayedComponents: .date)
          Button("Today") { date = Date() }.buttonStyle(StrukturButtonStyle())
          Spacer()
        }
        if store.goals.isEmpty {
          EmptyState(
            icon: "scope", title: "No goals yet",
            message:
              "Set a daily, weekly, or ongoing target, then choose which tasks or spaces count toward it."
          )
        }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
          ForEach(store.goals) { goal in
            Button {
              editing = goal
            } label: {
              GoalProgressCard(goal: goal, date: date).frame(minHeight: 175)
            }.buttonStyle(.plain).strukturCard()
              .accessibilityLabel("Edit goal \(goal.title)")
          }
        }
      }.padding(30)
    }
    .sheet(isPresented: $newGoal) { GoalEditorSheet() }
    .sheet(item: $editing) { GoalEditorSheet(goal: $0) }
  }
}

struct GoalProgressCard: View {
  @EnvironmentObject private var store: WorkspaceStore
  let goal: TrackedGoal
  let date: Date
  var body: some View {
    let progress = store.progress(for: goal, on: date)
    VStack(alignment: .leading, spacing: 13) {
      HStack {
        SuitIcon(symbol: goal.symbol, color: goal.color, size: 20)
        Text(goal.period.title.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1)
          .foregroundStyle(StrukturTheme.muted)
        Spacer()
        if progress.achieved {
          Label("Reached", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(
            StrukturTheme.ink)
        }
      }
      Text(goal.title).font(.strukturSerif(23)).fixedSize(horizontal: false, vertical: true)
      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          Capsule().fill(StrukturTheme.hairline)
          Capsule().fill(goal.color.color).frame(width: geometry.size.width * progress.fraction)
        }
      }.frame(height: 6)
        .accessibilityLabel(goal.title).accessibilityValue(
          "\(Int(progress.amount)) of \(goal.target)")
      HStack(alignment: .firstTextBaseline) {
        Text("\(Int(progress.amount))").font(.strukturSerif(26)).monospacedDigit()
        Text("/ \(goal.target) \(goal.metric == .completedTasks ? "tasks" : "minutes")")
          .font(.caption).foregroundStyle(StrukturTheme.muted)
        Spacer()
      }
      if let end = progress.periodEnd {
        Text(
          "Period ends "
            + end.addingTimeInterval(-1).formatted(
              .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
        )
        .font(.caption2).foregroundStyle(StrukturTheme.muted)
      } else {
        Text("Ongoing target · does not reset").font(.caption2).foregroundStyle(
          StrukturTheme.muted)
      }
    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
  }
}

struct GoalTrackerWidget: View {
  @EnvironmentObject private var store: WorkspaceStore
  let configuration: WidgetConfiguration
  let date: Date
  var expanded = false
  @State private var newGoal = false
  @State private var editing: TrackedGoal?
  @State private var editingTask: TaskItem?
  private var selected: TrackedGoal? {
    configuration.goalID.flatMap { id in store.goals.first { $0.id == id } } ?? store.goals.first
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        if let goal = selected {
          HStack {
            Menu(goal.title) {
              ForEach(store.goals) { goal in Button(goal.title) { pin(goal.id) } }
              Divider()
              Button("New goal") { newGoal = true }
            }.menuStyle(.borderlessButton).accessibilityLabel("Choose tracked goal")
            Spacer()
            IconButton(icon: "pencil", label: "Edit tracked goal") { editing = goal }
          }
          GoalProgressCard(goal: goal, date: date)
          if expanded {
            Divider().padding(.vertical, 8)
            Eyebrow(text: "Linked tasks")
            ForEach(store.tasks(for: goal)) { task in
              TaskRow(task: task).onTapGesture { editingTask = task }
            }
          }
        } else {
          Text("No goal selected").font(.strukturSerif(21))
          Button("Create a goal", systemImage: "plus") { newGoal = true }
            .buttonStyle(StrukturButtonStyle(compact: true))
        }
      }.padding(17)
    }
    .sheet(isPresented: $newGoal) { GoalEditorSheet(onSave: { pin($0.id) }) }
    .sheet(item: $editing) { GoalEditorSheet(goal: $0) }
    .sheet(item: $editingTask) { TaskEditorSheet(task: $0) }
  }
  private func pin(_ id: UUID) {
    var widgets = store.widgets
    if let index = widgets.firstIndex(where: { $0.id == configuration.id }) {
      widgets[index].goalID = id
      store.setWidgets(widgets)
    }
  }
}

struct GoalEditorSheet: View {
  @EnvironmentObject private var store: WorkspaceStore
  @Environment(\.dismiss) private var dismiss
  @State private var draft: TrackedGoal
  @State private var query = ""
  @State private var reference = ""
  @State private var referenceError: String?
  @State private var confirmingDelete = false
  private let isNew: Bool
  var onSave: (TrackedGoal) -> Void

  init(goal: TrackedGoal? = nil, onSave: @escaping (TrackedGoal) -> Void = { _ in }) {
    _draft = State(initialValue: goal ?? TrackedGoal(title: ""))
    isNew = goal == nil
    self.onSave = onSave
  }

  var body: some View {
    VStack(spacing: 0) {
      SheetHeader(
        title: isNew ? "New goal" : "Edit goal",
        subtitle: "Measure completed tasks or recorded focus time.")
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          TextField("What are you working toward?", text: $draft.title)
            .font(.strukturSerif(25)).textFieldStyle(.plain)
          TextField("Description", text: $draft.detail, axis: .vertical).strukturInput()
          HStack(spacing: 12) {
            StrukturMenuPicker(
              title: "Period", selection: $draft.period,
              options: GoalPeriod.allCases.map {
                StrukturMenuOption(value: $0, title: $0.title)
              })
            StrukturMenuPicker(
              title: "Measure", selection: $draft.metric,
              options: GoalMetric.allCases.map {
                StrukturMenuOption(value: $0, title: $0.title)
              })
          }
          HStack {
            Text("Target").font(.callout)
            TextField("Goal target", value: $draft.target, format: .number)
              .multilineTextAlignment(.center).strukturInput(compact: true).frame(width: 90)
            IconButton(icon: "minus", label: "Decrease target") {
              draft.target = max(1, draft.target - 1)
            }
            IconButton(icon: "plus", label: "Increase target") {
              draft.target = min(100_000, draft.target + 1)
            }
            Text(draft.metric == .completedTasks ? "tasks" : "minutes").font(.caption)
              .foregroundStyle(StrukturTheme.muted)
            Spacer()
          }
          Divider()
          Eyebrow(text: "Connect the work")
          Text(
            "Select tasks or whole spaces. Linked recurring tasks include future occurrences. Focus goals count sessions assigned to these tasks."
          )
          .font(.caption).foregroundStyle(StrukturTheme.muted)
          HStack {
            TextField("Paste a task/space UID or struktur:// link", text: $reference)
              .strukturInput()
            Button("Link") { addReference() }.buttonStyle(StrukturButtonStyle(compact: true))
              .disabled(reference.trimmingCharacters(in: .whitespaces).isEmpty)
          }
          if let referenceError { Text(referenceError).font(.caption).foregroundStyle(.red) }
          ForEach(store.projects) { project in
            StrukturToggleRow(
              isOn: membership(project.id, in: \.projectIDs), accessibilityTitle: project.name
            ) {
              Label(project.name, systemImage: project.symbol.icon)
            }
          }
          TextField("Filter tasks", text: $query).strukturInput()
          LazyVStack(alignment: .leading, spacing: 9) {
            ForEach(
              store.tasks.filter {
                query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
                  || $0.id.uuidString.localizedCaseInsensitiveContains(query)
              }
            ) { task in
              StrukturToggleRow(
                isOn: membership(task.id, in: \.taskIDs), accessibilityTitle: "Track \(task.title)"
              ) {
                VStack(alignment: .leading, spacing: 2) {
                  Text(task.title).fixedSize(horizontal: false, vertical: true)
                  Text(
                    String(task.id.uuidString.prefix(8)) + " · "
                      + (store.project(task.projectID)?.name ?? "Personal")
                  )
                  .font(.caption2).foregroundStyle(StrukturTheme.muted)
                }
              }
            }
          }
          Text("\(draft.taskIDs.count) task references · \(draft.projectIDs.count) spaces")
            .font(.caption).foregroundStyle(StrukturTheme.muted)
          HStack {
            ForEach(SuitSymbol.allCases) { symbol in
              Button {
                draft.symbol = symbol
              } label: {
                SuitIcon(symbol: symbol, color: draft.color, size: 24).padding(8)
                  .background(
                    draft.symbol == symbol ? StrukturTheme.hairline : .clear,
                    in: RoundedRectangle(cornerRadius: 8))
              }.buttonStyle(.plain).accessibilityLabel("Use \(symbol.title) symbol")
            }
            Spacer()
            StrukturMenuPicker(
              title: "Color", selection: $draft.color,
              options: AccentToken.allCases.map {
                StrukturMenuOption(value: $0, title: $0.name)
              }).frame(width: 190)
          }
          if !isNew {
            GoalProgressCard(goal: draft, date: Date())
            ItemReferenceRow(kind: "goal", id: draft.id)
          }
        }.padding(24)
      }
      Divider()
      HStack {
        if !isNew {
          Button("Delete goal", role: .destructive) { confirmingDelete = true }
            .buttonStyle(StrukturButtonStyle())
        }
        Spacer()
        Button("Cancel") { dismiss() }.buttonStyle(StrukturButtonStyle()).keyboardShortcut(
          .cancelAction)
        Button("Save goal") {
          store.saveGoal(draft)
          onSave(draft)
          dismiss()
        }
        .buttonStyle(StrukturButtonStyle(primary: true)).keyboardShortcut(.defaultAction)
        .disabled(
          draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(1...100_000).contains(draft.target)
            || (draft.taskIDs.isEmpty && draft.projectIDs.isEmpty))
      }.padding(18)
    }.frame(width: 680, height: 680).background(StrukturTheme.canvas).tint(StrukturTheme.darkButton)
      .confirmationDialog(
        "Delete this goal? Linked tasks and spaces will stay.", isPresented: $confirmingDelete
      ) {
        Button("Delete goal", role: .destructive) {
          store.removeGoal(draft.id)
          dismiss()
        }
      }
  }

  private func membership(_ id: UUID, in key: WritableKeyPath<TrackedGoal, [UUID]>) -> Binding<Bool>
  {
    Binding(
      get: { draft[keyPath: key].contains(id) },
      set: { selected in
        draft[keyPath: key].removeAll { $0 == id }
        if selected { draft[keyPath: key].append(id) }
      })
  }
  private func addReference() {
    let value = reference.trimmingCharacters(in: .whitespacesAndNewlines)
    let id =
      UUID(uuidString: value)
      ?? URL(string: value).flatMap { UUID(uuidString: $0.lastPathComponent) }
    guard let id else {
      referenceError = "Use a complete UUID or a copied Struktur reference."
      return
    }
    if store.tasks.contains(where: { $0.id == id }) {
      if !draft.taskIDs.contains(id) { draft.taskIDs.append(id) }
    } else if store.project(id) != nil {
      if !draft.projectIDs.contains(id) { draft.projectIDs.append(id) }
    } else {
      referenceError = "No task or space with that ID exists in this workspace."
      return
    }
    reference = ""
    referenceError = nil
  }
}
