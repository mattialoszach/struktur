import Charts
import SwiftUI

struct FocusPage: View {
  @EnvironmentObject private var store: WorkspaceStore
  @State private var search = ""
  @State private var selectedRecord: FocusRecord?
  @State private var deletingRecord: FocusRecord?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        VStack(alignment: .leading, spacing: 8) {
          Eyebrow(wording: .focusEyebrow)
          EditableWording(.focusTitle).font(.strukturSerif(35)).tracking(-1)
          EditableWording(.focusSubtitle)
            .font(.system(size: 12)).foregroundStyle(StrukturTheme.muted)
        }
        HStack(alignment: .top, spacing: 20) {
          FocusWidget(expanded: true)
            .frame(width: 300).frame(maxHeight: .infinity, alignment: .topLeading)
            .background(StrukturTheme.lavender, in: RoundedRectangle(cornerRadius: 18))
            .accessibilityIdentifier("focus.timerCard")
          ScratchpadView()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .strukturCard(padding: 0)
            .accessibilityIdentifier("focus.notesCard")
        }.fixedSize(horizontal: false, vertical: true)
        savedSessions
      }
      .frame(maxWidth: 1150, alignment: .leading)
      .frame(maxWidth: .infinity)
      .padding(30)
    }
    .scrollIndicators(.hidden)
    .sheet(item: $selectedRecord) { FocusRecordSheet(record: $0, store: store) }
    .alert("Delete this focus session?", isPresented: deleting) {
      Button("Cancel", role: .cancel) { deletingRecord = nil }
      Button("Delete session", role: .destructive) {
        if let record = deletingRecord { store.removeFocusRecord(id: record.id) }
        deletingRecord = nil
      }
    } message: {
      Text("This removes the session and its saved notes. Focus totals and linked goals update. Your working notes stay as they are.")
    }
  }

  private var deleting: Binding<Bool> {
    Binding(get: { deletingRecord != nil }, set: { if !$0 { deletingRecord = nil } })
  }

  private var savedSessions: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .firstTextBaseline) {
        Text("Saved sessions").font(.strukturSerif(22))
        Spacer()
        let today = (store.workspace.focusHistory ?? []).filter {
          Calendar.struktur.isDateInToday($0.endedAt)
        }
        Text("Today · \(focusTimeText(today.reduce(0) { $0 + $1.seconds })) · \(today.count) \(today.count == 1 ? "session" : "sessions")")
          .font(.caption).foregroundStyle(StrukturTheme.muted)
      }
      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass").foregroundStyle(StrukturTheme.muted)
        TextField("Search session titles and notes", text: $search)
          .textFieldStyle(.plain).accessibilityLabel("Search saved sessions")
        if !search.isEmpty {
          IconButton(icon: "xmark", label: "Clear session search") { search = "" }
        }
      }
      .font(.system(size: 12)).padding(10)
      .background(StrukturTheme.canvas, in: RoundedRectangle(cornerRadius: 8))
      let records = store.savedFocusSessions(matching: search)
      if records.isEmpty {
        Text(search.isEmpty
          ? "Finished sessions appear here with their title and notes."
          : "No sessions match your search.")
          .font(.system(size: 12)).foregroundStyle(StrukturTheme.muted).padding(.vertical, 12)
      } else {
        LazyVStack(spacing: 0) {
          ForEach(records) { record in
            HStack(spacing: 14) {
              Button { selectedRecord = record } label: {
                HStack(alignment: .center, spacing: 12) {
                  Image(systemName: record.completed ? "checkmark.circle" : "stop.circle")
                    .foregroundStyle(StrukturTheme.muted)
                  VStack(alignment: .leading, spacing: 5) {
                    Text(store.focusRecordTitle(record)).font(.system(size: 13, weight: .medium))
                    Text(record.endedAt.formatted(date: .abbreviated, time: .shortened))
                      .font(.caption).foregroundStyle(StrukturTheme.muted)
                  }
                  Spacer()
                  Text(focusTimeText(record.seconds)).monospacedDigit()
                  Image(systemName: "chevron.right").font(.caption2)
                    .foregroundStyle(StrukturTheme.muted)
                }
                .contentShape(Rectangle()).padding(.vertical, 14)
              }
              .buttonStyle(.plain)
              .accessibilityLabel("Open session \(store.focusRecordTitle(record))")
              .accessibilityIdentifier("focus.record.\(record.id)")
              IconButton(icon: "trash", label: "Delete session \(store.focusRecordTitle(record))") {
                deletingRecord = record
              }
            }
            if record.id != records.last?.id { Divider() }
          }
        }
      }
    }.strukturCard(padding: 20)
  }
}

struct ScratchpadView: View {
  @EnvironmentObject private var store: WorkspaceStore
  @State private var preview = false
  @State private var confirmingClear = false

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("Focus notes").font(.strukturSerif(20, weight: .semibold))
        Spacer()
        Button("Clear notes…", role: .destructive) { confirmingClear = true }
          .buttonStyle(StrukturButtonStyle(compact: true)).disabled(store.scratchpad.isEmpty)
      }.frame(minHeight: 28)
      MarkdownComposer(
        text: Binding(get: { store.scratchpad }, set: { store.updateScratchpad($0) }),
        showingPreview: $preview, title: "", editorHeight: 300,
        showsLivePreview: false, showsHelp: false, editorLabel: "Focus notes editor")
      HStack(spacing: 6) {
        Image(systemName: store.lastSaveError != nil ? "exclamationmark.triangle" : "checkmark.circle")
        WorkspaceSaveIndicator(
          status: store.saveStatus, failed: store.lastSaveError != nil, savedText: "Autosaved")
        Spacer()
        Text("A copy is kept with each finished session.")
      }.font(.caption2).foregroundStyle(StrukturTheme.muted)
    }
    .padding(20)
    .alert("Clear the working notes?", isPresented: $confirmingClear) {
      Button("Cancel", role: .cancel) {}
      Button("Clear notes", role: .destructive) { store.clearScratchpad() }
    } message: {
      Text("This clears the shared notepad in Focus and Notes widgets. Saved sessions keep their copies.")
    }
    .onDisappear { store.saveNow() }
  }
}

