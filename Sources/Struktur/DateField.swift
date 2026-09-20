import SwiftUI

/// A stable date trigger with all editing contained in one calendar-and-time popover.
struct StrukturDateField: View {
  @EnvironmentObject private var store: WorkspaceStore
  let title: String
  @Binding var selection: Date
  var minimumDate: Date?
  var displayedComponents: DatePickerComponents
  var showsLabel: Bool
  var fillsWidth: Bool
  @State private var showingCalendar = false
  @State private var isHovered = false
  @FocusState private var isFocused: Bool
  @Environment(\.calendar) private var environmentCalendar
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.locale) private var locale

  private var calendar: Calendar {
    var value = environmentCalendar
    value.firstWeekday = store.preferences.weekStartsMonday ? 2 : 1
    return value
  }

  init(
    _ title: String, selection: Binding<Date>, minimumDate: Date? = nil,
    displayedComponents: DatePickerComponents = [.date, .hourAndMinute], showsLabel: Bool = true,
    fillsWidth: Bool = false
  ) {
    self.title = title
    _selection = selection
    self.minimumDate = minimumDate
    self.displayedComponents = displayedComponents
    self.showsLabel = showsLabel
    self.fillsWidth = fillsWidth
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if showsLabel {
        Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(StrukturTheme.muted)
          .fixedSize(horizontal: true, vertical: false)
      }
      Button {
        showingCalendar.toggle()
      } label: {
        HStack(spacing: 10) {
          Text(
            DateFieldValue.displayText(
              for: selection, includesTime: includesTime, calendar: calendar, locale: locale)
          )
          .font(.system(size: 12, weight: .medium).monospacedDigit())
          .foregroundStyle(StrukturTheme.ink).lineLimit(1)
          Spacer(minLength: 2)
          Image(systemName: "calendar").font(.system(size: 11, weight: .medium))
            .foregroundStyle(showingCalendar ? StrukturTheme.ink : StrukturTheme.muted)
        }
        .frame(
          minWidth: includesTime ? 142 : 112, maxWidth: fillsWidth ? .infinity : nil,
          minHeight: 20, alignment: .leading)
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(
          isHovered || showingCalendar ? StrukturTheme.editingSurface : StrukturTheme.surface,
          in: RoundedRectangle(cornerRadius: 9)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 9).strokeBorder(
            isFocused || showingCalendar ? StrukturTheme.ink.opacity(0.24) : StrukturTheme.hairline)
        }
        .contentShape(RoundedRectangle(cornerRadius: 9))
      }
      .buttonStyle(.plain)
      .focusable().focusEffectDisabled().focused($isFocused)
      .onHover { isHovered = $0 }
      .opacity(isEnabled ? 1 : 0.45)
      .help("Choose \(title.lowercased())")
      .accessibilityLabel(title)
      .accessibilityValue(
        DateFieldValue.displayText(
          for: selection, includesTime: includesTime, calendar: calendar, locale: locale)
      )
      .accessibilityHint(includesTime ? "Opens a calendar and time editor" : "Opens a calendar")
      .popover(isPresented: $showingCalendar, arrowEdge: .bottom) { calendarPopover }
    }
    .fixedSize(horizontal: !fillsWidth, vertical: true)
  }

  private var calendarPopover: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(StrukturTheme.muted)
        Text(selection, format: .dateTime.weekday(.wide).day().month(.wide).year())
          .font(.strukturSerif(17, weight: .semibold)).foregroundStyle(StrukturTheme.ink)
      }
      DateSelectionCalendar(selection: $selection, minimumDate: minimumDate, calendar: calendar)
      if includesTime {
        Divider()
        TimeSelectionControl(
          selection: $selection, minimumDate: minimumDate, calendar: calendar)
      }
      HStack {
        Button("Today") {
          selection = DateFieldValue.selecting(
            day: Date(), preservingTimeOf: selection,
            minimumDate: minimumDate, calendar: calendar)
        }.buttonStyle(StrukturButtonStyle(compact: true))
          .disabled(
            minimumDate.map { calendar.startOfDay(for: $0) > calendar.startOfDay(for: Date()) }
              ?? false)
        Spacer()
        Button("Done") { showingCalendar = false }
          .buttonStyle(StrukturButtonStyle(primary: true, compact: true))
      }
    }.padding(18).frame(width: 300).background(StrukturTheme.surface)
  }

  private var includesTime: Bool { displayedComponents.contains(.hourAndMinute) }
}

