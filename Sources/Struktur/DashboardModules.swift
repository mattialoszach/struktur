import SwiftUI

struct WidgetContent: View {
  let configuration: WidgetConfiguration
  @Binding var selectedDate: Date
  var expanded = false
  var body: some View {
    switch configuration.kind {
    case .dayFlow: DayFlowWidget(selectedDate: $selectedDate, projectID: configuration.projectID)
    case .tasks: NextMovesWidget(selectedDate: selectedDate, projectID: configuration.projectID)
    case .focus: FocusWidget(expanded: expanded)
    case .deadlines: DeadlineWidget(projectID: configuration.projectID, expanded: expanded)
    case .connections:
      ConnectionsWidget(selectedDate: selectedDate, projectID: configuration.projectID)
    case .momentum: MomentumWidget(selectedDate: selectedDate)
    case .todayProgress: ProgressWidget(selectedDate: selectedDate)
    case .upcoming: UpcomingWidget(projectID: configuration.projectID)
    case .projectPulse:
      ProjectPulseWidget(projectID: configuration.projectID, widgetID: configuration.id)
    case .quickNote: NoteWidget(expanded: expanded)
    case .goals:
      GoalTrackerWidget(configuration: configuration, date: selectedDate, expanded: expanded)
    }
  }
}

struct DayFlowWidget: View {
  @EnvironmentObject private var store: WorkspaceStore
  @Binding var selectedDate: Date
  var projectID: UUID?
  @State private var entry: CalendarEntry?
  @State private var task: TaskItem?
  @State private var newEvent = false

