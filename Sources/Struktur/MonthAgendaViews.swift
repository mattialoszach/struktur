import SwiftUI

struct MonthCalendar: View {
  @EnvironmentObject private var store: WorkspaceStore
  @Binding var selectedDate: Date
  @Binding var editingEntry: CalendarEntry?
  var projectID: UUID?

  private var monthDays: [Date?] {
    guard let interval = displayCalendar.dateInterval(of: .month, for: selectedDate),
      let dayRange = displayCalendar.range(of: .day, in: .month, for: selectedDate)
    else { return [] }
    let weekday = displayCalendar.component(.weekday, from: interval.start)
    let blanks = (weekday - displayCalendar.firstWeekday + 7) % 7
    let allDays =
      Array(repeating: Date?.none, count: blanks)
      + dayRange.map { Optional(selectedDate.settingDay($0)) }
    guard !store.preferences.showWeekends else { return allDays }
    return allDays.enumerated().filter { index, _ in
      let weekdayIndex = (index + displayCalendar.firstWeekday - 1) % 7 + 1
      return weekdayIndex != 1 && weekdayIndex != 7
    }.map(\.element)
  }

  var body: some View {
    VStack(spacing: 0) {
      LazyVGrid(
        columns: Array(
          repeating: GridItem(.flexible(), spacing: 0),
          count: store.preferences.showWeekends ? 7 : 5), spacing: 0
      ) {
        ForEach(weekdaySymbols, id: \.self) { symbol in
          Text(symbol.uppercased())
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
      }
      Divider()
      GeometryReader { proxy in
        let columnCount = store.preferences.showWeekends ? 7 : 5
        let rowCount = max(1, Int(ceil(Double(monthDays.count) / Double(columnCount))))
        LazyVGrid(
          columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: columnCount),
          spacing: 0
        ) {
          ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
            MonthDayCell(
              day: day, selectedDate: $selectedDate, editingEntry: $editingEntry,
              projectID: projectID
            )
            .frame(height: proxy.size.height / CGFloat(rowCount))
          }
        }
      }
    }
    .padding(.horizontal, 20)
    .padding(.bottom, 18)
  }

  private var weekdaySymbols: [String] {
    let symbols = displayCalendar.shortWeekdaySymbols
    let first = displayCalendar.firstWeekday - 1
    let ordered = Array(symbols[first...]) + Array(symbols[..<first])
    guard !store.preferences.showWeekends else { return ordered }
    return ordered.filter { $0 != symbols[0] && $0 != symbols[6] }
  }

  private var displayCalendar: Calendar {
    var calendar = Calendar.autoupdatingCurrent
    calendar.firstWeekday = store.preferences.weekStartsMonday ? 2 : 1
    return calendar
  }
}

struct MonthDayCell: View {
  @EnvironmentObject private var store: WorkspaceStore
  let day: Date?
  @Binding var selectedDate: Date
  @Binding var editingEntry: CalendarEntry?
  var projectID: UUID?
  @State private var newEvent = false
  @State private var selectedTask: TaskItem?
  @State private var showingDay = false

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .topLeading) {
        Rectangle().fill(StrukturTheme.hairline)
        Rectangle().fill(StrukturTheme.surface).padding([.top, .leading], 1)
        if let day {
          let entries = entries(on: day)
          let tasks = tasks(on: day)
          let capacity = max(0, Int((geometry.size.height - 55) / 16))
          let eventCount = min(entries.count, capacity)
          let taskCount = min(tasks.count, max(0, capacity - eventCount))
          let hiddenCount = entries.count + tasks.count - eventCount - taskCount
          VStack(alignment: .leading, spacing: 3) {
            HStack {
              Text(day, format: .dateTime.day()).font(.system(size: 11, weight: .medium))
                .frame(width: 22, height: 22)
                .background(
                  Calendar.struktur.isDateInToday(day) ? StrukturTheme.darkButton : .clear,
                  in: Circle()
                )
                .foregroundStyle(
                  Calendar.struktur.isDateInToday(day)
                    ? StrukturTheme.buttonText : StrukturTheme.ink)
              Spacer()
              if !tasks.isEmpty {
                Label("\(tasks.count)", systemImage: "checkmark.circle").font(.system(size: 8))
                  .foregroundStyle(StrukturTheme.muted)
              }
            }.padding(.bottom, 3)
            ForEach(entries.prefix(eventCount)) { entry in
              Button {
                editingEntry = entry
              } label: {
                HStack(spacing: 4) {
                  AccentDot(color: store.project(entry.projectID)?.color ?? entry.color, size: 5)
                  Text(
                    entry.isAllDay ? "All day" : entry.start.formatted(.dateTime.hour().minute())
                  )
                  .font(.system(size: 8)).foregroundStyle(StrukturTheme.muted)
                  Text(entry.title).font(.system(size: 9, weight: .medium)).lineLimit(1)
                  Spacer(minLength: 0)
                }.frame(height: 13)
              }.buttonStyle(.plain).help(entry.title)
            }
            ForEach(tasks.prefix(taskCount)) { task in
              Button {
                selectedTask = task
              } label: {
                Label(task.title, systemImage: "diamond.fill").font(.system(size: 9))
                  .foregroundStyle(StrukturTheme.muted).lineLimit(1).frame(height: 13)
              }.buttonStyle(.plain)
            }
            if hiddenCount > 0 {
              Button("+ \(hiddenCount) more") { showingDay = true }
                .buttonStyle(.plain).font(.system(size: 9)).foregroundStyle(StrukturTheme.muted)
                .help("See all events and tasks for this day")
            }
            Spacer(minLength: 0)
          }.padding(7).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture { selectedDate = day }
            .contextMenu {
              Button("Add a calendar block") {
                selectedDate = day
                newEvent = true
              }
            }
        }
      }.clipped()
    }
    .sheet(isPresented: $newEvent) {
      EventEditorSheet(suggestedDate: day ?? selectedDate, projectID: projectID)
    }
    .sheet(item: $selectedTask) { TaskEditorSheet(task: $0) }
    .popover(isPresented: $showingDay) {
      VStack(alignment: .leading, spacing: 14) {
        HStack {
          Text((day ?? selectedDate).formatted(.dateTime.weekday(.wide).day().month(.wide))).font(
            .strukturSerif(21))
          Spacer()
          IconButton(icon: "xmark", label: "Close day") { showingDay = false }
        }
        ScrollView {
          VStack(spacing: 8) {
            ForEach(entries(on: day ?? selectedDate)) { entry in
              Button {
                showingDay = false
                editingEntry = entry
              } label: {
                AgendaEntryRow(entry: entry)
              }.buttonStyle(.plain)
            }
            ForEach(tasks(on: day ?? selectedDate)) { task in
              TaskRow(task: task, compact: true).onTapGesture {
                showingDay = false
                selectedTask = task
              }
            }
          }
        }
        Button("Add a calendar block") {
          showingDay = false
          newEvent = true
        }.buttonStyle(StrukturButtonStyle(compact: true))
      }.padding(20).frame(width: 420, height: 430).background(StrukturTheme.canvas)
    }
  }

  private func entries(on day: Date) -> [CalendarEntry] {
    store.entries.filter {
      $0.start < day.startOfDay.adding(days: 1) && $0.end > day.startOfDay
        && (projectID == nil || $0.projectID == projectID)
    }.sorted { $0.start < $1.start }
  }
  private func tasks(on day: Date) -> [TaskItem] {
    store.tasks(on: day, includeOverdue: false, projectID: projectID)
  }
}

