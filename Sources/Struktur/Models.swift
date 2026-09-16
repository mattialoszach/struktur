import Foundation
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
  case overview, calendar, tasks, projects, focus, insights, settings

  var id: String { rawValue }
  var title: String {
    switch self {
    case .overview: "Your day"
    case .projects: "Spaces"
    case .focus: "Focus room"
    case .insights: "Your rhythm"
    default: rawValue.capitalized
    }
  }
  var icon: String {
    switch self {
    case .overview: "rectangle.3.group"
    case .calendar: "calendar"
    case .tasks: "checkmark.circle"
    case .projects: "square.stack.3d.up"
    case .focus: "timer"
    case .insights: "chart.xyaxis.line"
    case .settings: "slider.horizontal.3"
    }
  }
}

enum CalendarViewMode: String, CaseIterable, Codable, Identifiable {
  case day, week, month, agenda
  var id: String { rawValue }
  var title: String { rawValue.capitalized }
}

enum TaskRailPosition: String, CaseIterable, Codable, Identifiable {
  case trailing, bottom, hidden
  var id: String { rawValue }
  var title: String {
    switch self {
    case .trailing: "Right"
    case .bottom: "Bottom"
    case .hidden: "Hidden"
    }
  }
}

enum AppAppearance: String, CaseIterable, Codable, Identifiable {
  case system, light, dark
  var id: String { rawValue }
  var title: String { rawValue.capitalized }
  var colorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
}

enum ItemKind: String, CaseIterable, Codable, Identifiable {
  case lecture, meeting, deepWork, personal, deadline
  var id: String { rawValue }
  var title: String {
    switch self {
    case .lecture: "Lecture"
    case .meeting: "Meeting"
    case .deepWork: "Deep work"
    case .personal: "Personal"
    case .deadline: "Deadline"
    }
  }
  var icon: String {
    switch self {
    case .lecture: "graduationcap.fill"
    case .meeting: "person.2.fill"
    case .deepWork: "brain.head.profile.fill"
    case .personal: "sparkles"
    case .deadline: "flag.fill"
    }
  }
}

enum TaskCadence: String, CaseIterable, Codable, Identifiable {
  case once, daily, weekly, openEnded
  var id: String { rawValue }
  var title: String {
    switch self {
    case .once: "One time"
    case .daily: "Daily"
    case .weekly: "Weekly"
    case .openEnded: "Open-ended"
    }
  }
}

enum TaskPriority: String, CaseIterable, Codable, Identifiable {
  case low, normal, high
  var id: String { rawValue }
  var title: String { rawValue.capitalized }
}

enum AccentToken: String, CaseIterable, Codable, Identifiable {
  case lilac, peach, mint, sky, butter, rose, graphite
  var id: String { rawValue }
  var name: String { rawValue.capitalized }
  var color: Color {
    switch self {
    case .lilac: Color(red: 0.76, green: 0.70, blue: 0.94)
    case .peach: Color(red: 0.96, green: 0.72, blue: 0.60)
    case .mint: Color(red: 0.62, green: 0.86, blue: 0.75)
    case .sky: Color(red: 0.58, green: 0.78, blue: 0.94)
    case .butter: Color(red: 0.95, green: 0.85, blue: 0.51)
    case .rose: Color(red: 0.93, green: 0.66, blue: 0.76)
    case .graphite: Color(red: 0.43, green: 0.45, blue: 0.49)
    }
  }
}

struct Project: Identifiable, Codable, Hashable {
  var id = UUID()
  var name: String
  var detail: String = ""
  var color: AccentToken
  var goal: String = ""
  var targetDate: Date?
  var isArchived = false
  var suit: SuitSymbol?
  var symbol: SuitSymbol { suit ?? color.symbol }
}

struct CalendarEntry: Identifiable, Codable, Hashable {
  var id = UUID()
  var title: String
  var notes: String = ""
  var start: Date
  var end: Date
  var kind: ItemKind = .personal
  var color: AccentToken = .lilac
  var projectID: UUID?
  var location: String = ""
  var isAllDay = false
  var externalIdentifier: String?
}

struct TaskItem: Identifiable, Codable, Hashable {
  var id = UUID()
  var title: String
  var notes: String = ""
  var isCompleted = false
  var createdAt = Date()
  var completedAt: Date?
  var dueDate: Date?
  var plannedStart: Date?
  var cadence: TaskCadence = .once
  var priority: TaskPriority = .normal
  var projectID: UUID?
  var color: AccentToken = .sky
  var estimateMinutes = 30
  var externalIdentifier: String?
  var linkedEventID: UUID?
  var recurrenceID: UUID?
}

enum DashboardWidgetKind: String, CaseIterable, Codable, Identifiable {
  case dayFlow, tasks, focus, deadlines, connections, momentum, todayProgress, upcoming,
    projectPulse, quickNote
  var id: String { rawValue }
  var title: String {
    switch self {
    case .dayFlow: "Day timeline"
    case .tasks: "Your next moves"
    case .focus: "A little focus"
    case .deadlines: "On the horizon"
    case .connections: "Everything, connected"
    case .momentum: "Momentum"
    case .todayProgress: "Today’s progress"
    case .upcoming: "Up next"
    case .projectPulse: "Project pulse"
    case .quickNote: "Quick note"
    }
  }
  var icon: String {
    switch self {
    case .dayFlow: "calendar"
    case .tasks: "checkmark.circle"
    case .focus: "timer"
    case .deadlines: "flag"
    case .connections: "point.3.connected.trianglepath.dotted"
    case .momentum: "flame.fill"
    case .todayProgress: "circle.dotted.circle"
    case .upcoming: "arrow.forward.circle.fill"
    case .projectPulse: "scope"
    case .quickNote: "note.text"
    }
  }
}

