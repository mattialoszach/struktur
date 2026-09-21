import Foundation

/// Ground a single event's explicitly named weekday/week before showing its draft.
/// Other date forms and requests with multiple days stay with the normal draft flow.
struct AssistantEventDate {
  let day: Date
  let calendar: Calendar

  static func resolve(prompt: String, context: AssistantContext) throws -> Self? {
    let weekday = #"(?:mon(?:day)?|tue(?:s(?:day)?)?|wed(?:nesday)?|thu(?:rs(?:day)?)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?)"#
    let pattern = #"\b(?:(?:this|next) week(?: on)?\s+"# + weekday
      + "|" + weekday + #"(?: of)? (?:this|next) week)\b"#
    let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    let matches = regex.matches(in: prompt, range: NSRange(prompt.startIndex..., in: prompt))
    guard matches.count == 1, let range = Range(matches[0].range, in: prompt) else { return nil }
    let rest = prompt.replacingCharacters(in: range, with: "")
    // Don't override multi-date, contradictory, recurring, or explicitly numbered dates.
    let otherDates = #"\b(?:"# + weekday + #"|today|tomorrow|yesterday|week|daily|every|until|through|days|nights|january|february|march|april|may|june|july|august|september|october|november|december)\b|\d{4}-\d{2}|\d{1,2}[/.]\d{1,2}"#
    guard rest.range(of: otherDates, options: [.regularExpression, .caseInsensitive]) == nil else { return nil }
    let resolved = try AssistantCalendarQuery.dates(prompt: String(prompt[range]), context: context)
    if let clarification = resolved.clarification { throw AssistantFailure(clarification) }
    guard let day = resolved.window?.start,
      let json = try JSONSerialization.jsonObject(with: Data(context.json.utf8)) as? [String: Any],
      let zone = (json["timeZone"] as? String).flatMap(TimeZone.init(identifier:)) else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return Self(day: day, calendar: calendar)
  }

  var guidance: String {
    let format = DateFormatter()
    format.calendar = calendar; format.timeZone = calendar.timeZone; format.locale = Locale(identifier: "en_US_POSIX")
    format.dateFormat = "yyyy-MM-dd EEEE"
    return "\nApp-resolved event day: \(format.string(from: day)) in \(calendar.timeZone.identifier). Use this day with the user's requested times."
  }

  func ground(_ actions: [AssistantAction]) throws -> [AssistantAction] {
    guard actions.count == 1, var event = actions.first, event.kind == .event,
      let start = event.start, let end = event.end else { return actions }
    let overnight = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    guard (0...1).contains(overnight), end > start else {
      throw AssistantFailure("I couldn't verify the event's date and duration. Please specify its start and end again.")
    }
    func move(_ time: Date, to day: Date) throws -> Date {
      let clock = calendar.dateComponents([.hour, .minute, .second], from: time)
      let first = calendar.date(bySettingHour: clock.hour!, minute: clock.minute!, second: clock.second!, of: day,
        matchingPolicy: .strict, repeatedTimePolicy: .first)
      let last = calendar.date(bySettingHour: clock.hour!, minute: clock.minute!, second: clock.second!, of: day,
        matchingPolicy: .strict, repeatedTimePolicy: .last)
      guard let first, first == last, calendar.isDate(first, inSameDayAs: day),
        calendar.dateComponents([.hour, .minute, .second], from: first) == clock else {
        throw AssistantFailure("That time is missing or occurs twice when the clocks change. Please choose an unambiguous time.")
      }
      return first
    }
    event.start = try move(start, to: day)
    event.end = try move(end, to: calendar.date(byAdding: .day, value: overnight, to: day)!)
    return [event]
  }
}
