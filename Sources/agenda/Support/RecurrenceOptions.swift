//
//  RecurrenceOptions.swift
//  agenda
//
//  Shared --repeat / --every / --on / --until / --times flags.
//
//  Created by David Sherlock on 7/19/26.
//

import AgendaKit
import ArgumentParser
import Foundation

/// The repeat flags, shared by `add` and `move`.
///
/// Split across several small flags rather than one RRULE string because an RRULE is
/// write-only for most people — `--repeat weekly --on MO,WE,FR` is guessable from
/// `--help`, `FREQ=WEEKLY;BYDAY=MO,WE,FR` is not.
struct RecurrenceOptions: ParsableArguments {

    @Option(name: .customLong("repeat"), help: "Repeat: daily | weekly | monthly | yearly.")
    var frequency: AgendaFrequency?

    @Option(name: .long, help: "Repeat every N periods, e.g. --every 2 with --repeat weekly.")
    var every: Int = 1

    @Option(name: .long, help: "Weekdays, comma-separated: MO,WE,FR.")
    var on: String?

    @Option(name: .long, help: "Days of the month: 1,15 or 'last'.")
    var onDay: String?

    @Option(name: .long, help: "Which occurrence in the period: first | second | third | fourth | last.")
    var nth: String?

    @Option(name: .long, help: "Stop repeating after this date (ISO 8601).")
    var until: String?

    @Option(name: .long, help: "Stop after this many occurrences.")
    var times: Int?

    /// Builds a ``Recurrence``, or nil when no repeat flag was given.
    ///
    /// - Throws: ``AgendaError/badDate(_:)`` on an unparseable `--until`, or a
    ///   validation error when `--until` and `--times` are both present — EventKit
    ///   silently keeps only one, so the conflict is refused here instead.
    func resolve() throws -> Recurrence? {
        guard let frequency else { return nil }

        guard until == nil || times == nil else {
            throw ValidationError("Pass either --until or --times, not both.")
        }

        let weekdays = try (on?.split(separator: ",") ?? []).map { code -> AgendaWeekday in
            guard let day = AgendaWeekday(code: String(code)) else {
                throw ValidationError("Unknown weekday \"\(code)\". Use SU MO TU WE TH FR SA.")
            }
            return day
        }

        let monthDays = try (onDay?.split(separator: ",") ?? []).map { raw -> Int in
            let text = raw.trimmingCharacters(in: .whitespaces)
            if let ordinal = Self.ordinal(text) { return ordinal }
            throw ValidationError("Day of month must be 1–31 or 'last', got \"\(text)\".")
        }

        let positions = try nth.map { raw -> [Int] in
            guard let ordinal = Self.ordinal(raw) else {
                throw ValidationError("--nth takes first, second, third, fourth, or last.")
            }
            return [ordinal]
        } ?? []

        return Recurrence(
            frequency: frequency,
            interval: every,
            weekdays: weekdays,
            daysOfMonth: monthDays,
            setPositions: positions,
            endDate: try until.map(Agenda.date),
            occurrences: times
        )
    }

    /// Reads an ordinal as a signed position.
    ///
    /// Word forms exist because ArgumentParser reads a leading `-1` as an option name,
    /// so `--nth -1` fails to parse. `--nth last` sidesteps that entirely and reads
    /// better anyway; the `=-1` form still works for anyone who prefers numbers.
    private static func ordinal(_ raw: String) -> Int? {
        switch raw.lowercased() {
        case "first":  return 1
        case "second": return 2
        case "third":  return 3
        case "fourth": return 4
        case "fifth":  return 5
        case "last":   return -1
        default:
            guard let value = Int(raw), value != 0, (-31...31).contains(value) else { return nil }
            return value
        }
    }
}

extension AgendaFrequency: ExpressibleByArgument {}
extension AgendaAvailability: ExpressibleByArgument {}

/// Parses repeatable `--alert` and `--alert-at` values into alarms.
enum AlertParsing {

    /// Reads time-based `--alert` values like `15m`, `1h`, `0` (at start).
    ///
    /// Offsets are negated so a bare duration reads as "before", which is what every
    /// calendar UI means by a 15-minute alert.
    static func alarms(from values: [String]) throws -> [AgendaAlarm] {
        try values.map { raw in
            if raw == "0" { return AgendaAlarm(relativeOffset: 0) }
            return .before(try Agenda.duration(raw))
        }
    }

    /// Reads a geofenced alert of the form `enter:LAT,LON[,RADIUS][,TITLE]`.
    ///
    /// ```
    /// --alert-at "enter:51.5074,-0.1278,200,Office"
    /// --alert-at "leave:37.3349,-122.0090"
    /// ```
    ///
    /// Coordinates are required rather than a place name, because EventKit geofences
    /// on a `CLLocation` and has nothing to watch without one.
    ///
    /// - Throws: `ValidationError` describing the expected shape.
    static func locationAlarm(from raw: String) throws -> AgendaAlarm {
        let halves = raw.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard halves.count == 2,
              let proximity = AlarmProximity(rawValue: String(halves[0]).lowercased()),
              proximity != .none else {
            throw ValidationError("--alert-at must start with enter: or leave:, e.g. enter:51.5,-0.12,200,Office")
        }

        let parts = halves[1].split(separator: ",", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count >= 2, let latitude = Double(parts[0]), let longitude = Double(parts[1]) else {
            throw ValidationError("--alert-at needs latitude and longitude, e.g. enter:51.5074,-0.1278")
        }
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw ValidationError("Latitude must be -90…90 and longitude -180…180.")
        }

        let radius = parts.count > 2 ? Double(parts[2]) ?? 0 : 0
        let title = parts.count > 3 ? parts[3...].joined(separator: ",") : nil

        let location = AgendaLocation(title: title, latitude: latitude, longitude: longitude, radius: radius)
        return proximity == .enter ? .arriving(at: location) : .leaving(location)
    }
}
