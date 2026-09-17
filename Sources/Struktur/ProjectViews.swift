import SwiftUI

struct ProjectsPage: View {
  @EnvironmentObject private var store: WorkspaceStore
  @Binding var selectedProjectID: UUID?
  @State private var editingProject: Project?
  @State private var showingNewProject = false
  @State private var showArchived = false
  private var visibleProjects: [Project] {
    showArchived ? store.workspace.projects.filter(\.isArchived) : store.projects
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .center) {
        VStack(alignment: .leading, spacing: 8) {
          Eyebrow(wording: .spacesEyebrow)
          EditableWording(.spacesTitle).font(.strukturSerif(35)).tracking(-1)
        }
        Spacer()
        StrukturOptions(label: "Spaces view", selection: $showArchived, options: [false, true]) {
          $0 ? "Archived" : "Active"
        }.frame(width: 172)
        Button {
          showingNewProject = true
        } label: {
          Label("New space", systemImage: "plus")
        }.buttonStyle(StrukturButtonStyle(primary: true))
      }.padding(30)
      ScrollView(.horizontal) {
        HStack(spacing: 12) {
          ForEach(visibleProjects) { project in
            Button {
              selectedProjectID = project.id
            } label: {
              HStack(spacing: 12) {
                SuitIcon(symbol: project.symbol, color: project.color, size: 28)
                VStack(alignment: .leading, spacing: 5) {
                  Text(project.name).font(.strukturSerif(18))
                  let count = store.tasks.filter { $0.projectID == project.id && !$0.isCompleted }
                    .count
                  Text(
                    "\(count) open \(count == 1 ? "task" : "tasks")"
                  ).font(.system(size: 10)).foregroundStyle(StrukturTheme.muted)
                }
                Spacer(minLength: 8)
              }.padding(17).frame(minWidth: 220)
                .background(
                  selectedProjectID == project.id
                    ? project.color.color.opacity(0.18) : StrukturTheme.surface,
                  in: RoundedRectangle(cornerRadius: 13)
                )
                .overlay {
                  RoundedRectangle(cornerRadius: 13).strokeBorder(
                    selectedProjectID == project.id ? project.color.color : StrukturTheme.hairline)
                }
            }.buttonStyle(.plain)
          }
        }.padding(.horizontal, 30).padding(.bottom, 20)
      }.scrollIndicators(.hidden).fixedSize(horizontal: false, vertical: true)
      Divider()
      if let project = visibleProjects.first(where: { $0.id == selectedProjectID }) {
        ProjectDetail(project: project, onEdit: { editingProject = project })
      } else {
        EmptyState(
          icon: "suit.club.fill",
          title: showArchived ? "No archived spaces" : "No space selected",
          message: showArchived
            ? "Archived spaces stay here until you restore or delete them. Deleting a space keeps its tasks and calendar blocks."
            : "Create or select a space to see its tasks and calendar blocks.")
      }
    }
    .onAppear {
      showArchived = store.project(selectedProjectID)?.isArchived == true
      if selectedProjectID == nil { selectedProjectID = visibleProjects.first?.id }
    }
    .onChange(of: selectedProjectID) { _, id in
      if let project = store.project(id) { showArchived = project.isArchived }
    }
    .onChange(of: visibleProjects.map(\.id)) { _, _ in
      if !visibleProjects.contains(where: { $0.id == selectedProjectID }) {
        selectedProjectID = visibleProjects.first?.id
      }
    }
    .sheet(isPresented: $showingNewProject) { ProjectEditorSheet() }
    .sheet(item: $editingProject) { ProjectEditorSheet(project: $0) }
  }
}