struct AgendaCalendar: View {
  @EnvironmentObject private var store: WorkspaceStore
  let selectedDate: Date
  @Binding var editingEntry: CalendarEntry?
  var projectID: UUID?
  @State private var selectedTask: TaskItem?

  private var days: [Date] { (0..<30).map { selectedDate.startOfDay.adding(days: $0) } }

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(days, id: \.self) { day in
          let entries = entries(on: day)
          let tasks = tasks(on: day)
          if !entries.isEmpty || !tasks.isEmpty {
            HStack(alignment: .top, spacing: 20) {
              VStack(alignment: .leading, spacing: 2) {
                Text(day, format: .dateTime.weekday(.abbreviated))
                  .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                Text(day, format: .dateTime.day())
                  .font(.strukturSerif(28, weight: .semibold))
              }
              .frame(width: 52, alignment: .leading)

              VStack(spacing: 8) {
                ForEach(entries) { entry in
                  AgendaEntryRow(entry: entry).onTapGesture { editingEntry = entry }
                }
                ForEach(tasks) { task in
                  TaskRow(task: task, compact: true).onTapGesture { selectedTask = task }
                }
              }
              .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 14)
            Divider().padding(.leading, 72)
          }
        }
      }
      .padding(.horizontal, 28)
      .padding(.bottom, 40)
    }
    .sheet(item: $selectedTask) { TaskEditorSheet(task: $0) }
  }

  private func entries(on day: Date) -> [CalendarEntry] {
    store.entries.filter {
      $0.start < day.startOfDay.adding(days: 1) && $0.end > day.startOfDay
        && (projectID == nil || $0.projectID == projectID)
    }.sorted { $0.start < $1.start }
  }
  private func tasks(on day: Date) -> [TaskItem] {
    store.tasks(on: day, includeOverdue: false, projectID: projectID)
  }
}

struct AgendaEntryRow: View {
  let entry: CalendarEntry
  var body: some View {
    HStack(spacing: 12) {
      Capsule().fill(entry.color.color).frame(width: 4, height: 38)
      VStack(alignment: .leading, spacing: 3) {
        Text(entry.title).font(.callout.weight(.semibold))
        HStack(spacing: 5) {
          if entry.isAllDay {
            Text("All day")
            if entry.end > entry.start.startOfDay.adding(days: 1) {
              Text(
                "· Ends "
                  + entry.end.addingTimeInterval(-1).formatted(.dateTime.day().month(.abbreviated)))
            }
          } else {
            Text(entry.start, format: .dateTime.hour().minute())
            Text("–")
            if Calendar.struktur.isDate(entry.start, inSameDayAs: entry.end) {
              Text(entry.end, format: .dateTime.hour().minute())
            } else {
              Text(entry.end, format: .dateTime.day().month(.abbreviated).hour().minute())
            }
          }
          if !entry.location.isEmpty { Text("· \(entry.location)") }
        }
        .font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      Image(systemName: entry.kind.icon).foregroundStyle(entry.color.color)
    }
    .padding(10)
    .background(entry.color.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    .contentShape(Rectangle())
  }
}

extension Date {
  fileprivate func settingDay(_ day: Int) -> Date {
    Calendar.struktur.date(bySetting: .day, value: day, of: self) ?? self
  }
}