  private var mode: Binding<CalendarViewMode> {
    Binding(
      get: { store.preferences.dashboardCalendarMode ?? .day },
      set: { value in store.updatePreferences { $0.dashboardCalendarMode = value } })
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .center) {
        VStack(alignment: .leading, spacing: 5) {
          Group {
            if mode.wrappedValue == .day {
              EditableWording(.scheduleTitle)
            } else {
              Text(selectedDate.formatted(.dateTime.month(.wide)))
            }
          }.font(.strukturSerif(21)).tracking(-0.4)
          HStack(spacing: 5) {
            Circle().fill(AccentToken.mint.color).frame(width: 5, height: 5)
            Text(
              "\(durationText(store.scheduledSeconds(on: selectedDate, projectID: projectID))) planned"
            )
            Text("·")
            Text(
              "\(durationText(max(0, store.workingWindow(on: selectedDate).duration - store.scheduledSeconds(on: selectedDate)))) open"
            )
          }.font(.system(size: 9)).foregroundStyle(StrukturTheme.muted)
        }
        Spacer(minLength: 5)
        Menu {
          ForEach(CalendarViewMode.allCases) { value in
            Button(value == .day ? "Flow" : value.title) { mode.wrappedValue = value }
          }
        } label: {
          HStack(spacing: 5) {
            Text(mode.wrappedValue == .day ? "Flow" : mode.wrappedValue.title)
            Image(systemName: "chevron.down").font(.system(size: 8))
          }.font(.system(size: 10)).padding(.horizontal, 10).padding(.vertical, 6)
            .background(StrukturTheme.canvas, in: RoundedRectangle(cornerRadius: 6))
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        IconButton(icon: "plus", label: "Add a calendar block") { newEvent = true }
      }.padding(.horizontal, 18).padding(.top, 3).padding(.bottom, 15)
      Divider().padding(.horizontal, 18)
      if mode.wrappedValue == .day {
        TimelineView(.periodic(from: .now, by: 30)) { context in
          flow(now: context.date)
        }
      } else {
        CalendarCanvas(
          mode: mode.wrappedValue, selectedDate: $selectedDate, editingEntry: $entry,
          projectID: projectID)
      }
    }
    .sheet(item: $entry) { EventEditorSheet(entry: $0) }
    .sheet(item: $task) { TaskEditorSheet(task: $0) }
    .sheet(isPresented: $newEvent) {
      EventEditorSheet(suggestedDate: selectedDate, projectID: projectID)
    }
  }

  private func flow(now: Date) -> some View {
    let blocks = store.blocks(on: selectedDate, projectID: projectID)
    return VStack(spacing: 0) {
      ScrollView {
        VStack(spacing: 0) {
          if blocks.isEmpty {
            EmptyState(
              icon: "sun.max", title: "Nothing scheduled",
              message: "Add a calendar block to plan time here.")
          }
          ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
            if index > 0 {
              let previousEnd = blocks.prefix(index).map(\.end).max() ?? block.start
              let gap = block.start.timeIntervalSince(previousEnd)
              if gap >= 900 {
                HStack(spacing: 9) {
                  Color.clear.frame(width: 41)
                  Image(systemName: "sparkle").font(.system(size: 10)).foregroundStyle(
                    StrukturTheme.muted)
                  Text("\(durationText(gap)) free").font(.system(size: 9))
                    .foregroundStyle(StrukturTheme.muted)
                  Spacer()
                }.padding(.vertical, 9)
              }
            }
            flowRow(block, now: now)
          }
        }.padding(.horizontal, 18).padding(.vertical, 13)
      }.scrollIndicators(.hidden)
      footer(blocks: blocks, now: now)
    }
  }

  private func flowRow(_ block: DayBlock, now: Date) -> some View {
    let live = !block.isAllDay && block.start <= now && block.end > now
    let ended = block.end <= now
    let symbol = store.project(block.projectID)?.symbol ?? block.color.symbol
    return HStack(alignment: .top, spacing: 10) {
      VStack(alignment: .trailing, spacing: 3) {
        Text(block.isAllDay ? "ALL" : block.start.formatted(.dateTime.hour().minute()))
          .font(.system(size: 10, weight: .medium)).monospacedDigit()
        if !block.isAllDay {
          Text(block.end.formatted(.dateTime.hour().minute())).font(.system(size: 9))
            .foregroundStyle(StrukturTheme.muted)
        }
      }.frame(width: 43, alignment: .trailing).padding(.top, 13)
      VStack(spacing: 0) {
        Circle().fill(live ? StrukturTheme.ink : block.color.color).frame(width: 7, height: 7)
          .overlay {
            if live { Circle().stroke(StrukturTheme.ink.opacity(0.16), lineWidth: 4).padding(-3) }
          }
        Rectangle().fill(StrukturTheme.hairline).frame(width: 1)
      }.frame(width: 9).padding(.top, 17)
      Button {
        if let value = block.entry { entry = value }
        if let value = block.task { task = value }
      } label: {
        HStack(alignment: .center, spacing: 10) {
          VStack(alignment: .leading, spacing: 6) {
            Text(block.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
            HStack(spacing: 5) {
              SuitIcon(symbol: symbol, color: block.color, size: 9)
              Text(
                store.project(block.projectID)?.name ?? (block.task == nil ? "Personal" : "Task"))
              if let location = block.entry?.location, !location.isEmpty {
                Text("· \(location)").lineLimit(1)
              }
            }.font(.system(size: 9)).foregroundStyle(StrukturTheme.muted)
          }
          Spacer(minLength: 0)
          VStack(alignment: .trailing, spacing: 5) {
            if live {
              HStack(spacing: 3) {
                Circle().fill(StrukturTheme.ink).frame(width: 3, height: 3)
                Text("NOW").font(.system(size: 8, weight: .semibold)).tracking(1)
              }
              Text("Ends in \(durationText(block.end.timeIntervalSince(now)))").font(
                .system(size: 9))
            } else if ended {
              Image(systemName: "checkmark").font(.system(size: 10)).foregroundStyle(
                StrukturTheme.muted)
              Text("Ended").font(.system(size: 8)).foregroundStyle(StrukturTheme.muted)
            } else {
              Text(
                block.isAllDay ? "All day" : durationText(block.end.timeIntervalSince(block.start))
              ).font(.system(size: 9)).foregroundStyle(StrukturTheme.muted)
              if block.task != nil { Image(systemName: "checkmark.circle").font(.system(size: 10)) }
            }
          }
        }.padding(.horizontal, 12).padding(.vertical, 12)
          .background(
            block.color.color.opacity(live ? 0.26 : 0.13), in: RoundedRectangle(cornerRadius: 10)
          )
          .overlay {
            if live {
              RoundedRectangle(cornerRadius: 10).strokeBorder(block.color.color.opacity(0.7))
            }
          }
          .opacity(ended ? 0.65 : 1)
      }.buttonStyle(.plain).padding(.bottom, 5)
    }.fixedSize(horizontal: false, vertical: true)
  }

  private func footer(blocks: [DayBlock], now: Date) -> some View {
    let timed = blocks.filter { !$0.isAllDay }
    let end = timed.map(\.end).max()
    let conflicts = ScheduleMath.lanes(for: timed).values.filter { $0.count > 1 }.count
    return HStack(spacing: 8) {
      Image(systemName: conflicts > 0 ? "rectangle.on.rectangle" : "arrow.down.right").font(
        .system(size: 10))
      Text(
        conflicts > 0
          ? "\(conflicts) overlapping blocks · open Calendar to see lanes"
          : (end.map {
            "Last block ends at \($0.formatted(.dateTime.hour().minute()))."
          } ?? "No timed blocks scheduled.")
      )
      .font(.system(size: 9)).lineLimit(2)
      Spacer(minLength: 0)
      SuitIcon(symbol: .club, color: .mint, size: 14)
    }.padding(.horizontal, 15).padding(.vertical, 11)
      .background(StrukturTheme.mint.opacity(0.6))
  }
}

