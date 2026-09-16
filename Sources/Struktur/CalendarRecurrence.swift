import CryptoKit
import Foundation

enum RepeatFrequency: String, Codable, CaseIterable, Identifiable {
  case daily, weekly, monthly
  var id: String { rawValue }
  var title: String { rawValue.capitalized }
}

struct CalendarRecurrence: Codable, Hashable {
  var frequency: RepeatFrequency = .weekly
  var interval = 1
  /// Calendar weekday numbers (Sunday = 1). An empty selection uses the start weekday.
  var weekdays: [Int] = []
  var until: Date?
  var count: Int?
  var timeZoneIdentifier = TimeZone.current.identifier

  var calendar: Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
    value.firstWeekday = 2
    return value
  }

  func start(at index: Int, from anchor: Date) -> Date? {
    guard index >= 0, interval > 0, index <= 1_000_000,
      count.map({ index < $0 }) ?? true
    else { return nil }
    let calendar = calendar
    let date: Date?
    switch frequency {
    case .daily:
      date = calendar.date(byAdding: .day, value: index * interval, to: anchor)
    case .monthly:
      date = calendar.date(byAdding: .month, value: index * interval, to: anchor)
    case .weekly:
      let anchorOffset = (calendar.component(.weekday, from: anchor) + 5) % 7
      let offsets = Set(weekdays.isEmpty ? [anchorOffset] : weekdays.map { ($0 + 5) % 7 }).sorted()
      let firstWeek = offsets.filter { $0 >= anchorOffset }
      let days: Int
      if index < firstWeek.count {
        days = firstWeek[index] - anchorOffset
      } else {
        let remaining = index - firstWeek.count
        days =
          (remaining / offsets.count + 1) * interval * 7 + offsets[remaining % offsets.count]
          - anchorOffset
      }
      date = calendar.date(byAdding: .day, value: days, to: anchor)
    }
    guard let date else { return nil }
    if let until, calendar.startOfDay(for: date) > calendar.startOfDay(for: until) { return nil }
    return date
  }

  func firstIndex(near date: Date, anchor: Date) -> Int {
    let calendar = calendar
    let days = max(0, calendar.dateComponents([.day], from: anchor, to: date).day ?? 0)
    switch frequency {
    case .daily: return max(0, days / interval - 2)
    case .monthly:
      return max(
        0, (calendar.dateComponents([.month], from: anchor, to: date).month ?? 0) / interval - 2)
    case .weekly:
      return max(0, (days / (7 * interval) - 2) * max(1, Set(weekdays).count))
    }
  }
}

enum CalendarEditScope: String, CaseIterable, Identifiable {
  case occurrence, series
  var id: String { rawValue }
  var title: String { self == .occurrence ? "Only this occurrence" : "Entire series" }
}

extension CalendarEntry {
  /// Encodes the occurrence index into a series-specific UUID, allowing direct UID lookup.
  func occurrenceID(at index: Int) -> UUID {
    let hash = Array(SHA256.hash(data: Data(id.uuidString.utf8)).prefix(12))
    let number = UInt32(clamping: index)
    let bytes =
      hash + [
        UInt8((number >> 24) & 255), UInt8((number >> 16) & 255),
        UInt8((number >> 8) & 255), UInt8(number & 255),
      ]
    return UUID(
      uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
      ))
  }

  func index(for occurrenceID: UUID) -> Int? {
    var raw = occurrenceID.uuid
    let bytes = withUnsafeBytes(of: &raw) { Array($0) }
    let prefix = Array(SHA256.hash(data: Data(id.uuidString.utf8)).prefix(12))
    guard Array(bytes.prefix(12)) == prefix else { return nil }
    return bytes.suffix(4).reduce(0) { ($0 << 8) | Int($1) }
  }

  func occurrence(at index: Int) -> CalendarEntry? {
    guard let rule = recurrence, !(excludedOccurrences ?? []).contains(index),
      let occurrenceStart = rule.start(at: index, from: start)
    else { return nil }
    var result = self
    result.id = occurrenceID(at: index)
    result.seriesID = id
    result.occurrenceIndex = index
    result.start = occurrenceStart
    if isAllDay {
      let days = max(1, rule.calendar.dateComponents([.day], from: start, to: end).day ?? 1)
      result.end =
        rule.calendar.date(byAdding: .day, value: days, to: occurrenceStart) ?? occurrenceStart
    } else {
      result.end = occurrenceStart.addingTimeInterval(end.timeIntervalSince(start))
    }
    result.recurrence = nil
    result.excludedOccurrences = nil
    result.externalIdentifier = nil
    return result
  }
}