struct FocusRecordSheet: View {
  @EnvironmentObject private var store: WorkspaceStore
  @Environment(\.dismiss) private var dismiss
  let record: FocusRecord
  @State private var title: String
  @State private var notes: String
  @State private var preview = true
  @State private var confirmingDeletion = false

  init(record: FocusRecord, store: WorkspaceStore) {
    self.record = record
    _title = State(initialValue: store.focusRecordTitle(record))
    _notes = State(initialValue: record.notes ?? "")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      SheetHeader(title: "Saved focus session",
        subtitle: "\(record.endedAt.formatted(date: .abbreviated, time: .shortened)) · \(focusTimeText(record.seconds)) · \(record.completed ? "Timer complete" : "Finished early")")
      Divider()
      VStack(alignment: .leading, spacing: 18) {
        TextField("Session title", text: $title)
          .font(.strukturSerif(25)).textFieldStyle(.plain).accessibilityLabel("Saved session title")
        if record.notes == nil {
          Text("This older session has no saved notes. You can add some here.")
            .font(.caption).foregroundStyle(StrukturTheme.muted)
        }
        MarkdownComposer(text: $notes, showingPreview: $preview, editorHeight: 280,
          showsLivePreview: false, showsHelp: false, editorLabel: "Saved session notes editor")
      }.padding(20)
      Spacer(minLength: 0)
      Divider()
      HStack {
        Button("Delete session…", role: .destructive) { confirmingDeletion = true }
          .buttonStyle(StrukturButtonStyle())
        Spacer()
        SheetActions(canSave: !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
          store.updateFocusRecord(id: record.id, title: title, notes: notes)
          dismiss()
        }
      }.padding(.leading, 20)
    }
    .frame(width: 660, height: 580).background(StrukturTheme.canvas)
    .alert("Delete this focus session?", isPresented: $confirmingDeletion) {
      Button("Cancel", role: .cancel) {}
      Button("Delete session", role: .destructive) {
        store.removeFocusRecord(id: record.id)
        dismiss()
      }
    } message: {
      Text("This removes the session and its saved notes. Focus totals and linked goals update. Your working notes stay as they are.")
    }
  }
}

func focusTimeText(_ seconds: TimeInterval) -> String {
  seconds < 60 ? "\(Int(seconds))s" : durationText(seconds)
}

struct InsightsPage: View {
  @EnvironmentObject private var store: WorkspaceStore

  private var weeklyData: [DayMetric] {
    (0..<7).map { offset in
      let day = store.weekStart(for: Date()).adding(days: offset)
      let completed = store.tasks.filter { task in
        task.completedAt.map { Calendar.struktur.isDate($0, inSameDayAs: day) } ?? false
      }.count
      let planned = store.scheduledSeconds(on: day) / 3600
      return DayMetric(day: day, completed: completed, scheduledHours: planned)
    }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 4) {
          EditableWording(.insightsTitle).font(.strukturSerif(30, weight: .semibold))
          EditableWording(.insightsSubtitle).font(.caption)
            .foregroundStyle(.secondary)
        }
        HStack(spacing: 14) {
          ProjectMetric(
            title: "Finished", value: "\(store.tasks.filter(\.isCompleted).count)",
            detail: "tasks in total", color: .mint)
          ProjectMetric(
            title: "Scheduled", value: scheduledLabel, detail: "hours this week", color: .lilac)
          ProjectMetric(
            title: "Open", value: "\(store.tasks.filter { !$0.isCompleted }.count)",
            detail: "across all spaces", color: .peach)
        }
        HStack(alignment: .top, spacing: 14) {
          VStack(alignment: .leading, spacing: 14) {
            Text("Scheduled hours").font(.strukturSerif(20, weight: .semibold))
            Chart(weeklyData) { item in
              BarMark(
                x: .value("Day", item.day, unit: .day), y: .value("Hours", item.scheduledHours)
              )
              .foregroundStyle(AccentToken.lilac.color.gradient)
              .cornerRadius(5)
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 250)
          }.strukturCard().frame(maxWidth: .infinity)
          VStack(alignment: .leading, spacing: 14) {
            Text("Completed tasks").font(.strukturSerif(20, weight: .semibold))
            Chart(weeklyData) { item in
              LineMark(x: .value("Day", item.day, unit: .day), y: .value("Tasks", item.completed))
                // Piecewise monotone cubic interpolation stays between adjacent counts,
                // including flat zero runs, without the overshoot of Catmull–Rom.
                .foregroundStyle(AccentToken.mint.color).interpolationMethod(.monotone)
              PointMark(x: .value("Day", item.day, unit: .day), y: .value("Tasks", item.completed))
                .foregroundStyle(AccentToken.mint.color)
            }
            .chartYScale(domain: 0...max(4, weeklyData.map(\.completed).max() ?? 0))
            .frame(height: 250)
          }.strukturCard().frame(maxWidth: .infinity)
        }
        EditableWording(.insightsFooter)
          .font(.strukturSerif(18)).foregroundStyle(.secondary).padding(.vertical, 12)
      }.padding(28)
    }
  }

  private var scheduledLabel: String {
    String(format: "%.1f", weeklyData.reduce(0) { $0 + $1.scheduledHours })
  }
}

struct DayMetric: Identifiable {
  var id: Date { day }
  let day: Date
  let completed: Int
  let scheduledHours: Double
}
