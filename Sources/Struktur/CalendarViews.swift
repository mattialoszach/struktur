import SwiftUI

struct CalendarPage: View {
  @EnvironmentObject private var store: WorkspaceStore
  @Binding var selectedDate: Date
  @State private var mode: CalendarViewMode = .week
  @State private var editingEntry: CalendarEntry?
  @State private var newEvent = false

  var body: some View {
    VStack(spacing: 0) {
      CalendarToolbar(selectedDate: $selectedDate, mode: $mode) { newEvent = true }
      HStack(spacing: 15) {
        ForEach(store.projects.prefix(5)) { project in
          HStack(spacing: 5) {
            SuitIcon(symbol: project.symbol, color: project.color, size: 11)
            Text(project.name).font(.system(size: 10)).foregroundStyle(StrukturTheme.muted)
          }
        }
        Spacer()
        Label(calendarHint, systemImage: "cursorarrow").font(
          .system(size: 9)
        ).foregroundStyle(StrukturTheme.muted)
      }.padding(.horizontal, 30).padding(.bottom, 18)
      Divider()
      CalendarCanvas(mode: mode, selectedDate: $selectedDate, editingEntry: $editingEntry)
        .background(StrukturTheme.surface)
    }
    .onAppear { mode = store.preferences.defaultCalendarMode }
    .onChange(of: mode) { _, value in store.updatePreferences { $0.defaultCalendarMode = value } }
    .sheet(item: $editingEntry) { EventEditorSheet(entry: $0) }
    .sheet(isPresented: $newEvent) { EventEditorSheet(suggestedDate: selectedDate) }
  }

  private var calendarHint: String {
    switch mode {
    case .day, .week: "Double-click an open slot to add a block"
    case .month: "Right-click a day to add a block"
    case .agenda: "Open a block to see its connected tasks"
    }
  }
}

struct CalendarToolbar: View {
  @EnvironmentObject private var store: WorkspaceStore
  @Binding var selectedDate: Date
  @Binding var mode: CalendarViewMode
  var addEvent: () -> Void = {}
  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 7) {
        Eyebrow(wording: .calendarEyebrow)
        Text(periodTitle).font(.strukturSerif(31)).tracking(-0.7)
      }
      Spacer()
      Button("Today") { withAnimation { selectedDate = Date() } }.buttonStyle(
        StrukturButtonStyle(compact: true))
      HStack(spacing: 1) {
        IconButton(icon: "chevron.left", label: "Previous period") { move(-1) }
        IconButton(icon: "chevron.right", label: "Next period") { move(1) }
      }
      StrukturOptions(label: "Calendar view", selection: $mode, options: CalendarViewMode.allCases)
      {
        $0.title
      }.frame(width: 248)
      Button(action: addEvent) { Image(systemName: "plus") }.buttonStyle(
        StrukturButtonStyle(primary: true, compact: true)
      ).help("New calendar block")
    }.padding(30)
  }
  private var periodTitle: String {
    switch mode {
    case .day: selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide))
    case .week:
      "Week of " + store.weekStart(for: selectedDate).formatted(.dateTime.day().month(.wide))
    case .month: selectedDate.formatted(.dateTime.month(.wide).year())
    case .agenda: "Upcoming schedule"
    }
  }
  private func move(_ direction: Int) {
    let component: Calendar.Component =
      mode == .month ? .month : (mode == .day ? .day : .weekOfYear)
    withAnimation(.easeInOut(duration: 0.2)) {
      selectedDate =
        Calendar.struktur.date(byAdding: component, value: direction, to: selectedDate)
        ?? selectedDate
    }
  }
}

struct CalendarCanvas: View {
  @EnvironmentObject private var store: WorkspaceStore
  let mode: CalendarViewMode
  @Binding var selectedDate: Date
  @Binding var editingEntry: CalendarEntry?
  var projectID: UUID?
  var body: some View {
    switch mode {
    case .day:
      TimelineCalendar(
        days: [selectedDate.startOfDay], editingEntry: $editingEntry, projectID: projectID)
    case .week:
      TimelineCalendar(days: visibleWeekDays, editingEntry: $editingEntry, projectID: projectID)
    case .month:
      MonthCalendar(selectedDate: $selectedDate, editingEntry: $editingEntry, projectID: projectID)
    case .agenda:
      AgendaCalendar(selectedDate: selectedDate, editingEntry: $editingEntry, projectID: projectID)
    }
  }
  private var visibleWeekDays: [Date] {
    let days = (0..<7).map { store.weekStart(for: selectedDate).adding(days: $0) }
    return store.preferences.showWeekends
      ? days : days.filter { !Calendar.struktur.isDateInWeekend($0) }
  }
}

