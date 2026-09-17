import Foundation
import SwiftUI

@MainActor
final class WorkspaceStore: ObservableObject {
  @Published private(set) var workspace: Workspace
  @Published var lastSaveError: String?
  @Published private(set) var isSavePending = false

  private let fileURL: URL
  private var saveTask: Task<Void, Never>?
  private var recoveryRequired = false
  private var migrationBackupRequired = false

  init(fileURL: URL? = nil) {
    self.fileURL = fileURL ?? Self.defaultFileURL
    workspace = Self.sampleWorkspace()
    if FileManager.default.fileExists(atPath: self.fileURL.path) {
      do {
        let data = try Data(contentsOf: self.fileURL)
        let decoded = try JSONDecoder.struktur.decode(Workspace.self, from: data)
        try decoded.validate()
        workspace = decoded
        migrationBackupRequired = decoded.schemaVersion < 3
      } catch {
        workspace = Workspace()
        recoveryRequired = true
        lastSaveError =
          "Your saved workspace could not be opened. The original file is untouched. Import a valid backup in Settings. \(error.localizedDescription)"
      }
    }
  }

  static var defaultFileURL: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return base.appending(path: "Struktur", directoryHint: .isDirectory)
      .appending(path: "workspace.json")
  }

  var projects: [Project] { workspace.projects.filter { !$0.isArchived } }
  var entries: [CalendarEntry] { workspace.calendarEntries }
  var tasks: [TaskItem] { workspace.tasks }
  var preferences: UserPreferences { workspace.preferences }
  var scratchpad: String { workspace.scratchpad }

  func project(_ id: UUID?) -> Project? {
    guard let id else { return nil }
    return workspace.projects.first { $0.id == id }
  }

  func add(_ entry: CalendarEntry) {
    workspace.calendarEntries.append(entry)
    changed()
  }

  func update(_ entry: CalendarEntry) {
    if entry.seriesID != nil {
      if let index = workspace.calendarEntries.firstIndex(where: { $0.id == entry.id }) {
        workspace.calendarEntries[index] = entry
      } else {
        workspace.calendarEntries.append(entry)
      }
      changed()
      return
    }
    guard let index = workspace.calendarEntries.firstIndex(where: { $0.id == entry.id }) else {
      return
    }
    var entry = entry
    if entry.recurrence != nil {
      // Cancellation metadata is store-owned; a previously opened editor must not resurrect it.
      entry.excludedOccurrences = Array(
        Set(
          (workspace.calendarEntries[index].excludedOccurrences ?? [])
            + (entry.excludedOccurrences ?? []))
      ).sorted()
    }
    workspace.calendarEntries[index] = entry
    if entry.recurrence == nil {
      for index in workspace.calendarEntries.indices
      where workspace.calendarEntries[index].seriesID == entry.id {
        workspace.calendarEntries[index].seriesID = nil
        workspace.calendarEntries[index].occurrenceIndex = nil
      }
    }
    // Shortening or stopping a series must not leave tasks pointing at missing occurrences.
    for index in workspace.tasks.indices {
      if let linked = workspace.tasks[index].linkedEventID,
        entry.index(for: linked) != nil, resolveEntry(linked) == nil
      {
        workspace.tasks[index].linkedEventID = nil
      }
    }
    changed()
  }

  func removeEntry(id: UUID) {
    let master = entries.first { $0.id == id && $0.recurrence != nil }
    let removedIDs = Set(entries.filter { $0.id == id || $0.seriesID == id }.map(\.id))
    workspace.calendarEntries.removeAll { $0.id == id || $0.seriesID == id }
    for index in workspace.tasks.indices
    where workspace.tasks[index].linkedEventID.map({
      removedIDs.contains($0) || master?.index(for: $0) != nil
    }) == true {
      workspace.tasks[index].linkedEventID = nil
    }
    changed()
  }

  func deleteOccurrence(_ entry: CalendarEntry) {
    guard let seriesID = entry.seriesID, let occurrence = entry.occurrenceIndex,
      let index = workspace.calendarEntries.firstIndex(where: { $0.id == seriesID })
    else {
      removeEntry(id: entry.id)
      return
    }
    workspace.calendarEntries[index].excludedOccurrences = Array(
      Set((workspace.calendarEntries[index].excludedOccurrences ?? []) + [occurrence]))
    workspace.calendarEntries.removeAll { $0.id == entry.id }
    for index in workspace.tasks.indices where workspace.tasks[index].linkedEventID == entry.id {
      workspace.tasks[index].linkedEventID = nil
    }
    changed()
  }

  func saveGoal(_ goal: TrackedGoal) {
    var goals = workspace.goals ?? []
    if let index = goals.firstIndex(where: { $0.id == goal.id }) {
      goals[index] = goal
    } else {
      goals.append(goal)
    }
    workspace.goals = goals
    changed()
  }

  func recordAppleEventExport(_ id: UUID, identifier: String) {
    if let index = workspace.calendarEntries.firstIndex(where: { $0.id == id }) {
      workspace.calendarEntries[index].externalIdentifier = identifier
    } else {
      if workspace.appleEventLinks == nil { workspace.appleEventLinks = [:] }
      workspace.appleEventLinks?[id.uuidString] = identifier
    }
    changed()
  }

  func removeGoal(_ id: UUID) {
    workspace.goals?.removeAll { $0.id == id }
    workspace.preferences.widgetLayout = workspace.preferences.widgetLayout?.map {
      var widget = $0
      if widget.goalID == id { widget.goalID = nil }
      return widget
    }
    changed()
  }

  func add(_ task: TaskItem) {
    workspace.tasks.append(task)
    changed()
  }

  func update(_ task: TaskItem) {
    guard let index = workspace.tasks.firstIndex(where: { $0.id == task.id }) else { return }
    workspace.tasks[index] = task
    changed()
  }

  func toggleTask(_ id: UUID) {
    guard let index = workspace.tasks.firstIndex(where: { $0.id == id }) else { return }
    let wasCompleted = workspace.tasks[index].isCompleted
    workspace.tasks[index].isCompleted.toggle()
    workspace.tasks[index].completedAt = workspace.tasks[index].isCompleted ? Date() : nil
    if !wasCompleted, workspace.tasks[index].isCompleted,
      workspace.tasks[index].cadence == .daily || workspace.tasks[index].cadence == .weekly
    {
      let interval = workspace.tasks[index].cadence == .daily ? 1 : 7
      var next = workspace.tasks[index]
      next.id = UUID()
      next.isCompleted = false
      next.completedAt = nil
      next.createdAt = Date()
      next.externalIdentifier = nil
      let family = workspace.tasks[index].recurrenceID ?? id
      workspace.tasks[index].recurrenceID = family
      next.recurrenceID = family
      let base = next.dueDate ?? next.plannedStart ?? Date()
      let nextDay = max(base.startOfDay, Date().startOfDay).adding(days: interval)
      let parts = Calendar.struktur.dateComponents([.hour, .minute], from: base)
      next.dueDate = nextDay.setting(hour: parts.hour ?? 17, minute: parts.minute ?? 0)
      if let planned = next.plannedStart {
        let time = Calendar.struktur.dateComponents([.hour, .minute], from: planned)
        next.plannedStart = nextDay.setting(hour: time.hour ?? 9, minute: time.minute ?? 0)
      }
      let alreadyExists = workspace.tasks.contains {
        !$0.isCompleted && $0.recurrenceID == family && $0.dueDate == next.dueDate
      }
      if !alreadyExists { workspace.tasks.append(next) }
    }
    changed()
  }

  func removeTask(id: UUID) {
    workspace.tasks.removeAll { $0.id == id }
    if workspace.focusSession?.taskID == id { workspace.focusSession?.taskID = nil }
    changed()
  }

  func add(_ project: Project) {
    workspace.projects.append(project)
    changed()
  }

  func update(_ project: Project) {
    guard let index = workspace.projects.firstIndex(where: { $0.id == project.id }) else { return }
    workspace.projects[index] = project
    changed()
  }

  func updatePreferences(_ edit: (inout UserPreferences) -> Void) {
    edit(&workspace.preferences)
    changed()
  }

  func updateScratchpad(_ value: String) {
    workspace.scratchpad = value
    changed(debounce: true)
  }

  func clearScratchpad() {
    workspace.scratchpad = ""
    changed()
  }

  var focusTitle: String {
    workspace.focusSession?.title ?? workspace.focusDraftTitle ?? ""
  }

  func updateFocusTitle(_ value: String) {
    if workspace.focusSession != nil {
      workspace.focusSession?.title = value
    } else {
      workspace.focusDraftTitle = value
    }
    changed(debounce: true)
  }

  func focusRecordTitle(_ record: FocusRecord) -> String {
    Self.normalizedFocusTitle(record.title)
      ?? tasks.first { $0.id == record.taskID }?.title ?? "Focus session"
  }

  func savedFocusSessions(matching search: String = "") -> [FocusRecord] {
    let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
    return (workspace.focusHistory ?? []).filter {
      query.isEmpty || focusRecordTitle($0).localizedStandardContains(query)
        || ($0.notes ?? "").localizedStandardContains(query)
    }.sorted { $0.endedAt == $1.endedAt ? $0.id.uuidString < $1.id.uuidString : $0.endedAt > $1.endedAt }
  }

  func updateFocusRecord(id: UUID, title: String, notes: String) {
    guard let index = workspace.focusHistory?.firstIndex(where: { $0.id == id }) else { return }
    workspace.focusHistory?[index].title = Self.normalizedFocusTitle(title) ?? "Focus session"
    workspace.focusHistory?[index].notes = notes
    changed()
  }

  func removeFocusRecord(id: UUID) {
    guard workspace.focusHistory?.contains(where: { $0.id == id }) == true else { return }
    workspace.focusHistory?.removeAll { $0.id == id }
    changed()
  }

  private static func normalizedFocusTitle(_ title: String?) -> String? {
    let value = title?.split(whereSeparator: \.isWhitespace).joined(separator: " ") ?? ""
    return value.isEmpty ? nil : value
  }

  func replaceWorkspace(_ newWorkspace: Workspace) {
    recoveryRequired = false
    migrationBackupRequired = false
    workspace = newWorkspace
    changed()
  }

  func exportData(projectID: UUID? = nil) throws -> Data {
    guard let projectID else { return try JSONEncoder.struktur.encode(workspace) }
    var subset = workspace
    subset.projects = workspace.projects.filter { $0.id == projectID }
    subset.tasks = workspace.tasks.filter { $0.projectID == projectID }
    subset.calendarEntries = workspace.calendarEntries.filter { $0.projectID == projectID }
    let selectedSeries = Set(subset.calendarEntries.filter { $0.recurrence != nil }.map(\.id))
    subset.calendarEntries = subset.calendarEntries.map { entry in
      var copy = entry
      if let seriesID = copy.seriesID, !selectedSeries.contains(seriesID) {
        // A moved exception belongs to this space, but its series does not.
        copy.seriesID = nil
        copy.occurrenceIndex = nil
      }
      if copy.recurrence != nil {
        // Do not regenerate occurrences whose exceptions belong to a different space.
        let omitted = workspace.calendarEntries.filter {
          $0.seriesID == copy.id && $0.projectID != projectID
        }.compactMap(\.occurrenceIndex)
        copy.excludedOccurrences = Array(Set((copy.excludedOccurrences ?? []) + omitted)).sorted()
      }
      return copy
    }
    subset.scratchpad = ""
    subset.focusSession = nil
    subset.focusDraftTitle = nil
    subset.preferences.widgetLayout = subset.preferences.widgetLayout?.map { widget in
      var copy = widget
      if copy.projectID != projectID { copy.projectID = nil }
      return copy
    }
    let taskIDs = Set(subset.tasks.map(\.id))
    let eventIDs = Set(subset.calendarEntries.map(\.id))
    subset.appleEventLinks = workspace.appleEventLinks?.filter {
      UUID(uuidString: $0.key).flatMap { resolveEntry($0)?.projectID } == projectID
    }
    subset.tasks = subset.tasks.map {
      var task = $0
      if let linked = task.linkedEventID, !eventIDs.contains(linked),
        resolveEntry(linked)?.projectID != projectID
      {
        task.linkedEventID = nil
      }
      return task
    }
    subset.goals = workspace.goals?.filter {
      (!$0.taskIDs.isEmpty || !$0.projectIDs.isEmpty)
        && $0.taskIDs.allSatisfy(taskIDs.contains)
        && $0.projectIDs.allSatisfy { $0 == projectID }
    }
    let goalIDs = Set((subset.goals ?? []).map(\.id))
    subset.preferences.widgetLayout = subset.preferences.widgetLayout?.map {
      var widget = $0
      if let id = widget.goalID, !goalIDs.contains(id) { widget.goalID = nil }
      return widget
    }
    subset.focusHistory = workspace.focusHistory?.filter { $0.taskID.map(taskIDs.contains) == true }
    return try JSONEncoder.struktur.encode(subset)
  }

  func importData(_ data: Data) throws {
    let imported = try JSONDecoder.struktur.decode(Workspace.self, from: data)
    try imported.validate()
    if FileManager.default.fileExists(atPath: fileURL.path) {
      let backup = fileURL.deletingLastPathComponent().appending(
        path: "workspace-backup-\(UUID().uuidString).json")
      try FileManager.default.copyItem(at: fileURL, to: backup)
    }
    replaceWorkspace(imported)
  }

  func saveNow() {
    saveTask?.cancel()
    isSavePending = false
    guard !recoveryRequired else { return }
    do {
      if migrationBackupRequired {
        let backup = fileURL.deletingLastPathComponent().appending(
          path: "workspace-before-v3-\(UUID().uuidString).json")
        try FileManager.default.copyItem(at: fileURL, to: backup)
        migrationBackupRequired = false
      }
      workspace.schemaVersion = 3
      let folder = fileURL.deletingLastPathComponent()
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try JSONEncoder.struktur.encode(workspace).write(to: fileURL, options: .atomic)
      lastSaveError = nil
    } catch {
      lastSaveError = error.localizedDescription
    }
  }

  func startFocus(minutes: Int, taskID: UUID? = nil, now: Date = Date()) {
    guard workspace.focusSession == nil else { return }
    let duration = TimeInterval(max(1, min(180, minutes)) * 60)
    workspace.focusSession = FocusSession(
      taskID: taskID, startedAt: now, duration: duration, endDate: now.addingTimeInterval(duration),
      title: Self.normalizedFocusTitle(workspace.focusDraftTitle)
        ?? tasks.first { $0.id == taskID }?.title)
    changed()
  }

  func toggleFocusPause(now: Date = Date()) {
    reconcileFocus(now: now)
    guard var session = workspace.focusSession else { return }
    if session.isPaused {
      session.endDate = now.addingTimeInterval(session.remaining(at: now))
      session.pausedRemaining = nil
    } else {
      session.pausedRemaining = session.remaining(at: now)
      session.endDate = nil
    }
    workspace.focusSession = session
    changed()
  }

  func finishFocus(completed: Bool = false, now: Date = Date()) {
    guard let session = workspace.focusSession else { return }
    let completed = completed || (!session.isPaused && session.remaining(at: now) <= 0)
    let seconds = max(0, min(session.duration, session.duration - session.remaining(at: now)))
    let record = FocusRecord(
      id: session.id, taskID: session.taskID, endedAt: completed ? (session.endDate ?? now) : now,
      seconds: seconds, completed: completed,
      title: Self.normalizedFocusTitle(session.title)
        ?? tasks.first { $0.id == session.taskID }?.title ?? "Focus session",
      notes: workspace.scratchpad)
    workspace.focusHistory = (workspace.focusHistory ?? []) + [record]
    workspace.focusSession = nil
    workspace.focusDraftTitle = nil
    changed()
  }

  func reconcileFocus(now: Date = Date()) {
    if let session = workspace.focusSession, !session.isPaused, session.remaining(at: now) <= 0 {
      finishFocus(completed: true, now: now)
    }
  }

  private func changed(debounce: Bool = false) {
    objectWillChange.send()
    saveTask?.cancel()
    if debounce {
      isSavePending = true
      saveTask = Task { [weak self] in
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        self?.saveNow()
      }
    } else {
      saveNow()
    }
  }

  static func sampleWorkspace(now: Date = Date()) -> Workspace {
    let uni = Project(
      name: "University", detail: "Classes, coursework, and exams.", color: .lilac,
      goal: "Finish the semester", suit: .spade)
    let struktur = Project(
      name: "Struktur launch", detail: "Design, development, and release planning.", color: .peach,
      goal: "Ship the first beta", targetDate: now.adding(days: 45), suit: .diamond)
    let health = Project(
      name: "Personal", detail: "Health, errands, and time off.",
      color: .mint, goal: "Exercise regularly", suit: .club)
    let studioID = UUID()
    let seminarID = UUID()
    return Workspace(
      projects: [uni, struktur, health],
      calendarEntries: [
        CalendarEntry(
          title: "Design systems", notes: "Room H12\n\nReview **tokens** before class.",
          start: now.setting(hour: 9), end: now.setting(hour: 10, minute: 30), kind: .lecture,
          color: .lilac, projectID: uni.id, location: "Campus · H12"),
        CalendarEntry(
          id: studioID, title: "Product studio", notes: "Prototype weekly calendar interactions.",
          start: now.setting(hour: 11), end: now.setting(hour: 13), kind: .deepWork, color: .peach,
          projectID: struktur.id),
        CalendarEntry(
          title: "Team sync", start: now.setting(hour: 15), end: now.setting(hour: 15, minute: 45),
          kind: .meeting, color: .sky, projectID: struktur.id, location: "FaceTime"),
        CalendarEntry(
          id: seminarID, title: "Research seminar", start: now.adding(days: 1).setting(hour: 10),
          end: now.adding(days: 1).setting(hour: 12), kind: .lecture, color: .lilac,
          projectID: uni.id),
        CalendarEntry(
          title: "A walk, no headphones", start: now.setting(hour: 18),
          end: now.setting(hour: 18, minute: 30), kind: .personal, color: .mint,
          projectID: health.id),
        CalendarEntry(
          title: "Make something good", start: now.adding(days: 2).setting(hour: 14),
          end: now.adding(days: 2).setting(hour: 16), kind: .deepWork, color: .peach,
          projectID: struktur.id),
        CalendarEntry(
          title: "Systems & society", start: now.adding(days: -1).setting(hour: 9),
          end: now.adding(days: -1).setting(hour: 11), kind: .lecture, color: .lilac,
          projectID: uni.id),
        CalendarEntry(
          title: "A fresh perspective", start: now.adding(days: -2).setting(hour: 10),
          end: now.adding(days: -2).setting(hour: 12), kind: .deepWork, color: .peach,
          projectID: struktur.id),
      ],
      tasks: [
        TaskItem(
          title: "Send seminar outline",
          notes: "## Before you send\n- [ ] Final references\n- [ ] Proofread the introduction",
          dueDate: now.setting(hour: 17), priority: .high, projectID: uni.id, color: .lilac,
          estimateMinutes: 25, linkedEventID: seminarID),
        TaskItem(
          title: "Polish onboarding flow", notes: "Keep the first run calm and human.",
          plannedStart: now.setting(hour: 13, minute: 30), priority: .normal,
          projectID: struktur.id, color: .peach, estimateMinutes: 60, linkedEventID: studioID),
        TaskItem(
          title: "Read interaction design chapter", dueDate: now.adding(days: 1).setting(hour: 20),
          cadence: .once, priority: .normal, projectID: uni.id, color: .sky, estimateMinutes: 45),
        TaskItem(
          title: "Ten-minute reset", notes: "Clear desk and plan tomorrow.",
          dueDate: now.setting(hour: 21), cadence: .daily, priority: .low, projectID: health.id,
          color: .mint, estimateMinutes: 10),
        TaskItem(
          title: "Review lecture notes", isCompleted: true, completedAt: now.setting(hour: 8),
          projectID: uni.id, color: .lilac),
        TaskItem(
          title: "Sketch a better first day", isCompleted: true,
          completedAt: now.setting(hour: 8, minute: 30), projectID: struktur.id, color: .peach),
        TaskItem(
          title: "Collect research references", isCompleted: true,
          completedAt: now.adding(days: -1).setting(hour: 17), projectID: uni.id, color: .lilac),
        TaskItem(
          title: "Get outside", isCompleted: true,
          completedAt: now.adding(days: -1).setting(hour: 18), projectID: health.id, color: .mint),
        TaskItem(
          title: "Map the week", isCompleted: true,
          completedAt: now.adding(days: -2).setting(hour: 8), projectID: struktur.id, color: .peach),
        TaskItem(
          title: "Read something new", isCompleted: true,
          completedAt: now.adding(days: -3).setting(hour: 15), projectID: uni.id, color: .lilac),
      ],
      scratchpad:
        "# Notes\n\nThis week:\n\n- [ ] Review lecture notes\n- [ ] Plan the next project meeting\n",
      isDemo: true
    )
  }
}

extension JSONEncoder {
  static var struktur: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }
}

extension JSONDecoder {
  static var struktur: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
