import Combine
import SwiftUI

struct RootView: View {
  @EnvironmentObject private var store: WorkspaceStore
  @State private var selection: AppSection = .overview
  @State private var quickCapture: QuickCaptureKind?
  @State private var selectedDate = Date()
  @State private var selectedProjectID: UUID?
  @State private var showingSearch = false
  @State private var showingProject = false
  @State private var linkedTask: TaskItem?
  @State private var linkedEntry: CalendarEntry?
  private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  var body: some View {
    HStack(spacing: 0) {
      SidebarView(
        selection: $selection, selectedDate: $selectedDate, selectedProjectID: $selectedProjectID,
        showingProject: $showingProject
      )
      .frame(width: 210)
      Rectangle().fill(StrukturTheme.hairline).frame(width: 1)
      VStack(spacing: 0) {
        topBar
        Rectangle().fill(StrukturTheme.hairline).frame(height: 1)
        detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        if let error = store.lastSaveError {
          Label(error, systemImage: "exclamationmark.triangle").font(.caption)
            .foregroundStyle(.red).padding(10).frame(maxWidth: .infinity)
            .background(StrukturTheme.peach)
        }
      }
    }
    .background(StrukturTheme.canvas)
    .foregroundStyle(StrukturTheme.ink)
    .tint(StrukturTheme.darkButton)
    .focusedValue(\.showQuickCapture) { quickCapture = $0 }
    .focusedValue(\.navigateToday) {
      selectedDate = Date()
      if selection != .calendar { selection = .overview }
    }
    .sheet(item: $quickCapture) { kind in
      switch kind {
      case .task: TaskEditorSheet()
      case .event: EventEditorSheet(suggestedDate: selectedDate)
      }
    }
    .sheet(isPresented: $showingProject) { ProjectEditorSheet() }
    .sheet(isPresented: $showingSearch) {
      SearchPanel { section, projectID in
        selection = section
        selectedProjectID = projectID
      }
    }
    .sheet(item: $linkedTask) { TaskEditorSheet(task: $0) }
    .sheet(item: $linkedEntry) { EventEditorSheet(entry: $0) }
    .onReceive(clock) { store.reconcileFocus(now: $0) }
    .onAppear {
      store.reconcileFocus()
      if let value = ProcessInfo.processInfo.environment["STRUKTUR_SECTION"],
        let section = AppSection(rawValue: value)
      {
        selection = section
      }
    }
    .onOpenURL { url in
      guard url.scheme == "struktur", let id = UUID(uuidString: url.lastPathComponent) else {
        return
      }
      switch url.host {
      case "task": linkedTask = store.tasks.first { $0.id == id }
      case "event": linkedEntry = store.entries.first { $0.id == id }
      case "space":
        selectedProjectID = id
        selection = .projects
      default: break
      }
    }
  }

  private var topBar: some View {
    HStack(spacing: 12) {
      Eyebrow(text: "Workspace")
      Text("/").foregroundStyle(StrukturTheme.muted.opacity(0.5))
      Text(selection.title).font(.system(size: 11, weight: .medium))
      if store.workspace.isDemo == true {
        TagPill(text: "Sample workspace", color: .butter).help(
          "Example content. Keep it or start empty in Settings.")
      }
      Spacer()
      if let session = store.workspace.focusSession {
        Button {
          selection = .focus
        } label: {
          HStack(spacing: 6) {
            Circle().fill(AccentToken.mint.color).frame(width: 5, height: 5)
            Text(session.isPaused ? "Focus paused" : "Focus in progress")
          }.font(.system(size: 10))
        }.buttonStyle(.plain)
      }
      Button {
        showingSearch = true
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "magnifyingglass")
          Text("Find anything")
          Text("⌘ K").font(.system(size: 9)).padding(3).background(
            StrukturTheme.hairline.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
        }.foregroundStyle(StrukturTheme.muted)
      }.buttonStyle(.plain).keyboardShortcut("k", modifiers: .command)
      Rectangle().fill(StrukturTheme.hairline).frame(width: 1, height: 16).padding(.horizontal, 4)
      Menu {
        Button("New task", systemImage: "checkmark.circle") { quickCapture = .task }
        Button("New calendar block", systemImage: "calendar") { quickCapture = .event }
        Button("New space", systemImage: "suit.club.fill") { showingProject = true }
      } label: {
        Label("Create", systemImage: "plus").font(.system(size: 11, weight: .medium))
      }
      .menuStyle(.borderlessButton).fixedSize()
    }
    .font(.system(size: 11))
    .padding(.horizontal, 30).frame(height: 48)
  }

  @ViewBuilder private var detail: some View {
    switch selection {
    case .overview: DashboardView(selectedDate: $selectedDate, quickCapture: $quickCapture)
    case .calendar: CalendarPage(selectedDate: $selectedDate)
    case .tasks: TasksPage()
    case .projects: ProjectsPage(selectedProjectID: $selectedProjectID)
    case .focus: FocusPage()
    case .insights: InsightsPage()
    case .settings: PreferencesView()
    }
  }
}