struct TimelineCalendar: View {
  @EnvironmentObject private var store: WorkspaceStore
  let days: [Date]
  @Binding var editingEntry: CalendarEntry?
  var projectID: UUID?
  @State private var editingTask: TaskItem?
  @State private var newDate: Date?
  private let hourHeight: CGFloat = 72
  private var startHour: Int { store.preferences.workingDayStart }
  private var endHour: Int { store.preferences.workingDayEnd }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        Text(TimeZone.current.abbreviation() ?? "TIME")
          .font(.system(size: 8, weight: .medium)).foregroundStyle(StrukturTheme.muted).frame(
            width: 58)
        ForEach(days, id: \.self) { day in
          HStack(spacing: 7) {
            Text(day, format: .dateTime.weekday(.abbreviated)).font(.system(size: 10))
              .foregroundStyle(StrukturTheme.muted)
            Text(day, format: .dateTime.day()).font(.strukturSerif(18))
              .frame(width: 29, height: 29)
              .background(
                Calendar.struktur.isDateInToday(day) ? StrukturTheme.darkButton : .clear,
                in: Circle()
              )
              .foregroundStyle(
                Calendar.struktur.isDateInToday(day) ? StrukturTheme.buttonText : StrukturTheme.ink)
          }.frame(maxWidth: .infinity).padding(.vertical, 13)
        }
      }
      Divider()
      if hasDayMarkers {
        dayMarkers
        Divider()
      }
      ScrollViewReader { reader in
        ScrollView(.vertical) {
          TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(alignment: .top, spacing: 0) {
              VStack(spacing: 0) {
                ForEach(startHour..<endHour, id: \.self) { hour in
                  Text(String(format: "%02d:00", hour)).font(.system(size: 9)).monospacedDigit()
                    .foregroundStyle(StrukturTheme.muted)
                    .frame(width: 50, height: hourHeight, alignment: .topTrailing)
                    .padding(.trailing, 8).id(hour)
                }
              }
              HStack(spacing: 0) {
                ForEach(days, id: \.self) { day in
                  dayColumn(day, now: context.date).frame(maxWidth: .infinity)
                }
              }
            }.padding(.top, 12)
          }
        }.scrollIndicators(.hidden)
          .onAppear { reader.scrollTo(max(startHour, min(endHour - 1, 8)), anchor: .top) }
      }
    }
    .sheet(item: $editingTask) { TaskEditorSheet(task: $0) }
    .sheet(
      item: Binding(get: { newDate.map { DateSelection(date: $0) } }, set: { newDate = $0?.date })
    ) { selection in
      EventEditorSheet(suggestedDate: selection.date, projectID: projectID)
    }
  }

  private var hasDayMarkers: Bool {
    days.contains { day in
      store.blocks(on: day, projectID: projectID).contains(where: \.isAllDay)
        || store.tasks.contains {
          !$0.isCompleted && (projectID == nil || $0.projectID == projectID)
            && $0.dueDate.map { Calendar.struktur.isDate($0, inSameDayAs: day) } == true
        }
    }
  }

  private var dayMarkers: some View {
    HStack(alignment: .top, spacing: 0) {
      VStack(alignment: .trailing, spacing: 5) {
        Text("ALL DAY")
        Text("& DUE")
      }.font(.system(size: 7, weight: .medium)).foregroundStyle(StrukturTheme.muted).frame(
        width: 50
      ).padding(.trailing, 8).padding(.top, 9)
      ForEach(days, id: \.self) { day in
        ScrollView {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(store.blocks(on: day, projectID: projectID).filter(\.isAllDay)) { block in
              Button {
                editingEntry = block.entry
              } label: {
                marker(block.title, color: block.color, icon: "sun.max")
              }.buttonStyle(.plain)
            }
            ForEach(
              store.tasks.filter {
                !$0.isCompleted && (projectID == nil || $0.projectID == projectID)
                  && $0.dueDate.map { Calendar.struktur.isDate($0, inSameDayAs: day) } == true
              }
            ) { task in
              Button {
                editingTask = task
              } label: {
                marker(
                  "\(task.dueDate!.formatted(.dateTime.hour().minute())) · \(task.title)",
                  color: store.project(task.projectID)?.color ?? task.color, icon: "diamond.fill")
              }.buttonStyle(.plain)
            }
          }.padding(5)
        }.frame(maxWidth: .infinity).frame(height: 57).scrollIndicators(.hidden)
      }
    }
  }

  private func marker(_ text: String, color: AccentToken, icon: String) -> some View {
    HStack(spacing: 4) {
      Image(systemName: icon).font(.system(size: 7))
      Text(text).font(.system(size: 9)).lineLimit(1)
      Spacer(minLength: 0)
    }.padding(5).background(color.color.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
  }

  private func dayColumn(_ day: Date, now: Date) -> some View {
    let window = store.workingWindow(on: day)
    let blocks = store.blocks(on: day, projectID: projectID).filter {
      !$0.isAllDay && $0.end > window.start && $0.start < window.end
    }
    let lanes = ScheduleMath.lanes(for: blocks)
    let totalHeight = CGFloat(endHour - startHour) * hourHeight
    return GeometryReader { geometry in
      ZStack(alignment: .topLeading) {
        VStack(spacing: 0) {
          ForEach(startHour..<endHour, id: \.self) { _ in
            Rectangle().fill(StrukturTheme.hairline).frame(height: 1)
            Color.clear.frame(height: hourHeight - 1)
          }
        }
        Rectangle().fill(StrukturTheme.hairline).frame(width: 1)
        Color.clear.contentShape(Rectangle())
          .onTapGesture(count: 2) { location in
            let minutes = max(
              0,
              min(
                (endHour - startHour) * 60 - 15,
                Int((location.y / hourHeight * 60 / 15).rounded()) * 15))
            newDate = window.start.addingTimeInterval(TimeInterval(minutes * 60))
          }
        ForEach(blocks) { block in
          let lane = lanes[block.id] ?? (index: 0, count: 1)
          let width = geometry.size.width / CGFloat(lane.count)
          let top = max(block.start, window.start)
          let bottom = min(block.end, window.end)
          Button {
            if let entry = block.entry { editingEntry = entry }
            if let task = block.task { editingTask = task }
          } label: {
            CalendarBlockView(block: block, now: now)
          }
          .buttonStyle(.plain)
          .frame(
            width: max(12, width - 7),
            height: max(23, CGFloat(bottom.timeIntervalSince(top) / 3600) * hourHeight - 4)
          )
          .offset(
            x: CGFloat(lane.index) * width + 4,
            y: CGFloat(top.timeIntervalSince(window.start) / 3600) * hourHeight
          )
          .help(
            "\(block.title)\n\(block.start.formatted(.dateTime.hour().minute())) – \(block.end.formatted(.dateTime.hour().minute()))\n\(store.project(block.projectID)?.name ?? "Personal")"
          )
        }
        if now >= window.start && now < window.end {
          HStack(spacing: 0) {
            Circle().fill(AccentToken.rose.color).frame(width: 6, height: 6)
            Rectangle().fill(AccentToken.rose.color).frame(height: 1)
          }.offset(x: -3, y: CGFloat(now.timeIntervalSince(window.start) / 3600) * hourHeight)
            .allowsHitTesting(false)
        }
      }
      .frame(height: totalHeight)
      .clipped()
      .dropDestination(for: String.self) { items, location in
        guard let value = items.first, value.hasPrefix("struktur-task:"),
          let id = UUID(uuidString: String(value.dropFirst(14))),
          var task = store.tasks.first(where: { $0.id == id })
        else { return false }
        let minutes = max(
          0,
          min(
            (endHour - startHour) * 60 - task.estimateMinutes,
            Int((location.y / hourHeight * 60 / 15).rounded()) * 15))
        task.plannedStart = window.start.addingTimeInterval(TimeInterval(minutes * 60))
        store.update(task)
        return true
      }
    }.frame(height: totalHeight)
  }
}