/// The same open calendar styling as the sidebar, with larger hit targets and full date labels.
struct DateSelectionCalendar: View {
  @Binding var selection: Date
  var minimumDate: Date?
  var calendar: Calendar
  @State private var month: Date
  @FocusState private var focusedDay: Date?

  init(selection: Binding<Date>, minimumDate: Date?, calendar: Calendar) {
    _selection = selection
    self.minimumDate = minimumDate
    self.calendar = calendar
    _month = State(initialValue: selection.wrappedValue)
  }

  var body: some View {
    VStack(spacing: 12) {
      HStack(spacing: 4) {
        Text(month, format: .dateTime.month(.wide).year()).font(.strukturSerif(19))
          .foregroundStyle(StrukturTheme.ink).fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
        IconButton(icon: "chevron.left", label: "Previous month") { moveMonth(-1) }
        IconButton(icon: "chevron.right", label: "Next month") { moveMonth(1) }
      }
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 4)
      {
        ForEach(0..<7, id: \.self) { index in
          Text(calendar.veryShortStandaloneWeekdaySymbols[(calendar.firstWeekday - 1 + index) % 7])
            .font(.system(size: 10, weight: .medium)).foregroundStyle(StrukturTheme.muted)
            .frame(height: 20).accessibilityHidden(true)
        }
        ForEach(
          Array(DateFieldValue.monthDays(month, calendar: calendar).enumerated()), id: \.offset
        ) { _, day in
          if let day {
            let selected = calendar.isDate(day, inSameDayAs: selection)
            let unavailable = minimumDate.map { day < calendar.startOfDay(for: $0) } ?? false
            Button {
              select(day)
            } label: {
              Text(day, format: .dateTime.day()).font(
                .system(size: 11, weight: selected ? .semibold : .regular)
              )
              .frame(maxWidth: .infinity).frame(height: 30)
              .foregroundStyle(selected ? StrukturTheme.buttonText : StrukturTheme.ink)
              .background(
                selected ? StrukturTheme.darkButton : .clear, in: RoundedRectangle(cornerRadius: 8)
              )
              .overlay {
                if calendar.isDateInToday(day) && !selected {
                  RoundedRectangle(cornerRadius: 8).strokeBorder(StrukturTheme.hairline)
                }
              }
              .opacity(unavailable ? 0.3 : 1).contentShape(RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain).disabled(unavailable).focusable().focusEffectDisabled().focused(
              $focusedDay, equals: day
            )
            .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
            .accessibilityAddTraits(selected ? .isSelected : [])
          } else {
            Color.clear.frame(height: 30)
          }
        }
      }
    }
    .onChange(of: selection) { _, value in month = value }
    .onMoveCommand { direction in
      let step: Int
      switch direction {
      case .left: step = -1
      case .right: step = 1
      case .up: step = -7
      case .down: step = 7
      default: return
      }
      if let day = calendar.date(byAdding: .day, value: step, to: selection) { select(day) }
    }
  }

  private func select(_ day: Date) {
    selection = DateFieldValue.selecting(
      day: day, preservingTimeOf: selection,
      minimumDate: minimumDate, calendar: calendar)
    focusedDay = calendar.startOfDay(for: selection)
  }

  private func moveMonth(_ step: Int) {
    let start = calendar.dateInterval(of: .month, for: month)?.start ?? month
    month = calendar.date(byAdding: .month, value: step, to: start) ?? month
  }
}

struct TimeSelectionControl: View {
  @Binding var selection: Date
  var minimumDate: Date?
  var calendar: Calendar
  @Environment(\.locale) private var locale
  @State private var draft = ""
  @FocusState private var editingTime: Bool