struct ProjectDetail: View {
  @EnvironmentObject private var store: WorkspaceStore
  let project: Project
  let onEdit: () -> Void
  @State private var editingTask: TaskItem?
  @State private var editingEntry: CalendarEntry?
  @State private var newTask = false
  @State private var newEvent = false
  @State private var confirmingDeletion = false
  private var tasks: [TaskItem] { store.tasks.filter { $0.projectID == project.id } }
  private var entries: [CalendarEntry] {
    store.calendarEntries(
      in: DateInterval(start: Date(), end: Date().adding(days: 90)), projectID: project.id)
  }
  private var completion: Double {
    tasks.isEmpty ? 0 : Double(tasks.filter(\.isCompleted).count) / Double(tasks.count)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
              SuitIcon(symbol: project.symbol, color: project.color, size: 18)
              Eyebrow(text: project.isArchived ? "Archived space" : "Your space")
            }
            Text(project.name).font(.strukturSerif(33)).tracking(-0.6)
            Text(project.detail).font(.system(size: 12)).foregroundStyle(StrukturTheme.muted)
          }
          Spacer()
          Button("Edit space", action: onEdit).buttonStyle(StrukturButtonStyle(compact: true))
        }
        if project.isArchived {
          VStack(alignment: .leading, spacing: 12) {
            Text("Archived spaces stay until you restore or delete them. Deleting this space keeps its tasks and calendar blocks outside the space.")
              .font(.system(size: 12)).foregroundStyle(StrukturTheme.muted)
            HStack(spacing: 10) {
              Button("Restore space") {
                var restored = project
                restored.isArchived = false
                store.update(restored)
              }.buttonStyle(StrukturButtonStyle())
              Button("Delete space…", role: .destructive) { confirmingDeletion = true }
                .buttonStyle(StrukturButtonStyle())
            }
          }.strukturCard()
        }
        if !project.goal.isEmpty {
          HStack(spacing: 14) {
            SuitIcon(symbol: project.symbol, color: project.color, size: 37)
            VStack(alignment: .leading, spacing: 6) {
              Eyebrow(text: "Goal")
              Text(project.goal).font(.strukturSerif(20))
            }
            Spacer()
            if let target = project.targetDate {
              VStack(alignment: .trailing, spacing: 5) {
                Text(target.formatted(.dateTime.day().month(.abbreviated))).font(.strukturSerif(21))
                Text(deadlineText(target)).font(.caption2).foregroundStyle(StrukturTheme.muted)
              }
            }
          }.padding(21).background(
            project.color.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 15))
        }
        HStack(spacing: 14) {
          ProjectMetric(
            title: "Completed", value: "\(Int(completion * 100))%",
            detail: "\(tasks.filter(\.isCompleted).count) of \(tasks.count) tasks done",
            color: project.color)
          ProjectMetric(
            title: "Open tasks", value: "\(tasks.filter { !$0.isCompleted }.count)",
            detail: "in this space", color: .sky)
          ProjectMetric(
            title: "Scheduled", value: "\(entries.count)", detail: "blocks in the next 90 days",
            color: .mint)
        }
        HStack(alignment: .top, spacing: 16) {
          VStack(alignment: .leading, spacing: 10) {
            HStack {
              Text("Tasks").font(.strukturSerif(20))
              Spacer()
              IconButton(icon: "plus", label: "Add a task to \(project.name)") { newTask = true }
            }
            ForEach(tasks.filter { !$0.isCompleted }) { task in
              TaskRow(task: task, compact: true).onTapGesture { editingTask = task }
            }
            if tasks.filter({ !$0.isCompleted }).isEmpty {
              Text("A clear page. Add the next meaningful step.").font(.caption).foregroundStyle(
                StrukturTheme.muted
              ).padding(.vertical, 20)
            }
          }.frame(maxWidth: .infinity, alignment: .leading).strukturCard()
          VStack(alignment: .leading, spacing: 10) {
            HStack {
              Text("Time for it").font(.strukturSerif(20))
              Spacer()
              IconButton(icon: "plus", label: "Add a block to \(project.name)") { newEvent = true }
            }
            ForEach(entries) { entry in
              AgendaEntryRow(entry: entry).onTapGesture { editingEntry = entry }
            }
            if entries.isEmpty {
              Text("No calendar blocks in the next 90 days.").font(.caption).foregroundStyle(
                StrukturTheme.muted
              ).padding(.vertical, 20)
            }
          }.frame(maxWidth: .infinity, alignment: .leading).strukturCard()
        }
        ItemReferenceRow(kind: "space", id: project.id)
      }.padding(30)
    }
    .alert("Delete “\(project.name)” permanently?", isPresented: $confirmingDeletion) {
      Button("Cancel", role: .cancel) {}
      Button("Delete space", role: .destructive) { store.removeArchivedProject(id: project.id) }
    } message: {
      Text("The space and its description and goal will be removed. Its tasks, notes, calendar blocks, and focus history are kept. Linked goals keep their tasks, and widgets filtered to this space switch to all spaces. This cannot be undone.")
    }
    .sheet(item: $editingTask) { TaskEditorSheet(task: $0) }
    .sheet(item: $editingEntry) { EventEditorSheet(entry: $0) }
    .sheet(isPresented: $newTask) { TaskEditorSheet(projectID: project.id) }
    .sheet(isPresented: $newEvent) { EventEditorSheet(projectID: project.id) }
  }
}