struct NextMovesWidget: View {
  @EnvironmentObject private var store: WorkspaceStore
  let selectedDate: Date
  var projectID: UUID?
  @State private var editingTask: TaskItem?
  @State private var capture = ""

  private var items: [TaskItem] {
    let pending = store.tasks(on: selectedDate, projectID: projectID)
    let completed =
      store.preferences.showCompletedTasks
      ? store.completions(on: selectedDate).filter { projectID == nil || $0.projectID == projectID }
      : []
    return pending + completed
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        EditableWording(.tasksTitle).font(.strukturSerif(17)).tracking(-0.4)
        Spacer()
      }.padding(.horizontal, 17).padding(.bottom, 12)
      HStack(spacing: 5) {
        Text("\(store.tasks(on: selectedDate, projectID: projectID).count) to do").font(
          .system(size: 9, weight: .medium))
        Text("·").foregroundStyle(StrukturTheme.muted)
        Text("\(store.completions(on: selectedDate).count) done today").font(.system(size: 9))
          .foregroundStyle(StrukturTheme.muted)
        Spacer()
      }.padding(.horizontal, 17).padding(.bottom, 12)
      Divider().padding(.horizontal, 17)
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(items) { item in
            VStack(alignment: .leading, spacing: 6) {
              HStack(alignment: .top, spacing: 9) {
                Button {
                  withAnimation(.snappy) { store.toggleTask(item.id) }
                } label: {
                  Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(
                      item.isCompleted ? AccentToken.mint.color : StrukturTheme.muted.opacity(0.55)
                    )
                    .frame(width: 19, height: 22)
                }.buttonStyle(.plain).accessibilityLabel(
                  item.isCompleted ? "Reopen \(item.title)" : "Complete \(item.title)")
                Button {
                  editingTask = item
                } label: {
                  VStack(alignment: .leading, spacing: 7) {
                    Text(item.title).font(.system(size: 11, weight: .medium)).lineLimit(2)
                      .strikethrough(item.isCompleted)
                    HStack(spacing: 4) {
                      if let project = store.project(item.projectID) {
                        SuitIcon(symbol: project.symbol, color: project.color, size: 9)
                        Text(project.name).lineLimit(1)
                      } else {
                        Text("Personal")
                      }
                      Spacer(minLength: 0)
                      Text("\(item.estimateMinutes)m")
                    }.font(.system(size: 9)).foregroundStyle(StrukturTheme.muted)
                    if let due = item.dueDate, !item.isCompleted {
                      HStack(spacing: 4) {
                        Image(systemName: due < Date() ? "exclamationmark.circle" : "flag")
                        Text(deadlineText(due))
                        if item.linkedEventID != nil { Image(systemName: "link") }
                      }.font(.system(size: 8, weight: .medium))
                        .foregroundStyle(
                          due < Date()
                            ? Color(red: 0.72, green: 0.32, blue: 0.25) : StrukturTheme.muted)
                    }
                  }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
              }
              Divider().padding(.leading, 28).padding(.top, 7)
            }.padding(.top, 12)
          }
          if items.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
              SuitIcon(symbol: .heart, color: .peach, size: 25)
              Text("No open tasks").font(.strukturSerif(19))
              Text("Add a task below.").font(.caption)
                .foregroundStyle(StrukturTheme.muted)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 25)
          }
        }.padding(.horizontal, 16)
      }.scrollIndicators(.hidden)
      HStack(spacing: 7) {
        Image(systemName: "plus").font(.system(size: 11)).foregroundStyle(StrukturTheme.muted)
          TextField("Add a task…", text: $capture).textFieldStyle(.plain).font(.system(size: 10))
          .onSubmit(addTask)
        if !capture.isEmpty {
          Button(action: addTask) {
            Image(systemName: "arrow.turn.down.left").font(.system(size: 10))
          }.buttonStyle(.plain).help("Add task")
        }
      }.padding(11).background(StrukturTheme.canvas, in: RoundedRectangle(cornerRadius: 8)).padding(
        12)
    }.sheet(item: $editingTask) { TaskEditorSheet(task: $0) }
  }

  private func addTask() {
    let title = capture.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return }
    store.add(
      TaskItem(
        title: title, dueDate: selectedDate.setting(hour: 17), projectID: projectID,
        color: store.project(projectID)?.color ?? .sky))
    capture = ""
  }
}