  var body: some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Time").font(.system(size: 10, weight: .semibold)).foregroundStyle(
          StrukturTheme.muted)
        Text("15-minute steps").font(.system(size: 9)).foregroundStyle(
          StrukturTheme.muted)
      }
      Spacer(minLength: 8)
      timeButton("minus", label: "15 minutes earlier", minutes: -15)
      TextField("Time", text: $draft)
        .multilineTextAlignment(.center).font(.system(size: 12, weight: .medium).monospacedDigit())
        .strukturInput(compact: true).frame(width: 88).focused($editingTime)
        .accessibilityLabel("Time")
        .onSubmit { commitDraft() }
      timeButton("plus", label: "15 minutes later", minutes: 15)
    }
    .onAppear { synchronizeDraft() }
    .onChange(of: selection) { _, _ in if !editingTime { synchronizeDraft() } }
    .onChange(of: editingTime) { _, editing in if !editing { commitDraft() } }
  }

  private func timeButton(_ icon: String, label: String, minutes: Int) -> some View {
    Button {
      selection = DateFieldValue.adjustingTime(
        selection, byMinutes: minutes, minimumDate: minimumDate, calendar: calendar)
      synchronizeDraft()
    } label: {
      Image(systemName: icon).font(.system(size: 10, weight: .semibold)).frame(width: 25, height: 25)
        .background(StrukturTheme.editingSurface, in: RoundedRectangle(cornerRadius: 7))
        .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(StrukturTheme.hairline) }
    }
    .buttonStyle(.plain).accessibilityLabel(label)
  }

  private func synchronizeDraft() {
    draft = DateFieldValue.timeText(for: selection, calendar: calendar, locale: locale)
  }

  private func commitDraft() {
    guard
      let value = DateFieldValue.applyingTime(
        draft, to: selection, minimumDate: minimumDate, calendar: calendar, locale: locale)
    else {
      synchronizeDraft()
      return
    }
    selection = value
    synchronizeDraft()
  }
}

enum DateFieldValue {
  static func displayText(
    for date: Date, includesTime: Bool, calendar: Calendar, locale: Locale
  ) -> String {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = locale
    formatter.dateFormat = DateFormatter.dateFormat(
      fromTemplate: includesTime ? "yMdjm" : "yMd", options: 0, locale: locale)
    return formatter.string(from: date)
  }

  static func timeText(for date: Date, calendar: Calendar, locale: Locale) -> String {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = locale
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }

  static func applyingTime(
    _ text: String, to date: Date, minimumDate: Date?, calendar: Calendar, locale: Locale
  ) -> Date? {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = locale
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    formatter.isLenient = false
    formatter.defaultDate = calendar.startOfDay(for: date)
    guard let parsed = formatter.date(from: text) else { return nil }
    let time = calendar.dateComponents([.hour, .minute], from: parsed)
    return settingTime(
      hour: time.hour ?? 0, minute: time.minute ?? 0, on: date,
      minimumDate: minimumDate, calendar: calendar)
  }

  static func settingTime(
    hour: Int, minute: Int, on date: Date, minimumDate: Date?, calendar: Calendar
  ) -> Date {
    guard (0...23).contains(hour), (0...59).contains(minute) else {
      return clamped(date, minimumDate: minimumDate)
    }
    let value =
      calendar.date(
        bySettingHour: hour, minute: minute, second: 0, of: date,
        matchingPolicy: .nextTime, repeatedTimePolicy: .first) ?? date
    return clamped(value, minimumDate: minimumDate)
  }

  static func adjustingTime(
    _ date: Date, byMinutes minutes: Int, minimumDate: Date?, calendar: Calendar
  ) -> Date {
    clamped(
      calendar.date(byAdding: .minute, value: minutes, to: date) ?? date,
      minimumDate: minimumDate)
  }

  static func monthDays(_ month: Date, calendar: Calendar) -> [Date?] {
    guard let start = calendar.dateInterval(of: .month, for: month)?.start,
      let range = calendar.range(of: .day, in: .month, for: month)
    else { return [] }
    let blanks = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
    return Array(repeating: nil, count: blanks)
      + range.map {
        calendar.date(byAdding: .day, value: $0 - 1, to: start)
      }
  }

  static func clamped(_ date: Date, minimumDate: Date?) -> Date {
    max(date, minimumDate ?? .distantPast)
  }

  static func selecting(
    day: Date, preservingTimeOf original: Date, minimumDate: Date?, calendar: Calendar
  ) -> Date {
    let time = calendar.dateComponents([.hour, .minute, .second], from: original)
    let combined =
      calendar.date(
        bySettingHour: time.hour ?? 0, minute: time.minute ?? 0,
        second: time.second ?? 0, of: day, matchingPolicy: .nextTime, repeatedTimePolicy: .first)
      ?? day
    return clamped(combined, minimumDate: minimumDate)
  }
}