struct ProjectMetric: View {
  let title: String
  let value: String
  let detail: String
  let color: AccentToken
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        SuitIcon(symbol: color.symbol, color: color, size: 11)
        Text(title).font(.system(size: 10)).foregroundStyle(StrukturTheme.muted)
      }
      Text(value).font(.strukturSerif(31)).monospacedDigit()
      Text(detail).font(.system(size: 10)).foregroundStyle(StrukturTheme.muted)
    }.frame(maxWidth: .infinity, alignment: .leading).strukturCard()
  }
}

struct ProjectEditorSheet: View {
  @EnvironmentObject private var store: WorkspaceStore
  @Environment(\.dismiss) private var dismiss
  @State private var draft: Project
  @State private var hasTarget: Bool
  private let isNew: Bool

  init(project: Project? = nil) {
    _draft = State(initialValue: project ?? Project(name: "", color: .lilac))
    _hasTarget = State(initialValue: project?.targetDate != nil)
    isNew = project == nil
  }

  var body: some View {
    VStack(spacing: 0) {
      SheetHeader(
        title: isNew ? "New space" : "Edit space",
        subtitle: "Keep related tasks, calendar blocks, and notes together.")
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          HStack(spacing: 15) {
            SuitIcon(symbol: draft.symbol, color: draft.color, size: 45)
            TextField("A name for this space", text: $draft.name).font(.strukturSerif(27))
              .textFieldStyle(.plain)
          }.padding(.vertical, 8)
          TextField("Description", text: $draft.detail, axis: .vertical).textFieldStyle(
            .roundedBorder)
          VStack(alignment: .leading, spacing: 7) {
            Eyebrow(text: "Goal")
            TextField("What are you working toward?", text: $draft.goal, axis: .vertical)
              .textFieldStyle(.roundedBorder)
          }
          HStack {
            Toggle("Give it a target date", isOn: $hasTarget)
            Spacer()
            if hasTarget {
              StrukturDateField(
                "Target",
                selection: Binding(
                  get: { draft.targetDate ?? Date().adding(days: 30) },
                  set: { draft.targetDate = $0 }), displayedComponents: .date, showsLabel: false
              )
            }
          }
          HStack(spacing: 14) {
            ForEach(SuitSymbol.allCases) { symbol in
              Button {
                draft.suit = symbol
              } label: {
                SuitIcon(symbol: symbol, color: draft.color, size: 27).frame(width: 56, height: 52)
                  .background(
                    draft.symbol == symbol ? StrukturTheme.hairline : .clear,
                    in: RoundedRectangle(cornerRadius: 12))
              }.buttonStyle(.plain).help(symbol.title)
            }
            Spacer()
          }
          HStack(spacing: 12) {
            Eyebrow(text: "Color")
            ForEach(AccentToken.allCases) { color in
              Button {
                draft.color = color
              } label: {
                Circle().fill(color.color).frame(width: 24, height: 24)
                  .overlay {
                    if draft.color == color {
                      Circle().stroke(StrukturTheme.ink, lineWidth: 1.5).padding(-4)
                    }
                  }
              }.buttonStyle(.plain).help(color.name).accessibilityLabel(color.name)
            }
          }
          if !isNew { Toggle("Archive this space", isOn: $draft.isArchived).font(.caption) }
        }.padding(26)
      }
      Divider()
      SheetActions(canSave: !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
        draft.targetDate = hasTarget ? (draft.targetDate ?? Date().adding(days: 30)) : nil
        isNew ? store.add(draft) : store.update(draft)
        dismiss()
      }
    }.frame(width: 580, height: 570).background(StrukturTheme.canvas)
  }
}