extension QuickCaptureKind: Identifiable {
  var id: String { self == .task ? "task" : "event" }
}

struct SidebarView: View {
  @EnvironmentObject private var store: WorkspaceStore
  @Binding var selection: AppSection
  @Binding var selectedDate: Date
  @Binding var selectedProjectID: UUID?
  @Binding var showingProject: Bool

  var body: some View {
    GeometryReader { geometry in
      sidebar(showCalendar: geometry.size.height > 820)
    }
  }

  private func sidebar(showCalendar: Bool) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        Image(systemName: "asterisk").font(.system(size: 25, weight: .heavy))
          .rotationEffect(.degrees(15))
        Text("struktur").font(.strukturSerif(29)).tracking(-1.4)
        Circle().fill(AccentToken.mint.color).frame(width: 6, height: 6).offset(x: -4, y: 9)
      }.padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 32)

      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          Eyebrow(text: "A place for everything").padding(.horizontal, 22).padding(.bottom, 12)
          VStack(spacing: 4) {
            ForEach(AppSection.allCases.filter { $0 != .settings }) { section in
              Button {
                withAnimation(.easeInOut(duration: 0.15)) { selection = section }
              } label: {
                HStack(spacing: 11) {
                  Image(systemName: section.icon).font(.system(size: 14, weight: .regular)).frame(
                    width: 18)
                  Text(section.title).font(
                    .system(size: 12, weight: selection == section ? .semibold : .regular))
                  Spacer()
                  if section == .tasks {
                    Text("\(store.tasks.filter { !$0.isCompleted }.count)").font(
                      .system(size: 9, weight: .medium)
                    ).foregroundStyle(StrukturTheme.muted)
                  }
                  if selection == section {
                    Circle().fill(StrukturTheme.ink).frame(width: 4, height: 4)
                  }
                }
                .foregroundStyle(selection == section ? StrukturTheme.ink : StrukturTheme.muted)
                .padding(.horizontal, 12).frame(height: 37)
                .background(
                  selection == section ? StrukturTheme.surface : .clear,
                  in: RoundedRectangle(cornerRadius: 9)
                )
                .overlay {
                  if selection == section {
                    RoundedRectangle(cornerRadius: 9).strokeBorder(StrukturTheme.hairline)
                  }
                }
                .contentShape(Rectangle())
              }.buttonStyle(.plain)
            }
          }.padding(.horizontal, 12)

          HStack {
            Eyebrow(text: "Your spaces")
            Spacer()
            IconButton(icon: "plus", label: "Create a space") { showingProject = true }
          }.padding(.leading, 22).padding(.trailing, 16).padding(.top, 26).padding(.bottom, 5)

          ForEach(store.projects.prefix(6)) { project in
            Button {
              selectedProjectID = project.id
              selection = .projects
            } label: {
              HStack(spacing: 10) {
                SuitIcon(symbol: project.symbol, color: project.color, size: 14).frame(width: 18)
                Text(project.name).font(.system(size: 11)).lineLimit(1)
                Spacer()
                Text(
                  "\(store.tasks.filter { $0.projectID == project.id && !$0.isCompleted }.count)"
                )
                .font(.system(size: 9)).foregroundStyle(StrukturTheme.muted)
              }.padding(.horizontal, 23).frame(height: 32).contentShape(Rectangle())
            }.buttonStyle(.plain)
          }
          if store.projects.isEmpty {
            Text("Make space for a new idea.").font(.caption).foregroundStyle(StrukturTheme.muted)
              .padding(.horizontal, 22)
          }
        }
      }.scrollIndicators(.hidden)

      if showCalendar {
        SidebarCalendar(selectedDate: $selectedDate) { selection = .overview }.padding(
          .horizontal, 19
        ).padding(.vertical, 24)
      }
      Button {
        selection = .settings
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "slider.horizontal.3").font(.system(size: 13))
          Text("Settings & connections").font(.system(size: 10))
          Spacer()
        }.foregroundStyle(StrukturTheme.muted).padding(.horizontal, 23).padding(.bottom, 18)
      }.buttonStyle(.plain)
      Rectangle().fill(StrukturTheme.hairline).frame(height: 1)
      HStack(spacing: 10) {
        Text(
          store.preferences.displayName.isEmpty
            ? "s." : String(store.preferences.displayName.prefix(1)).lowercased()
        )
        .font(.strukturSerif(19)).frame(width: 31, height: 31).background(
          StrukturTheme.mint, in: Circle())
        VStack(alignment: .leading, spacing: 4) {
          Text(
            store.preferences.displayName.isEmpty
              ? "Your personal space" : store.preferences.displayName
          )
          .font(.system(size: 10, weight: .medium))
          HStack(spacing: 4) {
            Circle().fill(
              store.lastSaveError == nil ? AccentToken.mint.color : AccentToken.rose.color
            ).frame(width: 4, height: 4)
            Text(store.lastSaveError == nil ? "Saved on this Mac" : "Needs attention").font(
              .system(size: 9)
            ).foregroundStyle(StrukturTheme.muted)
          }
        }
      }.padding(19)
    }
    .background(StrukturTheme.sidebar)
  }
}

