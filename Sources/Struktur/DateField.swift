import AppKit
import SwiftUI

/// Native date editing in the same quiet surface used by the app's other controls.
struct StrukturDateField: View {
  @EnvironmentObject private var store: WorkspaceStore
  let title: String
  @Binding var selection: Date
  var minimumDate: Date?
  var displayedComponents: DatePickerComponents
  var showsLabel: Bool
  @State private var showingCalendar = false
  @Environment(\.calendar) private var environmentCalendar
  @Environment(\.isEnabled) private var isEnabled

  private var calendar: Calendar {
    var value = environmentCalendar
    value.firstWeekday = store.preferences.weekStartsMonday ? 2 : 1
    return value
  }

  init(
    _ title: String, selection: Binding<Date>, minimumDate: Date? = nil,
    displayedComponents: DatePickerComponents = [.date, .hourAndMinute], showsLabel: Bool = true
  ) {
    self.title = title
    _selection = selection
    self.minimumDate = minimumDate
    self.displayedComponents = displayedComponents
    self.showsLabel = showsLabel
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if showsLabel {
        Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(StrukturTheme.muted)
          .fixedSize(horizontal: true, vertical: false)
      }
      HStack(spacing: 6) {
        NativeDateInput(
          selection: $selection, title: title, minimumDate: minimumDate,
          includesTime: displayedComponents.contains(.hourAndMinute), calendar: calendar)
        Button {
          showingCalendar = true
        } label: {
          Image(systemName: "calendar").font(.system(size: 12))
            .foregroundStyle(StrukturTheme.muted).frame(width: 24, height: 20)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
          .help("Choose \(title.lowercased())")
          .accessibilityLabel("Choose \(title.lowercased())")
          .popover(isPresented: $showingCalendar, arrowEdge: .bottom) { calendarPopover }
      }
      .padding(.horizontal, 10).padding(.vertical, 7)
      .background(StrukturTheme.surface, in: RoundedRectangle(cornerRadius: 9))
      .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(StrukturTheme.hairline) }
      .opacity(isEnabled ? 1 : 0.45)
    }.fixedSize()
  }

  private var calendarPopover: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(StrukturTheme.muted)
      DateSelectionCalendar(selection: $selection, minimumDate: minimumDate, calendar: calendar)
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

struct NativeDateInput: NSViewRepresentable {
  @Binding var selection: Date
  var title: String
  var minimumDate: Date?
  var includesTime: Bool
  var calendar: Calendar
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.locale) private var locale

  func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

  func makeNSView(context: Context) -> NSDatePicker {
    let picker = NSDatePicker()
    picker.datePickerStyle = .textField
    picker.isBezeled = false
    picker.isBordered = false
    picker.drawsBackground = false
    picker.font = .systemFont(ofSize: 12)
    picker.textColor = NSColor(StrukturTheme.ink)
    picker.datePickerMode = .single
    picker.presentsCalendarOverlay = false
    picker.target = context.coordinator
    picker.action = #selector(Coordinator.changed(_:))
    picker.setContentHuggingPriority(.required, for: .horizontal)
    picker.setContentCompressionResistancePriority(.required, for: .horizontal)
    return picker
  }

  func updateNSView(_ picker: NSDatePicker, context: Context) {
    context.coordinator.selection = $selection
    context.coordinator.minimumDate = minimumDate
    picker.datePickerElements = includesTime ? [.yearMonthDay, .hourMinute] : .yearMonthDay
    picker.calendar = calendar
    picker.timeZone = calendar.timeZone
    picker.locale = locale
    picker.minDate = minimumDate
    picker.isEnabled = isEnabled
    picker.setAccessibilityLabel(title)
    if picker.dateValue != selection { picker.dateValue = selection }
  }

  func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSDatePicker, context: Context) -> CGSize?
  {
    CGSize(width: max(100, nsView.intrinsicContentSize.width), height: 20)
  }

  @MainActor final class Coordinator: NSObject {
    var selection: Binding<Date>
    var minimumDate: Date?
    init(selection: Binding<Date>) { self.selection = selection }
    @objc func changed(_ sender: NSDatePicker) {
      let value = DateFieldValue.clamped(sender.dateValue, minimumDate: minimumDate)
      if value != sender.dateValue { sender.dateValue = value }
      selection.wrappedValue = value
    }
  }
}

enum DateFieldValue {
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
