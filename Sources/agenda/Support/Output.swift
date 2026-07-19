//
//  Output.swift
//  agenda
//
//  Rendering results as dense text or JSON.
//
//  Created by David Sherlock on 7/19/26.
//

import AgendaKit
import ArgumentParser
import Foundation

/// How results are printed.
///
/// Text is the default because JSON repeats every key on every row — across fifty
/// events that is a large fraction of the output spent on punctuation, which matters
/// when the reader is a model paying by the token. `--json` is there for piping.
enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
    case text
    case json
}

/// Flags shared by every command.
struct OutputOptions: ParsableArguments {

    @Flag(name: .long, help: "Emit JSON instead of text.")
    var json = false

    @Option(name: .long, help: "Compute dates in this zone, e.g. Asia/Tokyo. Defaults to the system zone.")
    var timezone: String?

    var format: OutputFormat { json ? .json : .text }

    /// Applies `--timezone` to the package and the output formatters.
    ///
    /// Must run before any date is parsed or rendered — `Agenda.calendar` decides what
    /// a bare `2026-07-19` means, so setting it afterwards would leave the parse in one
    /// zone and the display in another.
    func apply() throws {
        guard let timezone else { return }
        guard let zone = TimeZone(identifier: timezone) else {
            throw ValidationError("Unknown time zone \"\(timezone)\". Use an IANA name like Europe/London.")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        Agenda.calendar = calendar
        Output.applyTimeZone(zone)
    }
}

enum Output {

    /// Retargets every formatter at `zone`, so `--timezone` shows the remote wall
    /// clock rather than translating it back to the machine's.
    static func applyTimeZone(_ zone: TimeZone) {
        iso.timeZone = zone
        clock.timeZone = zone
        stamp.timeZone = zone
        day.timeZone = zone
    }

    /// ISO 8601 with local offset — unambiguous to parse, still readable.
    static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        return formatter
    }()

    /// Short local time, e.g. "2:30 PM".
    static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    /// Short local date and time.
    static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .medium
        return formatter
    }()

    static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    /// Prints `values` in `format`, or `empty` when there are none.
    ///
    /// The empty case prints to stdout and exits zero — "you have nothing on" is a
    /// successful answer, not a failure. Permission problems throw long before here.
    static func render<T: Encodable>(_ values: [T], format: OutputFormat,
                                     empty: String, line: (T) -> String) throws {
        switch format {
        case .json:
            print(try encode(values))
        case .text:
            guard !values.isEmpty else { print(empty); return }
            print(values.map(line).joined(separator: "\n"))
        }
    }

    // MARK: - Line formats

    static func line(_ event: AgendaEvent) -> String {
        var parts = [""]
        if event.isAllDay {
            parts[0] = "\(stamp.string(from: event.startsAt).prefix(12)) all day  \(event.title)"
        } else {
            parts[0] = "\(stamp.string(from: event.startsAt))–\(clock.string(from: event.endsAt))  \(event.title)"
        }
        if let location = event.location { parts.append("@ \(location)") }
        if let url = event.meetingURL { parts.append(url) }
        if !event.attendees.isEmpty { parts.append("\(event.attendees.count) attending") }
        if !event.alarms.isEmpty { parts.append("⏰ \(event.alarms.map(\.summary).joined(separator: ", "))") }
        if event.availability != .busy { parts.append(event.availability.rawValue) }
        if event.status == .canceled { parts.append("CANCELLED") }
        parts.append("[\(event.calendar)]")
        if let recurrence = event.recurrence { parts.append("↻ \(recurrence.summary)") }
        return parts.joined(separator: "  ") + "\n    \(event.id)"
    }

    /// Date only, no time — for all-day items, where a time would be invented.
    static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static func line(_ reminder: AgendaReminder) -> String {
        var parts = [reminder.isCompleted ? "[x]" : "[ ]", reminder.title]
        if let due = reminder.dueAt {
            // An all-day reminder has no time of day; rendering one shows "12:00 AM"
            // and reads as a midnight alert that was never set.
            let when = (reminder.isDueAllDay ? day : stamp).string(from: due)
            parts.append(reminder.isOverdue ? "overdue \(when)" : "due \(when)")
        }
        if let priority = reminder.priorityLabel { parts.append("!\(priority)") }
        if !reminder.alarms.isEmpty { parts.append("⏰ \(reminder.alarms.map(\.summary).joined(separator: ", "))") }
        parts.append("[\(reminder.list)]")
        if let recurrence = reminder.recurrence { parts.append("↻ \(recurrence.summary)") }
        return parts.joined(separator: "  ") + "\n    \(reminder.id)"
    }

    /// Renders a search hit, tagging which kind it is so a mixed list stays readable.
    static func line(_ result: SearchResult) -> String {
        switch result {
        case .event(let event):       return "event     " + line(event)
        case .reminder(let reminder): return "reminder  " + line(reminder)
        }
    }

    static func line(_ slot: FreeSlot) -> String {
        let hours = slot.minutes / 60
        let minutes = slot.minutes % 60
        let length = hours > 0 ? "\(hours)h\(minutes > 0 ? " \(minutes)m" : "")" : "\(minutes)m"
        return "\(stamp.string(from: slot.startsAt))–\(clock.string(from: slot.endsAt))  (\(length))"
    }

    static func line(_ calendar: AgendaCalendar) -> String {
        let flags = [
            calendar.isWritable ? nil : "read-only",
            calendar.isSubscribed ? "subscribed" : nil,
            calendar.isDefault ? "default" : nil,
            calendar.color
        ].compactMap { $0 }
        let suffix = flags.isEmpty ? "" : "  (\(flags.joined(separator: ", ")))"
        return "\(calendar.title)  [\(calendar.source)]\(suffix)\n    \(calendar.id)"
    }
}