struct SidebarCalendar: View {
  @EnvironmentObject private var store: WorkspaceStore
  @Binding var selectedDate: Date
  var onSelect: () -> Void
  @State private var month = Date()
  private var calendar: Calendar {
    var value = Calendar.autoupdatingCurrent
    value.firstWeekday = store.preferences.weekStartsMonday ? 2 : 1
    return value
  }
  private var days: [Date?] {
    let start = calendar.dateInterval(of: .month, for: month)!.start
    let blanks = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
    return Array(repeating: nil, count: blanks)
      + (0..<(calendar.range(of: .day, in: .month, for: month)?.count ?? 30)).map {
        start.adding(days: $0)
      }
  }
  var body: some View {
    VStack(spacing: 11) {
      HStack {
        Text(month.formatted(.dateTime.month(.wide))).font(.strukturSerif(14))
        Spacer()
        IconButton(icon: "chevron.left", label: "Previous month") { move(-1) }
        IconButton(icon: "chevron.right", label: "Next month") { move(1) }
      }
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 5)
      {
        ForEach(0..<7, id: \.self) { index in
          let weekday = (calendar.firstWeekday - 1 + index) % 7
          Text(calendar.veryShortWeekdaySymbols[weekday]).font(.system(size: 8)).foregroundStyle(
            StrukturTheme.muted
          ).frame(height: 16)
        }
        ForEach(Array(days.enumerated()), id: \.offset) { _, day in
          if let day {
            Button {
              selectedDate = day
              onSelect()
            } label: {
              Text(day.formatted(.dateTime.day())).font(
                .system(size: 9, weight: calendar.isDateInToday(day) ? .bold : .regular)
              )
              .frame(width: 21, height: 21)
              .foregroundStyle(
                calendar.isDate(day, inSameDayAs: selectedDate)
                  ? StrukturTheme.buttonText : StrukturTheme.ink
              )
              .background(
                calendar.isDate(day, inSameDayAs: selectedDate) ? StrukturTheme.darkButton : .clear,
                in: Circle()
              )
              .overlay(alignment: .bottom) {
                if calendar.isDateInToday(day) {
                  Circle().fill(AccentToken.peach.color).frame(width: 3, height: 3).offset(y: 3)
                }
              }
            }.buttonStyle(.plain)
          } else {
            Color.clear.frame(height: 21)
          }
        }
      }
    }
    .onChange(of: selectedDate) { _, value in month = value }
  }
  private func move(_ direction: Int) {
    month = calendar.date(byAdding: .month, value: direction, to: month) ?? month
  }
}