struct CalendarBlockView: View {
  @EnvironmentObject private var store: WorkspaceStore
  let block: DayBlock
  let now: Date
  var body: some View {
    GeometryReader { geometry in
      HStack(alignment: .top, spacing: 5) {
        Capsule().fill(block.color.color).frame(width: 3)
        VStack(alignment: .leading, spacing: 4) {
          Text(block.title).font(.system(size: 11, weight: .medium)).lineLimit(
            geometry.size.height > 65 ? 2 : 1)
          if geometry.size.height > 39 {
            Text(
              block.start.formatted(.dateTime.hour().minute()) + " – "
                + block.end.formatted(.dateTime.hour().minute())
            )
            .font(.system(size: 8)).monospacedDigit().foregroundStyle(StrukturTheme.muted)
            .lineLimit(1)
          }
          if geometry.size.height > 65 {
            HStack(spacing: 4) {
              SuitIcon(
                symbol: store.project(block.projectID)?.symbol ?? block.color.symbol,
                color: block.color, size: 8)
              Text(
                store.project(block.projectID)?.name
                  ?? (block.task != nil ? "Scheduled task" : "Personal")
              ).font(.system(size: 8)).foregroundStyle(StrukturTheme.muted).lineLimit(1)
            }
          }
          Spacer(minLength: 0)
          if block.start <= now && block.end > now && geometry.size.height > 90 {
            Text("ENDS IN \(durationText(block.end.timeIntervalSince(now)).uppercased())").font(
              .system(size: 7, weight: .semibold)
            ).tracking(0.5)
          }
        }.frame(maxWidth: .infinity, alignment: .topLeading)
      }.padding(6).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(block.color.color.opacity(0.21), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
          if block.task != nil {
            RoundedRectangle(cornerRadius: 7).strokeBorder(
              block.color.color, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
          }
        }
    }
  }
}

struct EventBlock: View {
  let entry: CalendarEntry
  var body: some View {
    CalendarBlockView(
      block: DayBlock(
        id: entry.id, title: entry.title, start: entry.start, end: entry.end, color: entry.color,
        projectID: entry.projectID, entry: entry), now: Date())
  }
}

struct TaskPin: View {
  let task: TaskItem
  var body: some View {
    Label(task.title, systemImage: "diamond.fill").font(.system(size: 9))
      .padding(5).background(task.color.color.opacity(0.3), in: Capsule())
  }
}

private struct DateSelection: Identifiable {
  let date: Date
  var id: Date { date }
}
