//
//  AgendaError.swift
//  SwiftAgenda
//
//  Failures that carry the fix, not just the symptom.
//
//  Created by David Sherlock on 7/19/26.
//

import EventKit
import Foundation

/// Everything `Agenda` can fail with.
///
/// Each case renders a message naming the next action. An agent driving this tool
/// recovers from "run `agenda doctor`" and cannot recover from "operation failed",
/// so no case is allowed to be vague.
public enum AgendaError: LocalizedError, Equatable {

    /// The entity type is not authorized. Distinct from an empty result on purpose.
    case accessDenied(EKEntityType)

    /// A `--calendar` value matched no calendar by title or identifier.
    case unknownCalendar(String)

    /// No event or reminder exists with the given identifier.
    case notFound(String)

    /// A duration string could not be parsed (see ``Agenda/duration(_:)``).
    case badDuration(String)

    /// A date string could not be parsed.
    case badDate(String)

    /// A recurring item was mutated without an explicit span.
    ///
    /// Defaulting this is how an agent deletes four years of a weekly standup while
    /// believing it removed one instance.
    case spanRequired(String)

    /// EventKit rejected a save or delete.
    case storeFailure(String)

    /// A time-zone name matched no IANA zone.
    case badTimeZone(String)

    /// A caller-supplied argument was missing or unusable.
    ///
    /// Distinct from the parsing cases so a wrong argument does not surface as a
    /// nonsense date error — nesting one message inside another produces text like
    /// `Could not read "Unknown time zone" as a date`, which tells a reader nothing.
    case invalidArgument(String)

    /// The message shown to the user, naming the remedy rather than the symptom.
    public var errorDescription: String? {
        switch self {
        case .accessDenied(let entity):
            let name = entity == .reminder ? "Reminders" : "Calendars"
            return """
                Access to \(name) is not authorized. \
                Run `agenda doctor` to grant it, or enable agenda under \
                System Settings → Privacy & Security → \(name).
                """
        case .unknownCalendar(let name):
            return "No calendar named \"\(name)\". Run `agenda calendars` to list them."
        case .notFound(let id):
            return "Nothing found with identifier \"\(id)\"."
        case .badDuration(let raw):
            return "Could not read \"\(raw)\" as a duration. Use forms like 30m, 4h, 7d, 2w."
        case .badDate(let raw):
            return """
                Could not read "\(raw)" as a date. Use plain language like now, tomorrow 9am, \
                next friday, or +2d — or ISO 8601 like 2026-07-19T14:00.
                """
        case .badTimeZone(let raw):
            return "Unknown time zone \"\(raw)\". Use an IANA name like Europe/London or Asia/Tokyo."
        case .invalidArgument(let message):
            return message
        case .spanRequired(let title):
            return """
                "\(title)" repeats. Pass --span this to change only this occurrence, \
                or --span future to change this and every later one.
                """
        case .storeFailure(let message):
            return "EventKit rejected the change: \(message)"
        }
    }
}
