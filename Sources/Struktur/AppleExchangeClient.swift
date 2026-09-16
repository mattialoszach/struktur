import EventKit
import Foundation

@MainActor
protocol AppleExchangeClient {
  func authorizeEvents() async throws
  func authorizeReminders() async throws
  func saveEvent(_ entry: CalendarEntry) async throws -> String
  func saveTask(_ task: TaskItem) async throws -> String
  func fetchEvents(in window: DateInterval) async throws -> [CalendarEntry]
  func fetchTasks() async throws -> [TaskItem]
}

@MainActor
final class SystemEventKitClient: AppleExchangeClient {
  let eventStore: EKEventStore
  var eventCalendar: EKCalendar?
  var reminderCalendar: EKCalendar?

  init(eventStore: EKEventStore = EKEventStore()) { self.eventStore = eventStore }

  func authorizeEvents() async throws {
    guard try await eventStore.requestFullAccessToEvents() else {
      throw IntegrationError.accessDenied
    }
  }
  func authorizeReminders() async throws {
    guard try await eventStore.requestFullAccessToReminders() else {
      throw IntegrationError.accessDenied
    }
  }
  func saveEvent(_ item: CalendarEntry) async throws -> String {
    guard let calendar = eventCalendar ?? eventStore.defaultCalendarForNewEvents,
      calendar.allowsContentModifications
    else { throw IntegrationError.missingCalendar }
    guard item.recurrence == nil else { throw IntegrationError.expandSeries }
    let event = EKEvent(eventStore: eventStore)
    event.title = item.title
    event.notes = item.notes
    event.startDate = item.start
    event.endDate = item.end
    event.isAllDay = item.isAllDay
    event.location = item.location
    event.calendar = calendar
    try eventStore.save(event, span: .thisEvent, commit: true)
    return event.calendarItemExternalIdentifier ?? event.calendarItemIdentifier
  }
  func saveTask(_ item: TaskItem) async throws -> String {
    guard let calendar = reminderCalendar ?? eventStore.defaultCalendarForNewReminders(),
      calendar.allowsContentModifications
    else { throw IntegrationError.missingReminderList }
    let reminder = EKReminder(eventStore: eventStore)
    reminder.title = item.title
    reminder.notes = item.notes
    reminder.calendar = calendar
    if let due = item.dueDate {
      reminder.dueDateComponents = Calendar.autoupdatingCurrent.dateComponents(
        in: .autoupdatingCurrent, from: due)
    }
    reminder.priority = item.priority == .high ? 1 : (item.priority == .low ? 9 : 5)
    try eventStore.save(reminder, commit: true)
    return reminder.calendarItemExternalIdentifier ?? reminder.calendarItemIdentifier
  }
  func fetchEvents(in window: DateInterval) async throws -> [CalendarEntry] {
    let predicate = eventStore.predicateForEvents(
      withStart: window.start, end: window.end,
      calendars: eventCalendar.map { [$0] })
    return eventStore.events(matching: predicate).map {
      CalendarEntry(
        title: $0.title ?? "Untitled event", notes: $0.notes ?? "", start: $0.startDate,
        end: $0.endDate, color: .sky, location: $0.location ?? "", isAllDay: $0.isAllDay,
        externalIdentifier: $0.calendarItemExternalIdentifier ?? $0.calendarItemIdentifier)
    }
  }
  func fetchTasks() async throws -> [TaskItem] {
    let predicate = eventStore.predicateForReminders(in: reminderCalendar.map { [$0] })
    return await withCheckedContinuation { continuation in
      eventStore.fetchReminders(matching: predicate) { reminders in
        let tasks = (reminders ?? []).map { reminder in
          TaskItem(
            title: reminder.title ?? "Untitled reminder", notes: reminder.notes ?? "",
            isCompleted: reminder.isCompleted, completedAt: reminder.completionDate,
            dueDate: reminder.dueDateComponents.flatMap {
              Calendar.autoupdatingCurrent.date(from: $0)
            },
            priority: reminder.priority > 0 && reminder.priority <= 4
              ? .high : (reminder.priority >= 6 ? .low : .normal),
            color: .mint,
            externalIdentifier: reminder.calendarItemExternalIdentifier
              ?? reminder.calendarItemIdentifier)
        }
        continuation.resume(returning: tasks)
      }
    }
  }
}
