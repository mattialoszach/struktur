import AppKit
import SwiftUI
import XCTest

@testable import Struktur

@MainActor
final class ControlLayoutTests: XCTestCase {
  private let taskLabels = ["Today", "Upcoming", "Open", "Completed"]

  private func sizes(_ labels: [String]) -> [CGSize] {
    labels.map {
      let text = ($0 as NSString).size(withAttributes: [
        .font: NSFont.systemFont(ofSize: 11, weight: .medium)
      ])
      return CGSize(width: ceil(text.width) + 18, height: ceil(text.height) + 14)
    }
  }

  func testTaskFiltersReserveEnoughWidthForEveryCompleteLabel() {
    let measured = sizes(taskLabels)
    // The 300-point toolbar control includes three points of outer padding on each side.
    let frames = OptionLayoutGeometry.frames(width: 294, sizes: measured)
    XCTAssertEqual(Set(frames.map(\.minY)), [0])
    XCTAssertEqual(frames.last?.maxX ?? 0, 294, accuracy: 0.001)
    for (index, frame) in frames.enumerated() {
      XCTAssertGreaterThanOrEqual(frame.width, measured[index].width)
    }
    XCTAssertGreaterThan(frames[3].width, frames[2].width)
  }

  func testConstrainedOptionsWrapWithoutClippingOrOverlapping() {
    let measured = sizes(taskLabels + ["An unusually long option"])
    for width: CGFloat in [0, 90, 150, 200, 300, 600] {
      let frames = OptionLayoutGeometry.frames(width: width, sizes: measured)
      let available = max(width, measured.map(\.width).max() ?? 0)
      for (index, frame) in frames.enumerated() {
        XCTAssertGreaterThanOrEqual(frame.width, measured[index].width)
        XCTAssertGreaterThanOrEqual(frame.height, measured[index].height)
        XCTAssertLessThanOrEqual(frame.maxX, available + 0.001)
        for other in frames.dropFirst(index + 1) { XCTAssertFalse(frame.intersects(other)) }
      }
      if width == 200 { XCTAssertGreaterThan(frames.last?.minY ?? 0, 0) }
    }
  }

  func testUnconstrainedAndEmptyOptionsHaveFiniteNaturalSizes() {
    XCTAssertTrue(OptionLayoutGeometry.frames(width: 300, sizes: []).isEmpty)
    let measured = sizes(["Active", "Archived"])
    let frames = OptionLayoutGeometry.frames(width: nil, sizes: measured)
    XCTAssertEqual(frames.map(\.width), measured.map(\.width))
    XCTAssertEqual(frames, OptionLayoutGeometry.frames(width: .infinity, sizes: measured))
    XCTAssertEqual(frames, OptionLayoutGeometry.frames(width: .nan, sizes: measured))
  }

  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
    return calendar
  }

  private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0)
    -> Date
  {
    calendar.date(
      from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
  }

  func testChoosingCalendarDayPreservesTheEnteredTime() {
    let original = date(2026, 9, 17, 17, 45)
    let result = DateFieldValue.selecting(
      day: date(2026, 10, 3), preservingTimeOf: original,
      minimumDate: nil, calendar: calendar)
    XCTAssertEqual(result, date(2026, 10, 3, 17, 45))
    XCTAssertEqual(
      DateFieldValue.selecting(
        day: date(2028, 2, 29), preservingTimeOf: original,
        minimumDate: nil, calendar: calendar), date(2028, 2, 29, 17, 45))
  }

  func testCalendarGridRespectsWeekStartAndLeapYears() {
    var calendar = calendar
    for firstWeekday in [1, 2] {
      calendar.firstWeekday = firstWeekday
      let days = DateFieldValue.monthDays(date(2028, 2, 29), calendar: calendar)
      XCTAssertEqual(days.compactMap { $0 }.count, 29)
      XCTAssertEqual(days.compactMap { $0 }.last, date(2028, 2, 29))
      // February 2028 starts on Tuesday: two blanks for Sunday, one for Monday.
      XCTAssertEqual(days.prefix { $0 == nil }.count, firstWeekday == 1 ? 2 : 1)
    }
  }

  func testCalendarGridKeepsEveryDateAtLocalMidnightAcrossDST() {
    for month in [3, 10] {
      let days = DateFieldValue.monthDays(date(2026, month, 1), calendar: calendar).compactMap {
        $0
      }
      XCTAssertEqual(days.count, 31)
      XCTAssertEqual(days.map { calendar.component(.day, from: $0) }, Array(1...31))
      XCTAssertTrue(days.allSatisfy { calendar.component(.hour, from: $0) == 0 })
    }
  }

  func testDaySelectionRetainsWallClockTimeAcrossDaylightSavingBoundaries() {
    for (month, day) in [(3, 29), (10, 25)] {
      XCTAssertEqual(
        DateFieldValue.selecting(
          day: date(2026, month, day),
          preservingTimeOf: date(2026, month, day - 1, 17, 45), minimumDate: nil, calendar: calendar
        ),
        date(2026, month, day, 17, 45))
    }
    // A nonexistent spring-forward time advances to the next valid time, on the chosen day.
    XCTAssertEqual(
      DateFieldValue.selecting(
        day: date(2026, 3, 29),
        preservingTimeOf: date(2026, 3, 28, 2, 30), minimumDate: nil, calendar: calendar),
      date(2026, 3, 29, 3))
  }

  func testDateSelectionHonorsMinimumDayAndTime() {
    let minimum = date(2026, 9, 17, 16)
    XCTAssertEqual(DateFieldValue.clamped(date(2026, 9, 16), minimumDate: minimum), minimum)
    XCTAssertEqual(
      DateFieldValue.selecting(
        day: date(2026, 9, 17),
        preservingTimeOf: date(2026, 9, 16, 9), minimumDate: minimum, calendar: calendar), minimum)
    let later = date(2026, 9, 18, 9)
    XCTAssertEqual(DateFieldValue.clamped(later, minimumDate: minimum), later)
    XCTAssertEqual(DateFieldValue.clamped(later, minimumDate: nil), later)
  }

  func testNativeDateEditsUpdateTheBindingAndRejectEarlierValues() {
    var selected = date(2026, 9, 17, 9)
    let binding = Binding(get: { selected }, set: { selected = $0 })
    let coordinator = NativeDateInput.Coordinator(selection: binding)
    let picker = NSDatePicker()
    picker.dateValue = date(2026, 9, 20, 17, 45)
    coordinator.changed(picker)
    XCTAssertEqual(selected, picker.dateValue)
    coordinator.minimumDate = date(2026, 9, 18, 10)
    picker.dateValue = date(2026, 9, 16)
    coordinator.changed(picker)
    XCTAssertEqual(selected, coordinator.minimumDate)
    XCTAssertEqual(picker.dateValue, selected)
  }
}
