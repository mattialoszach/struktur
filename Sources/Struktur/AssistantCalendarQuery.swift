import Foundation

/// Common calendar reads don't need a generative model to choose a date or invent an answer.
/// Unrecognized/compound questions continue through the model; ambiguous date reads ask for clarity.
struct AssistantCalendarQuery: Sendable {
  var kind: ItemKind?
  var window: DateInterval?
  var clarification: String?

  static func resolve(prompt: String, history: [AssistantTurn], context: AssistantContext) throws -> Self? {
    let text = prompt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    func matches(_ pattern: String, _ value: String = "") -> Bool {
      (value.isEmpty ? text : value).range(of: pattern, options: .regularExpression) != nil
    }
    // Don't intercept actions, explanations, filtered searches, or multi-part requests.
    guard !matches(#"\b(create|add|book|schedule a|plan|move|reschedule|cancel|delete|remove|summarize|explain|why|with|except|excluding|tasks|deadlines|notes)\b"#),
      !matches(#"\bnext (meeting|event|appointment)\b"#),
      !matches(#"^what (is|are|does|do)\b"#),
      !matches(#"\b(at|before|after|since)\s+\d|\d:\d|\b(morning|afternoon|evening|tonight)\b"#),
      !(matches(#"\babout\b"#) && !matches(#"^(what|how) about\b"#)) else { return nil }
    let nouns = #"\b(meetings|events|appointments|calendar|schedule)\b"#
    let isRead = matches(#"^(what|which|show|list|do i have|are there|when are|can you (show|list))\b"#) && matches(nouns)
    var kind: ItemKind? = matches(#"\bmeetings\b"#) ? .meeting : nil
    if !isRead {
      guard matches(#"^(and\b|on\b|how about\b|what about\b|tomorrow\b|today\b|(?:mon|tue|wed|thu|fri|sat|sun))"#),
        let previous = history.lastIndex(where: { $0.role == "user" }),
        let inherited = try resolve(prompt: history[previous].text, history: Array(history[..<previous]), context: context) else { return nil }
      let words = Set(text.components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty })
      let allowed: Set<String> = ["and", "on", "how", "what", "about", "instead", "the", "day", "after", "today", "tomorrow", "yesterday", "selected", "this", "next", "week", "mon", "monday", "tue", "tues", "tuesday", "wed", "wednesday", "thu", "thurs", "thursday", "fri", "friday", "sat", "saturday", "sun", "sunday", "jan", "january", "feb", "february", "mar", "march", "apr", "april", "may", "jun", "june", "jul", "july", "aug", "august", "sep", "sept", "september", "oct", "october", "nov", "november", "dec", "december", "st", "nd", "rd", "th"]
      guard words.isSubset(of: allowed) else { return nil }
      kind = inherited.kind
    }
    return try dates(prompt: prompt, kind: kind, context: context)
  }

  /// Also used after model routing: a missing model date must not override an explicit user date.
  static func dates(prompt: String, kind: ItemKind? = nil, context: AssistantContext) throws -> Self {
    let text = prompt.lowercased()
    func matches(_ pattern: String) -> Bool { text.range(of: pattern, options: .regularExpression) != nil }
    guard let snapshot = try JSONSerialization.jsonObject(with: Data(context.json.utf8)) as? [String: Any],
      let now = try AssistantWireReply.date(snapshot["now"] as? String),
      let selected = try AssistantWireReply.date(snapshot["selectedDate"] as? String),
      let zoneName = snapshot["timeZone"] as? String, let zone = TimeZone(identifier: zoneName) else {
      return Self(kind: kind, clarification: "I couldn't determine the current date. Please try again.")
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    calendar.firstWeekday = 2
    let today = calendar.startOfDay(for: now)
    let weekdays = ["sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7]
    let weekdayPattern = #"\b(mon(?:day)?|tue(?:s(?:day)?)?|wed(?:nesday)?|thu(?:rs(?:day)?)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?)\.?\b"#
    let weekday = captures(weekdayPattern, in: text).flatMap { weekdays[String($0[1].prefix(3))] }
    func day(_ start: Date) -> Self {
      if let weekday, calendar.component(.weekday, from: start) != weekday { return clarify() }
      return Self(kind: kind, window: DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start)!))
    }
    func clarify() -> Self {
      Self(kind: kind, clarification: "Which date or week do you mean? You can say tomorrow, Tuesday 22 September, or 2026-09-22.")
    }
    // Don't silently answer only the first date in a compound range.
    if matches(#"\b(between|through|until|from|all|every)\b"#)
      || matches(#"\b(?:tomorrow|today|monday|tuesday|wednesday|thursday|friday|saturday|sunday|\d)\s+(?:and|to|or|-)\b"#) { return clarify() }

    let iso = #"\b(\d{4})-(\d{2})-(\d{2})\b"#
    if let parts = captures(iso, in: text) {
      guard let date = date(year: Int(parts[1])!, month: Int(parts[2])!, day: Int(parts[3])!, calendar: calendar) else { return clarify() }
      return day(date)
    }
    if matches(#"\bday after tomorrow\b"#) { return day(calendar.date(byAdding: .day, value: 2, to: today)!) }
    if matches(#"\btomorrow\b"#) { return day(calendar.date(byAdding: .day, value: 1, to: today)!) }
    if matches(#"\byesterday\b"#) { return day(calendar.date(byAdding: .day, value: -1, to: today)!) }
    if matches(#"\btoday\b"#) { return day(today) }
    if matches(#"\bselected day\b"#) { return day(calendar.startOfDay(for: selected)) }
    if matches(#"\b(this|next) week\b"#) {
      let offset = matches(#"\bnext week\b"#) ? 7 : 0
      let currentWeekday = calendar.component(.weekday, from: today)
      let start = calendar.date(byAdding: .day, value: -((currentWeekday + 5) % 7) + offset, to: today)!
      if let weekday { return day(calendar.date(byAdding: .day, value: (weekday + 5) % 7, to: start)!) }
      return Self(kind: kind, window: DateInterval(start: start, end: calendar.date(byAdding: .day, value: 7, to: start)!))
    }
    let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
      "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]
    let monthPattern = #"(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)"#
    var number: Int?
    var month: Int?
    var year = calendar.component(.year, from: today)
    if let parts = captures(#"\b(\d{1,2})(?:st|nd|rd|th)?\s+"# + monthPattern + #"(?:\s+(\d{4}))?\b"#, in: text) {
      number = Int(parts[1]); month = months[String(parts[2].prefix(3))]
      if !parts[3].isEmpty { year = Int(parts[3])! }
    } else if let parts = captures(#"\b"# + monthPattern + #"\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(\d{4}))?\b"#, in: text) {
      month = months[String(parts[1].prefix(3))]; number = Int(parts[2])
      if !parts[3].isEmpty { year = Int(parts[3])! }
    } else if let parts = captures(weekdayPattern + #"\s+(\d{1,2})(?:st|nd|rd|th)?\b"#, in: text) {
      number = Int(parts[2]); month = calendar.component(.month, from: today)
    }
    if let number, let month {
      guard let date = date(year: year, month: month, day: number, calendar: calendar),
        weekday == nil || calendar.component(.weekday, from: date) == weekday else { return clarify() }
      return day(date)
    }
    // Unknown numeric dates and modifiers must not become the selected day or a different weekday.
    if matches(#"\d|\b(month|year|last|weekend|morning|afternoon|evening|tonight)\b"#) { return clarify() }
    if let weekday {
      if matches(#"\bthis\b"#) {
        let offset = (weekday + 5) % 7 - (calendar.component(.weekday, from: today) + 5) % 7
        return day(calendar.date(byAdding: .day, value: offset, to: today)!)
      }
      var offset = (weekday - calendar.component(.weekday, from: today) + 7) % 7
      if offset == 0 && matches(#"\bnext\b"#) { offset = 7 }
      return day(calendar.date(byAdding: .day, value: offset, to: today)!)
    }
    if matches(#"\b(on|next|this|in|after|before)\b"#) { return clarify() }
    return day(calendar.startOfDay(for: selected))
  }

  var request: AssistantContextRequest? {
    guard let window else { return nil }
    let format = ISO8601DateFormatter()
    return AssistantContextRequest(schedule: true, startDate: format.string(from: window.start),
      endDate: format.string(from: window.end), calendarOnly: true, eventKind: kind)
  }

  func reply(context: AssistantContext) throws -> AssistantReply {
    if let clarification { return AssistantReply(message: clarification, actions: []) }
    guard let window,
      let json = try JSONSerialization.jsonObject(with: Data(context.json.utf8)) as? [String: Any],
      let fetched = json["window"] as? [String: String],
      try AssistantWireReply.date(fetched["start"]) == window.start,
      try AssistantWireReply.date(fetched["endExclusive"]) == window.end,
      let events = json["events"] as? [[String: Any]] else {
      throw AssistantFailure("I couldn't verify the requested calendar range. Please try again.")
    }
    let zone = (json["timeZone"] as? String).flatMap(TimeZone.init(identifier:)) ?? .current
    let date = DateFormatter()
    date.locale = .autoupdatingCurrent; date.timeZone = zone; date.dateStyle = .full
    let time = DateFormatter()
    time.locale = .autoupdatingCurrent; time.timeZone = zone; time.timeStyle = .short
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
    let multipleDays = !calendar.isDate(window.start, inSameDayAs: window.end.addingTimeInterval(-1))
    let heading = multipleDays ? "\(date.string(from: window.start)) – \(date.string(from: window.end.addingTimeInterval(-1)))" : date.string(from: window.start)
    let noun = kind == .meeting ? "meetings" : "calendar blocks"
    let lines = try events.compactMap { row -> String? in
      guard kind == nil || row["kind"] as? String == kind?.rawValue,
        let start = try AssistantWireReply.date(row["start"] as? String),
        let end = try AssistantWireReply.date(row["end"] as? String), start < window.end, end > window.start else { return nil }
      let title = row["title"] as? String ?? "Untitled block"
      let allDay = row["allDay"] as? Bool == true
      let spansDays = !calendar.isDate(start, inSameDayAs: end.addingTimeInterval(-1))
      let startLabel = multipleDays || spansDays ? date.string(from: start) + " · " : ""
      let endLabel = spansDays ? date.string(from: allDay ? end.addingTimeInterval(-1) : end) + " · " : ""
      let duration = allDay ? (spansDays ? "\(startLabel)→ \(endLabel)all day" : "\(startLabel)All day")
        : "\(startLabel)\(time.string(from: start)) – \(endLabel)\(time.string(from: end))"
      return "• \(title) · \(duration)"
    }
    let omitted = (json["omitted"] as? [String: Int])?["events"] ?? 0
    let body = lines.isEmpty
      ? (omitted > 0 ? "No matching \(noun) in the retrieved portion of your calendar." : "No \(noun) in Struktur for this date range.")
      : lines.joined(separator: "\n")
    let limited = omitted > 0 ? "\n\n\(omitted) more \(noun) were omitted. Open Calendar for the complete view." : ""
    return AssistantReply(message: heading + " · " + zone.identifier + "\n\n" + body + limited, actions: [])
  }

  private static func captures(_ pattern: String, in text: String) -> [String]? {
    guard let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
    return (0..<match.numberOfRanges).map { index in
      Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
    }
  }

  private static func date(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
    guard (1970...2200).contains(year), let value = calendar.date(from: DateComponents(year: year, month: month, day: day)),
      calendar.component(.year, from: value) == year, calendar.component(.month, from: value) == month,
      calendar.component(.day, from: value) == day else { return nil }
    return value
  }
}