struct FocusWidget: View {
  @EnvironmentObject private var store: WorkspaceStore
  var expanded = false
  @State private var minutes = 25
  @State private var taskID: UUID?

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let session = store.workspace.focusSession
      let remaining = session?.remaining(at: context.date) ?? TimeInterval(minutes * 60)
      VStack(alignment: .leading, spacing: expanded ? 25 : 10) {
        HStack(alignment: .center) {
          VStack(alignment: .leading, spacing: 6) {
            Text(session?.isPaused == true ? "Paused" : "Focus timer")
              .font(.system(size: expanded ? 16 : 10)).foregroundStyle(StrukturTheme.muted)
            Text(String(format: "%02d:%02d", Int(ceil(remaining)) / 60, Int(ceil(remaining)) % 60))
              .font(.strukturSerif(expanded ? 82 : 39)).tracking(-2).monospacedDigit()
          }
          Spacer()
          SuitIcon(symbol: .spade, color: .lilac, size: expanded ? 95 : 43).rotationEffect(
            .degrees(-12))
        }
        if expanded {
          Picker("Focus on", selection: $taskID) {
            Text("An open focus session").tag(UUID?.none)
            ForEach(store.tasks.filter { !$0.isCompleted }) { Text($0.title).tag(Optional($0.id)) }
          }.disabled(session != nil)
          Picker("Session length", selection: $minutes) {
            Text("25 minutes").tag(25)
            Text("50 minutes").tag(50)
            Text("90 minutes").tag(90)
          }.pickerStyle(.segmented).labelsHidden().disabled(session != nil)
        }
        HStack(spacing: 7) {
          if let session {
            Button {
              store.toggleFocusPause()
            } label: {
              Label(
                session.isPaused ? "Resume" : "Pause",
                systemImage: session.isPaused ? "play.fill" : "pause.fill"
              )
              .frame(maxWidth: .infinity)
            }.buttonStyle(StrukturButtonStyle(primary: true, compact: !expanded))
            IconButton(icon: "stop.fill", label: "End and save focus session") {
              store.finishFocus()
            }
          } else {
            Button {
              store.startFocus(minutes: minutes, taskID: taskID)
            } label: {
              HStack {
                Image(systemName: "play.fill").font(.system(size: 8))
                Spacer()
                Text("Start focusing")
                Spacer()
                Text("\(minutes)m").opacity(0.65)
              }
              .frame(maxWidth: .infinity)
            }.buttonStyle(StrukturButtonStyle(primary: true, compact: !expanded))
            if !expanded {
              Menu {
                Button("25 minutes") { minutes = 25 }
                Button("50 minutes") { minutes = 50 }
                Button("90 minutes") { minutes = 90 }
              } label: {
                Image(systemName: "chevron.down").font(.system(size: 9))
              }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
          }
        }
        if expanded {
          if let id = session?.taskID, let task = store.tasks.first(where: { $0.id == id }) {
            Text(task.title).font(.strukturSerif(23))
            Button(task.isCompleted ? "Task completed" : "Complete task") {
              if !task.isCompleted { store.toggleTask(id) }
              store.finishFocus()
            }.buttonStyle(StrukturButtonStyle()).disabled(task.isCompleted)
          }
          Text("Your timer continues across the app and after relaunch.").font(.caption)
            .foregroundStyle(StrukturTheme.muted)
          Spacer()
        }
      }.padding(.horizontal, expanded ? 36 : 17).padding(.top, expanded ? 30 : 0).padding(
        .bottom, 16)
    }
    .onAppear { minutes = store.preferences.focusDurationMinutes ?? 25 }
    .onChange(of: minutes) { _, value in store.updatePreferences { $0.focusDurationMinutes = value }
    }
  }
}

