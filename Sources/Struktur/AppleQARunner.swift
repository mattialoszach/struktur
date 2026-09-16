#if DEBUG
  import AppKit
  import EventKit

  /// Opt-in destructive integration check. Never invoked during normal application use.
  @MainActor
  enum AppleQARunner {
    private static var started = false
    static func runIfRequested() {
      guard !started, ProcessInfo.processInfo.environment["STRUKTUR_APPLE_QA"] == "1" else {
        return
      }
      started = true
      guard Bundle.main.bundleIdentifier == "app.struktur.qa",
        ProcessInfo.processInfo.environment["STRUKTUR_ALLOW_DISPOSABLE_APPLE_DATA"] == "1"
      else {
        report(
          "REFUSED: use the separate QA bundle and explicitly authorize disposable Apple test data."
        )
        return
      }
      Task { await run() }
    }

    private static func report(_ message: String) {
      FileHandle.standardOutput.write(Data("APPLE QA: \(message)\n".utf8))
    }

    private static func run() async {
      let client = SystemEventKitClient()
      let token = "Struktur QA \(UUID().uuidString)"
      var created: [EKCalendar] = []
      var checksPassed = false
      var cleanupSucceeded = true
      do {
        try await client.authorizeEvents()
        try await client.authorizeReminders()
        guard let eventSource = client.eventStore.defaultCalendarForNewEvents?.source,
          let reminderSource = client.eventStore.defaultCalendarForNewReminders()?.source
        else {
          throw WorkspaceValidationError.invalid(
            "Configure writable default Calendar and Reminders accounts before running QA.")
        }
        for (type, source) in [(EKEntityType.event, eventSource), (.reminder, reminderSource)] {
          let calendar = EKCalendar(for: type, eventStore: client.eventStore)
          calendar.title = token
          calendar.source = source
          try client.eventStore.saveCalendar(calendar, commit: true)
          created.append(calendar)
          report(
            "Created disposable \(type == .event ? "calendar" : "list"): \(calendar.calendarIdentifier)"
          )
          if type == .event {
            client.eventCalendar = calendar
          } else {
            client.reminderCalendar = calendar
          }
        }
        let service = AppleIntegrationService(client: client)
        let start = Date().startOfDay.setting(hour: 10)
        let timed = CalendarEntry(
          title: token + " timed", notes: "**QA**", start: start,
          end: start.addingTimeInterval(3600), location: "QA only")
        let allDay = CalendarEntry(
          title: token + " all-day", start: start.startOfDay, end: start.startOfDay.adding(days: 1),
          isAllDay: true)
        let task = TaskItem(
          title: token + " task", notes: "- [ ] QA", dueDate: start.addingTimeInterval(7200),
          priority: .high)
        var saved: [UUID: String] = [:]
        let result = try await service.export(
          entries: [timed, allDay], tasks: [task], includeEvents: true, includeTasks: true
        ) { id, external, _ in saved[id] = external }
        guard result.eventIdentifiers.count == 2, result.taskIdentifiers.count == 1 else {
          throw WorkspaceValidationError.invalid("Export counts did not match.")
        }
        let events = try await service.importCalendar()
        let tasks = try await service.importReminders()
        guard
          events.contains(where: {
            $0.title == timed.title && $0.notes == timed.notes && $0.location == timed.location
              && abs($0.start.timeIntervalSince(timed.start)) < 1
          }),
          events.contains(where: { $0.title == allDay.title && $0.isAllDay && $0.end == allDay.end }
          ),
          tasks.contains(where: {
            $0.title == task.title && $0.notes == task.notes && $0.priority == .high
              && $0.dueDate == task.dueDate
          })
        else {
          throw WorkspaceValidationError.invalid(
            "A live EventKit round-trip changed expected fields.")
        }
        var linkedEvent = timed
        linkedEvent.externalIdentifier = saved[timed.id]
        var linkedTask = task
        linkedTask.externalIdentifier = saved[task.id]
        let retry = try await service.export(
          entries: [linkedEvent], tasks: [linkedTask], includeEvents: true, includeTasks: true
        ) { _, _, _ in }
        guard retry.eventIdentifiers.isEmpty, retry.taskIdentifiers.isEmpty else {
          throw WorkspaceValidationError.invalid("Retry exported duplicate records.")
        }
        checksPassed = true
        report("Round-trip and duplicate-prevention checks passed.")
      } catch {
        report("FAILED or BLOCKED: \(error.localizedDescription)")
      }
      for calendar in created.reversed() {
        do {
          guard calendar.title == token else {
            throw WorkspaceValidationError.invalid(
              "Test container was renamed; refusing automatic cleanup.")
          }
          try client.eventStore.removeCalendar(calendar, commit: true)
          report(
            "Removed disposable container \(calendar.calendarIdentifier). Its QA records were deleted."
          )
        } catch {
          cleanupSucceeded = false
          report("Cleanup needed for \(calendar.calendarIdentifier): \(error.localizedDescription)")
        }
      }
      report(
        checksPassed && cleanupSucceeded
          ? "PASS — test containers removed." : "NOT VERIFIED — see the messages above.")
    }
  }
#endif