extension WorkspaceStore {
  /// Finds the next active or future block without an arbitrary date horizon.
  func nextCalendarEntry(after date: Date, projectID: UUID? = nil) -> CalendarEntry? {
    let overrides = Set(entries.filter { $0.seriesID != nil }.map(\.id))
    var candidates = entries.filter {
      $0.recurrence == nil && $0.end > date && (projectID == nil || $0.projectID == projectID)
    }
    for master in entries
    where master.recurrence != nil
      && (projectID == nil || master.projectID == projectID)
    {
      guard let rule = master.recurrence else { continue }
      var index = rule.firstIndex(
        near: date.addingTimeInterval(-master.end.timeIntervalSince(master.start)),
        anchor: master.start)
      while rule.start(at: index, from: master.start) != nil {
        defer { index += 1 }
        guard var occurrence = master.occurrence(at: index),
          !overrides.contains(occurrence.id), occurrence.end > date
        else { continue }
        occurrence.externalIdentifier = workspace.appleEventLinks?[occurrence.id.uuidString]
        candidates.append(occurrence)
        break
      }
    }
    return candidates.min {
      $0.start == $1.start ? $0.id.uuidString < $1.id.uuidString : $0.start < $1.start
    }
  }

  func calendarEntries(in window: DateInterval, projectID: UUID? = nil) -> [CalendarEntry] {
    let overrides = Dictionary(
      entries.filter { $0.seriesID != nil }.map { ($0.id, $0) },
      uniquingKeysWith: { _, last in last })
    var result = entries.filter {
      $0.recurrence == nil && $0.start < window.end && $0.end > window.start
    }
    for master in entries where master.recurrence != nil && master.seriesID == nil {
      guard let rule = master.recurrence else { continue }
      let earliest = window.start.addingTimeInterval(
        -max(0, master.end.timeIntervalSince(master.start)))
      var index = rule.firstIndex(near: earliest, anchor: master.start)
      while let start = rule.start(at: index, from: master.start), start < window.end {
        if var occurrence = master.occurrence(at: index),
          overrides[occurrence.id] == nil, occurrence.end > window.start
        {
          occurrence.externalIdentifier = workspace.appleEventLinks?[occurrence.id.uuidString]
          result.append(occurrence)
        }
        index += 1
      }
    }
    return result.filter { projectID == nil || $0.projectID == projectID }
      .sorted { $0.start == $1.start ? $0.id.uuidString < $1.id.uuidString : $0.start < $1.start }
  }

  func calendarEntries(on day: Date, projectID: UUID? = nil) -> [CalendarEntry] {
    calendarEntries(
      in: DateInterval(start: day.startOfDay, end: day.startOfDay.adding(days: 1)),
      projectID: projectID)
  }

  func resolveEntry(_ id: UUID) -> CalendarEntry? {
    if let saved = entries.first(where: { $0.id == id }) {
      return saved
    }
    for master in entries where master.recurrence != nil {
      if let index = master.index(for: id) {
        var occurrence = master.occurrence(at: index)
        occurrence?.externalIdentifier = workspace.appleEventLinks?[id.uuidString]
        return occurrence
      }
    }
    return nil
  }
}