struct DeadlineWidget: View {
  @EnvironmentObject private var store: WorkspaceStore
  var projectID: UUID?
  var expanded = false
  @State private var selectedTask: TaskItem?
  private var tasks: [TaskItem] {
    store.tasks.filter {
      !$0.isCompleted && $0.dueDate != nil && (projectID == nil || $0.projectID == projectID)
    }
    .sorted { $0.dueDate! < $1.dueDate! }
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 13) {
        if let next = tasks.first, let due = next.dueDate {
          HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(
              due < Date()
                ? "Overdue"
                : (Calendar.struktur.isDateInToday(due) ? "Due today" : "Next deadline")
            )
            .font(.strukturSerif(expanded ? 28 : 18)).tracking(-0.4)
            Spacer()
          }
          ForEach(tasks.prefix(expanded ? 100 : 2)) { task in
            Button {
              selectedTask = task
            } label: {
              HStack(spacing: 9) {
                SuitIcon(
                  symbol: store.project(task.projectID)?.symbol ?? .diamond,
                  color: store.project(task.projectID)?.color ?? .peach, size: 16)
                VStack(alignment: .leading, spacing: 4) {
                  Text(task.title).font(.system(size: expanded ? 13 : 10, weight: .medium))
                    .lineLimit(1)
                  if let due = task.dueDate {
                    Text(deadlineText(due)).font(.system(size: 9)).foregroundStyle(
                      StrukturTheme.muted)
                  }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.system(size: 9)).foregroundStyle(
                  StrukturTheme.muted)
              }.contentShape(Rectangle())
            }.buttonStyle(.plain)
          }
        } else {
          Text("No upcoming deadlines").font(.strukturSerif(22))
          Text("Open tasks with deadlines appear here.").font(.caption).foregroundStyle(
            StrukturTheme.muted)
        }
      }.padding(.horizontal, 17).padding(.bottom, 15)
    }.scrollIndicators(.hidden).sheet(item: $selectedTask) { TaskEditorSheet(task: $0) }
  }
}

struct ConnectionsWidget: View {
  @EnvironmentObject private var store: WorkspaceStore
  let selectedDate: Date
  var projectID: UUID?
  @State private var selectedProject: Project?
  @State private var editingProject: Project?
  private var projects: [Project] {
    Array(store.projects.filter { projectID == nil || $0.id == projectID }.prefix(3))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack {
        EditableWording(.connectionsTitle).font(.strukturSerif(17)).tracking(-0.3)
        Spacer()
      }.padding(.horizontal, 17)
      if projects.isEmpty {
        Text("Add a space, then link tasks and calendar blocks to it.").font(.caption)
          .foregroundStyle(StrukturTheme.muted).padding(20)
      } else {
        GeometryReader { geometry in
          let width = geometry.size.width
          let height = geometry.size.height
          ZStack(alignment: .topLeading) {
            Canvas { context, size in
              for index in projects.indices {
                let y = height / CGFloat(projects.count) * (CGFloat(index) + 0.5)
                var path = Path()
                path.move(to: CGPoint(x: width * 0.21, y: height * 0.5))
                path.addCurve(
                  to: CGPoint(x: width * 0.40, y: y),
                  control1: CGPoint(x: width * 0.29, y: height * 0.5),
                  control2: CGPoint(x: width * 0.29, y: y))
                path.move(to: CGPoint(x: width * 0.65, y: y))
                path.addLine(to: CGPoint(x: width * 0.72, y: y))
                context.stroke(
                  path, with: .color(projects[index].color.color.opacity(0.7)),
                  style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
              }
            }
            VStack(alignment: .leading, spacing: 5) {
              Text("Your day").font(.strukturSerif(15))
              Text("TASKS + TIME").font(.system(size: 7, weight: .medium)).tracking(0.6)
                .foregroundStyle(StrukturTheme.muted)
            }.position(x: width * 0.12, y: height * 0.5)
            ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
              let y = height / CGFloat(projects.count) * (CGFloat(index) + 0.5)
              Button {
                selectedProject = project
              } label: {
                HStack(spacing: 6) {
                  SuitIcon(symbol: project.symbol, color: project.color, size: 13)
                  Text(project.name).font(.system(size: 10, weight: .medium)).lineLimit(1)
                }.padding(.horizontal, 9).padding(.vertical, 8)
                  .frame(width: width * 0.29, alignment: .leading)
                  .background(
                    project.color.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 7))
              }.buttonStyle(.plain).position(x: width * 0.52, y: y)
              let count = store.tasks.filter { $0.projectID == project.id && !$0.isCompleted }.count
              let seconds = store.scheduledSeconds(on: selectedDate, projectID: project.id)
              VStack(alignment: .leading, spacing: 3) {
                Text("\(count) \(count == 1 ? "task" : "tasks")").font(.system(size: 10, weight: .medium))
                Text("\(durationText(seconds)) on calendar").font(.system(size: 8)).foregroundStyle(
                  StrukturTheme.muted)
              }.frame(width: width * 0.25, alignment: .leading).position(x: width * 0.855, y: y)
            }
          }
        }.padding(.horizontal, 19).padding(.bottom, 12)
      }
    }
    .sheet(item: $selectedProject) { project in
      VStack(spacing: 0) {
        HStack {
          Spacer()
          DismissButton()
        }.padding(12)
        ProjectDetail(
          project: store.project(project.id) ?? project,
          onEdit: { editingProject = store.project(project.id) ?? project })
      }.frame(width: 850, height: 650).background(StrukturTheme.canvas)
        .sheet(item: $editingProject) { ProjectEditorSheet(project: $0) }
    }
  }
}