struct SearchPanel: View {
  @EnvironmentObject private var store: WorkspaceStore
  @Environment(\.dismiss) private var dismiss
  var navigate: (AppSection, UUID?) -> Void
  @State private var query = ""
  @State private var task: TaskItem?
  @State private var entry: CalendarEntry?
  @FocusState private var focused: Bool

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Image(systemName: "magnifyingglass").foregroundStyle(StrukturTheme.muted)
        TextField("Find tasks, events, spaces, or a UID…", text: $query).textFieldStyle(.plain)
          .font(.system(size: 17)).focused($focused)
        Button("Esc") { dismiss() }.buttonStyle(.plain).font(.caption).foregroundStyle(
          StrukturTheme.muted)
      }.padding(24)
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 7) {
          if query.isEmpty {
            Eyebrow(text: "Jump to").padding(.vertical, 8)
            ForEach(AppSection.allCases) { section in
              Button {
                navigate(section, nil)
                dismiss()
              } label: {
                row(section.title, detail: "Open \(section.title.lowercased())", icon: section.icon)
              }.buttonStyle(.plain)
            }
          } else {
            ForEach(store.tasks.filter { matches($0.title + $0.notes + $0.id.uuidString) }) {
              item in
              Button {
                task = item
              } label: {
                row(
                  item.title, detail: "Task · \(store.project(item.projectID)?.name ?? "Personal")",
                  icon: "checkmark.circle")
              }.buttonStyle(.plain)
            }
            ForEach(store.entries.filter { matches($0.title + $0.notes + $0.id.uuidString) }) {
              item in
              Button {
                entry = item
              } label: {
                row(
                  item.title, detail: item.start.formatted(.dateTime.day().month().hour().minute()),
                  icon: "calendar")
              }.buttonStyle(.plain)
            }
            ForEach(store.projects.filter { matches($0.name + $0.detail + $0.id.uuidString) }) {
              project in
              Button {
                navigate(.projects, project.id)
                dismiss()
              } label: {
                row(project.name, detail: "Space · \(project.goal)", icon: project.symbol.icon)
              }.buttonStyle(.plain)
            }
            if !hasMatches {
              EmptyState(
                icon: "magnifyingglass", title: "Nothing here yet",
                message: "Try a title, a note, or an item's identifier.")
            }
          }
        }.padding(18)
      }
      Divider()
      HStack {
        Text("Everything has a place. Find yours.").font(.caption2).foregroundStyle(
          StrukturTheme.muted)
        Spacer()
        Text("⌘ K").font(.caption2)
      }.padding(14)
    }.frame(width: 620, height: 480).background(StrukturTheme.canvas)
      .onAppear { focused = true }
      .sheet(item: $task) { TaskEditorSheet(task: $0) }
      .sheet(item: $entry) { EventEditorSheet(entry: $0) }
  }
  private func matches(_ value: String) -> Bool { value.localizedCaseInsensitiveContains(query) }
  private var hasMatches: Bool {
    store.tasks.contains { matches($0.title + $0.notes + $0.id.uuidString) }
      || store.entries.contains { matches($0.title + $0.notes + $0.id.uuidString) }
      || store.projects.contains { matches($0.name + $0.detail + $0.id.uuidString) }
  }
  private func row(_ title: String, detail: String, icon: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: icon).frame(width: 28).foregroundStyle(StrukturTheme.muted)
      VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1)
        Text(detail).font(.caption2).foregroundStyle(StrukturTheme.muted).lineLimit(1)
      }
      Spacer()
      Image(systemName: "arrow.up.left").font(.caption2).foregroundStyle(StrukturTheme.muted)
    }.padding(10).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
  }
}