struct UserPreferences: Codable, Equatable {
  var defaultCalendarMode: CalendarViewMode = .week
  var taskRailPosition: TaskRailPosition = .trailing
  var appearance: AppAppearance = .system
  var weekStartsMonday = true
  var showWeekends = true
  var workingDayStart = 7
  var workingDayEnd = 22
  var showCompletedTasks = false
  var enabledWidgets: [DashboardWidgetKind] = [.momentum, .todayProgress, .upcoming, .projectPulse]
  var widgetLayout: [WidgetConfiguration]? = WidgetConfiguration.starterLayout
  var displayName = ""
  var dashboardCalendarMode: CalendarViewMode? = .day
  var focusDurationMinutes: Int? = 25

  init() {}

  private enum CodingKeys: String, CodingKey {
    case defaultCalendarMode, taskRailPosition, appearance, weekStartsMonday, showWeekends
    case workingDayStart, workingDayEnd, showCompletedTasks, enabledWidgets, widgetLayout,
      displayName, dashboardCalendarMode, focusDurationMinutes
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    defaultCalendarMode =
      try values.decodeIfPresent(CalendarViewMode.self, forKey: .defaultCalendarMode) ?? .week
    taskRailPosition =
      try values.decodeIfPresent(TaskRailPosition.self, forKey: .taskRailPosition) ?? .trailing
    appearance = try values.decodeIfPresent(AppAppearance.self, forKey: .appearance) ?? .system
    weekStartsMonday = try values.decodeIfPresent(Bool.self, forKey: .weekStartsMonday) ?? true
    showWeekends = try values.decodeIfPresent(Bool.self, forKey: .showWeekends) ?? true
    workingDayStart = min(
      23, max(0, try values.decodeIfPresent(Int.self, forKey: .workingDayStart) ?? 7))
    workingDayEnd = min(
      24,
      max(workingDayStart + 1, try values.decodeIfPresent(Int.self, forKey: .workingDayEnd) ?? 22))
    showCompletedTasks = try values.decodeIfPresent(Bool.self, forKey: .showCompletedTasks) ?? false
    enabledWidgets =
      try values.decodeIfPresent([DashboardWidgetKind].self, forKey: .enabledWidgets) ?? [
        .momentum, .projectPulse,
      ]
    displayName = try values.decodeIfPresent(String.self, forKey: .displayName) ?? ""
    dashboardCalendarMode =
      try values.decodeIfPresent(CalendarViewMode.self, forKey: .dashboardCalendarMode) ?? .day
    focusDurationMinutes = min(
      180, max(1, try values.decodeIfPresent(Int.self, forKey: .focusDurationMinutes) ?? 25))
    if let layout = try values.decodeIfPresent([WidgetConfiguration].self, forKey: .widgetLayout) {
      widgetLayout = layout
    } else if enabledWidgets == [.momentum, .todayProgress, .upcoming, .projectPulse]
      && taskRailPosition == .trailing
    {
      widgetLayout = WidgetConfiguration.starterLayout
    } else {
      var layout = [WidgetConfiguration(kind: .dayFlow, columns: 2, rows: 2)]
      if taskRailPosition == .trailing { layout.append(WidgetConfiguration(kind: .tasks, rows: 2)) }
      layout += enabledWidgets.map { WidgetConfiguration(kind: $0) }
      if taskRailPosition == .bottom {
        layout.append(WidgetConfiguration(kind: .tasks, columns: 2))
      }
      widgetLayout = layout
    }
  }
}

struct Workspace: Codable, Equatable {
  var projects: [Project] = []
  var calendarEntries: [CalendarEntry] = []
  var tasks: [TaskItem] = []
  var preferences = UserPreferences()
  var scratchpad = "# Capture\n\nWrite freely. Use **Markdown**, lists, and ideas."
  var schemaVersion = 2
  var focusSession: FocusSession?
  var focusHistory: [FocusRecord]?
  var isDemo: Bool?
}

extension Calendar {
  static var struktur: Calendar {
    var calendar = Calendar.autoupdatingCurrent
    calendar.firstWeekday = 2
    return calendar
  }
}

extension Date {
  var startOfDay: Date { Calendar.struktur.startOfDay(for: self) }
  var endOfDay: Date {
    Calendar.struktur.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay) ?? self
  }
  var startOfWeek: Date {
    Calendar.struktur.dateInterval(of: .weekOfYear, for: self)?.start ?? startOfDay
  }
  func adding(days: Int) -> Date {
    Calendar.struktur.date(byAdding: .day, value: days, to: self) ?? self
  }
  func setting(hour: Int, minute: Int = 0) -> Date {
    Calendar.struktur.date(bySettingHour: hour, minute: minute, second: 0, of: self) ?? self
  }
}