struct MomentumWidget: View {
  @EnvironmentObject private var store: WorkspaceStore
  let selectedDate: Date
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 5) {
        Text("\(store.streak)").font(.strukturSerif(30))
        Text(store.streak == 1 ? "day in a row" : "days in a row").font(.system(size: 9))
          .foregroundStyle(StrukturTheme.muted)
        Spacer()
        SuitIcon(symbol: .spade, color: .lilac, size: 19)
      }
      HStack(alignment: .bottom, spacing: 7) {
        let start = store.weekStart(for: selectedDate)
        let counts = (0..<7).map { store.completions(on: start.adding(days: $0)).count }
        ForEach(0..<7, id: \.self) { index in
          let date = start.adding(days: index)
          VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3)
              .fill(
                Calendar.struktur.isDateInToday(date)
                  ? AccentToken.lilac.color : AccentToken.lilac.color.opacity(0.4)
              )
              .frame(
                height: max(4, CGFloat(counts[index]) / CGFloat(max(1, counts.max() ?? 1)) * 43))
            Text(date.formatted(.dateTime.weekday(.narrow))).font(.system(size: 8)).foregroundStyle(
              StrukturTheme.muted)
          }.frame(maxWidth: .infinity).help(
            "\(date.formatted(.dateTime.weekday(.wide))): \(counts[index]) completed tasks")
        }
      }.frame(height: 62, alignment: .bottom)
    }.padding(.horizontal, 17).padding(.bottom, 15)
  }
}

struct ProgressWidget: View {
  @EnvironmentObject private var store: WorkspaceStore
  let selectedDate: Date
  var body: some View {
    let completed = store.completions(on: selectedDate).count
    let total = completed + store.tasks(on: selectedDate).count
    HStack(spacing: 20) {
      RingProgress(
        progress: total == 0 ? 0 : Double(completed) / Double(total), color: .mint,
        center: "\(completed)"
      )
      .frame(width: 90, height: 90)
      VStack(alignment: .leading, spacing: 7) {
        EditableWording(.progressTitle).font(.strukturSerif(19))
        Text("\(completed) of \(total) tasks done.").font(.caption).foregroundStyle(
          StrukturTheme.muted)
      }
      Spacer()
    }.padding(17)
  }
}

