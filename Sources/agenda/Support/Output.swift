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
import CLIKit
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
enum Output {

    // THE FORMATTERS ARE SHARED AND MUTABLE, and Swift 6 is right to ask about that. They
    // are safe here for a reason that is about this program rather than about the type: one
    // command runs per process, on one thread, and `--timezone` retargets them once before
    // anything is parsed or rendered. Making them instance state would thread a formatter
    // through every line function to buy nothing.

    /// Retargets every formatter at `zone`, so `--timezone` shows the remote wall
    /// clock rather than translating it back to the machine's.
    static func applyTimeZone(_ zone: TimeZone) {
        iso.timeZone = zone
        clock.timeZone = zone
        stamp.timeZone = zone
        day.timeZone = zone
    }

    /// ISO 8601 with local offset — unambiguous to parse, still readable.
    nonisolated(unsafe) static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        return formatter
    }()

    /// Short local time, e.g. "2:30 PM".
    nonisolated(unsafe) static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    /// Short local date and time.
    nonisolated(unsafe) static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .medium
        return formatter
    }()



    // MARK: - Line formats

    static func line(_ event: AgendaEvent) -> String {
        // Title and location may be someone else's words (an invitation, a shared
        // calendar); `Untrusted.text` fences them when this run wraps.
        let title = Untrusted.text(event.title)
        var parts = [""]
        if event.isAllDay {
            // The date alone, from the date formatter: cutting the date-and-time
            // string at 12 characters left "8 Dec 2026 a" ("at") on one-digit days.
            parts[0] = "\(day.string(from: event.startsAt)) all day  \(title)"
        } else {
            parts[0] = "\(stamp.string(from: event.startsAt))–\(clock.string(from: event.endsAt))  \(title)"
        }
        // A location that is nothing but the call link would print the same URL twice.
        let link = event.videoCall?.url ?? event.meetingURL
        if let location = event.location,
           location.trimmingCharacters(in: .whitespacesAndNewlines) != link {
            parts.append("@ \(Untrusted.text(location))")
        }
        // A recognised call names its service, so "Zoom" reads at a glance; any other link
        // (the event's own URL field) still prints bare, as it always has.
        if let call = event.videoCall {
            parts.append("📹 \(call.service.displayName) \(call.url)")
        } else if let url = event.meetingURL {
            parts.append(url)
        }
        if !event.attendees.isEmpty { parts.append("\(event.attendees.count) attending") }
        if !event.alarms.isEmpty { parts.append("⏰ \(event.alarms.map(\.summary).joined(separator: ", "))") }
        if event.availability != .busy { parts.append(event.availability.rawValue) }
        if event.status == .canceled { parts.append("CANCELLED") }
        parts.append("[\(event.calendar)]")
        if let recurrence = event.recurrence { parts.append("↻ \(recurrence.summary)") }
        return parts.joined(separator: "  ") + "\n    \(event.id)"
    }

    /// Date only, no time — for all-day items, where a time would be invented.
    nonisolated(unsafe) static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static func line(_ reminder: AgendaReminder, details: ReminderStoreDetails? = nil) -> String {
        var parts = [reminder.isCompleted ? "[x]" : "[ ]", Untrusted.text(reminder.title)]
        // Tags and the section are authored text from the store, fenced like the title.
        if let tags = details?.tags, !tags.isEmpty {
            parts.append(Untrusted.text(tags.map { "#\($0)" }.joined(separator: " ")))
        }
        if let section = details?.section { parts.append("§ \(Untrusted.text(section))") }
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
    static func line(_ result: SearchResult, details: ReminderStoreDetails? = nil) -> String {
        switch result {
        case .event(let event):       return "event     " + line(event)
        case .reminder(let reminder): return "reminder  " + line(reminder, details: details)
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
