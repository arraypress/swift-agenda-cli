//
//  Agenda+RelativeDate.swift
//  SwiftAgenda
//
//  Plain-language date parsing — "tomorrow 9am", "next monday", "+2d".
//
//  Created by David Sherlock on 7/19/26.
//

import Foundation

extension Agenda {

    /// Parses a relative date phrase, or returns nil when the text is not one.
    ///
    /// Accepted shapes, all optionally followed by a time:
    ///
    /// | Input | Means |
    /// |---|---|
    /// | `now` | this instant |
    /// | `today`, `tomorrow`, `yesterday` | that day, at midnight unless a time is given |
    /// | `monday` … `sunday` (or `mon`, `tue`) | the next such day, today included |
    /// | `next monday` | the same, but always at least a week out |
    /// | `+2d`, `-1w`, `+90m` | offset from now, using ``duration(_:)``'s units |
    ///
    /// Times attach with a space: `tomorrow 9am`, `monday 14:30`, `today 5:15pm`.
    ///
    /// Callers get this for free through ``date(_:)``; it exists separately so the
    /// relative grammar can be tested without ISO parsing in the way.
    ///
    /// - Note: A bare weekday resolves to *today* when today is that weekday. Say
    ///   `next monday` for the following week — guessing between the two silently is
    ///   how an agent books a meeting seven days from where the user meant.
    static func relativeDate(_ raw: String) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty else { return nil }

        if text == "now" { return Date() }

        // "2d ago" exists because a leading `-` is read as an option name by most
        // argument parsers, making `--at -1w` unusable without `=` quoting.
        if text.hasSuffix(" ago") {
            let body = String(text.dropLast(" ago".count)).trimmingCharacters(in: .whitespaces)
            guard let seconds = try? duration(body) else { return nil }
            return Date().addingTimeInterval(-seconds)
        }

        // A leading sign means a pure offset from now, with no day/time split.
        if text.hasPrefix("+") || text.hasPrefix("-") {
            guard let seconds = try? duration(String(text.dropFirst())) else { return nil }
            return Date().addingTimeInterval(text.hasPrefix("-") ? -seconds : seconds)
        }

        let (dayPhrase, timePhrase) = splitDayAndTime(text)
        guard let day = resolveDay(dayPhrase) else { return nil }
        guard let timePhrase else { return calendar.startOfDay(for: day) }
        guard let time = parseTime(timePhrase) else { return nil }

        return calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day)
    }

    /// Splits `"tomorrow 9am"` into its day and time halves.
    ///
    /// The time is recognised by shape rather than position, so `next monday 14:00`
    /// keeps its two-word day phrase intact.
    private static func splitDayAndTime(_ text: String) -> (day: String, time: String?) {
        let words = text.split(separator: " ").map(String.init)
        guard words.count > 1, let last = words.last, looksLikeTime(last) else {
            return (text, nil)
        }
        return (words.dropLast().joined(separator: " "), last)
    }

    /// Whether a word could be a time of day.
    private static func looksLikeTime(_ word: String) -> Bool {
        word.range(of: #"^\d{1,2}(:\d{2})?(am|pm)?$"#, options: .regularExpression) != nil
    }

    /// Resolves a day phrase to some moment on that day, or nil if unrecognised.
    private static func resolveDay(_ phrase: String) -> Date? {
        let now = Date()
        switch phrase {
        case "today":     return now
        case "tomorrow":  return calendar.date(byAdding: .day, value: 1, to: now)
        case "yesterday": return calendar.date(byAdding: .day, value: -1, to: now)
        default: break
        }

        let wantsNextWeek = phrase.hasPrefix("next ")
        let name = wantsNextWeek ? String(phrase.dropFirst("next ".count)) : phrase
        guard let weekday = weekdayNumber(name) else { return nil }

        let today = calendar.component(.weekday, from: now)
        var ahead = (weekday - today + 7) % 7
        // `next monday` always means the occurrence after the upcoming one. On a
        // Sunday, `monday` is tomorrow and `next monday` is eight days out — without
        // the unconditional week, the two phrases would collapse to the same day and
        // "next" would mean nothing.
        if wantsNextWeek { ahead += 7 }
        return calendar.date(byAdding: .day, value: ahead, to: now)
    }

    /// Maps a weekday name or three-letter abbreviation to a `Calendar` weekday number.
    private static func weekdayNumber(_ name: String) -> Int? {
        let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        if let index = names.firstIndex(of: name) { return index + 1 }
        if name.count == 3, let index = names.firstIndex(where: { $0.hasPrefix(name) }) {
            return index + 1
        }
        return nil
    }

    /// Parses `9am`, `9:30`, `14:00`, `5:15pm` into hour and minute.
    ///
    /// Returns nil rather than clamping an out-of-range hour — `25:00` is a typo, and
    /// silently reading it as 1am would schedule something on the wrong day.
    private static func parseTime(_ text: String) -> (hour: Int, minute: Int)? {
        let pattern = #"^(\d{1,2})(?::(\d{2}))?(am|pm)?$"#
        guard let match = text.range(of: pattern, options: .regularExpression) else { return nil }
        let body = String(text[match])

        let meridiem = body.hasSuffix("am") ? "am" : (body.hasSuffix("pm") ? "pm" : nil)
        let digits = body.replacingOccurrences(of: "am", with: "").replacingOccurrences(of: "pm", with: "")
        let parts = digits.split(separator: ":").map(String.init)

        guard var hour = Int(parts[0]) else { return nil }
        let minute = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        guard (0...59).contains(minute) else { return nil }

        switch meridiem {
        case "am": guard (1...12).contains(hour) else { return nil }; if hour == 12 { hour = 0 }
        case "pm": guard (1...12).contains(hour) else { return nil }; if hour != 12 { hour += 12 }
        default:   guard (0...23).contains(hour) else { return nil }
        }
        return (hour, minute)
    }
}