struct UpcomingWidget: View {
  @EnvironmentObject private var store: WorkspaceStore
  var projectID: UUID?
  @State private var editing: CalendarEntry?
  var body: some View {
    TimelineView(.periodic(from: .now, by: 30)) { context in
      let next = store.nextCalendarEntry(after: context.date, projectID: projectID)
      VStack(alignment: .leading, spacing: 12) {
        if let next {
          Button {
            editing = next
          } label: {
            Text(next.title).font(.strukturSerif(22)).multilineTextAlignment(.leading)
          }.buttonStyle(.plain)
          Text(
            next.isAllDay
              ? next.start.formatted(.dateTime.day().month(.abbreviated)) + " · All day"
              : next.start.formatted(.dateTime.day().month(.abbreviated).hour().minute()) + " – "
                + next.end.formatted(.dateTime.hour().minute())
          )
          .font(.caption).foregroundStyle(StrukturTheme.muted)
          TagPill(
            text: next.start <= context.date
              ? "Ends in \(durationText(next.end.timeIntervalSince(context.date)))"
              : "Starts in \(durationText(next.start.timeIntervalSince(context.date)))",
            color: next.color)
        } else {
          Text("Nothing scheduled next").font(.strukturSerif(22))
        }
        Spacer(minLength: 0)
      }.padding(17)
    }.sheet(item: $editing) { EventEditorSheet(entry: $0) }
  }
}

struct ProjectPulseWidget: View {
  @EnvironmentObject private var store: WorkspaceStore
  var projectID: UUID?
  var widgetID: UUID
  var body: some View {
    let project = store.project(projectID) ?? store.projects.first
    VStack(alignment: .leading, spacing: 11) {
      if let project {
        let tasks = store.tasks.filter { $0.projectID == project.id }
        let completed = tasks.filter(\.isCompleted).count
        let progress = tasks.isEmpty ? 0 : Double(completed) / Double(tasks.count)
        HStack {
          SuitIcon(symbol: project.symbol, color: project.color, size: 20)
          Menu {
            ForEach(store.projects) { item in
              Button(item.name) {
                var widgets = store.widgets
                if let index = widgets.firstIndex(where: { $0.id == widgetID }) {
                  widgets[index].projectID = item.id
                  store.setWidgets(widgets)
                }
              }
            }
          } label: {
            Text(project.name).font(.strukturSerif(18))
          }.menuStyle(.borderlessButton).fixedSize()
          Spacer(minLength: 0)
        }
        Text(project.goal.isEmpty ? project.detail : project.goal).font(.system(size: 10))
          .foregroundStyle(StrukturTheme.muted).lineLimit(2)
        VStack(spacing: 7) {
          GeometryReader { geometry in
            Capsule().fill(StrukturTheme.ink.opacity(0.08))
              .overlay(alignment: .leading) {
                Capsule().fill(StrukturTheme.ink.opacity(0.6)).frame(
                  width: geometry.size.width * progress)
              }
          }.frame(height: 5)
          HStack {
            Text("\(completed) of \(tasks.count) tasks")
            Spacer()
            Text(project.targetDate.map { deadlineText($0) } ?? "\(Int(progress * 100))% complete")
          }.font(.system(size: 9)).foregroundStyle(StrukturTheme.muted)
        }
      } else {
        Text("No space selected").font(.strukturSerif(21))
        Text("Create a space to track a goal here.").font(.caption).foregroundStyle(
          StrukturTheme.muted)
      }
      Spacer(minLength: 0)
    }.padding(.horizontal, 17).padding(.bottom, 15)
  }
}

struct NoteWidget: View {
  @EnvironmentObject private var store: WorkspaceStore
  var expanded = false
  @State private var preview = true
  var body: some View {
    VStack(spacing: 8) {
      if expanded {
        MarkdownComposer(
          text: Binding(get: { store.scratchpad }, set: { store.updateScratchpad($0) }),
          showingPreview: $preview)
      } else {
        HStack {
          EditableWording(.notesTitle).font(.strukturSerif(18))
          Spacer()
          Button(preview ? "Write" : "Read") { preview.toggle() }.buttonStyle(.plain).font(
            .system(size: 9))
        }
        if preview {
          ScrollView {
            MarkdownContent(
              text: Binding(get: { store.scratchpad }, set: { store.updateScratchpad($0) }))
          }
        } else {
          TextEditor(text: Binding(get: { store.scratchpad }, set: { store.updateScratchpad($0) }))
            .font(.system(size: 11)).scrollContentBackground(.hidden)
        }
      }
    }.padding(.horizontal, 17).padding(.bottom, 15).onDisappear { store.saveNow() }
  }
}

struct DismissButton: View {
  @Environment(\.dismiss) private var dismiss
  var body: some View { IconButton(icon: "xmark", label: "Close") { dismiss() } }
}
