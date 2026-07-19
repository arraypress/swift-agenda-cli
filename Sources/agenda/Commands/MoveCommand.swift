//
//  MoveCommand.swift
//  agenda
//
//  `agenda move` — reschedule or edit an event.
//
//  Created by David Sherlock on 7/19/26.
//

import AgendaKit
import ArgumentParser
import EventKit
import Foundation

struct MoveCommand: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "move",
        abstract: "Reschedule or edit an existing event.",
        discussion: """
            agenda move <id> --to 2026-07-20T20:00
            agenda move <id> --by 1h --span this

            Only the fields you pass change. Editing a repeating event requires --span.
            """
    )

    @Argument(help: "Event id.")
    var id: String

    @Option(name: .long, help: "New start: tomorrow 9am, next friday, +2d, or ISO 8601. Duration is preserved.")
    var to: String?

    @Option(name: .long, help: "Shift by a duration: 30m, 1h, 1d.")
    var by: String?

    @Option(name: .long, help: "New title.")
    var title: String?

    @Option(name: .long, help: "New location.")
    var location: String?

    @Option(name: .long, help: "New notes.")
    var notes: String?

    @Option(name: .long, help: "Move to this calendar.")
    var calendar: String?

    @Option(name: .long, help: "Free/busy marking: busy | free | tentative | unavailable.")
    var availability: AgendaAvailability?

    @Option(name: .long, help: "Replace alerts: 15m, 1h, 1d. Repeatable.")
    var alert: [String] = []

    @Flag(name: .long, help: "Remove all alerts.")
    var clearAlerts = false

    @Flag(name: .long, help: "Stop it repeating.")
    var clearRepeat = false

    @OptionGroup var repeats: RecurrenceOptions

    @Option(name: .long, help: "For repeating events: this | future.")
    var span: AgendaSpan?

    @Option(name: .long, help: "Which occurrence of a repeating event, e.g. 2026-08-10 or next friday.")
    var occurrence: String?

    @Flag(name: .long, help: "Print the change without saving.")
    var dryRun = false

    @OptionGroup var output: OutputOptions

    func run() async throws {
        try output.apply()
        try await Agenda.requestAccess(to: .event)
        let occurrenceDate = try occurrence.map(Agenda.date)
        let event = try Agenda.event(id: id, occurrenceOn: occurrenceDate)

        var changes = EventChanges(title: title, location: location, notes: notes,
                                   calendar: calendar, availability: availability)

        if clearRepeat {
            changes.recurrence = .some(nil)
        } else if let recurrence = try repeats.resolve() {
            changes.recurrence = .some(recurrence)
        }

        if clearAlerts {
            changes.alarms = []
        } else if !alert.isEmpty {
            changes.alarms = try AlertParsing.alarms(from: alert)
        }

        // Duration is held constant across a move — a reschedule should not silently
        // shorten a meeting because only the start was given.
        if let to {
            let start = try Agenda.date(to)
            changes.startsAt = start
            changes.endsAt = start.addingTimeInterval(event.duration)
        } else if let by {
            let shift = try Agenda.duration(by)
            changes.startsAt = event.startsAt.addingTimeInterval(shift)
            changes.endsAt = event.endsAt.addingTimeInterval(shift)
        }

        guard !changes.isEmpty else {
            print("Nothing to change. See `agenda move --help` for the available fields.")
            return
        }

        if dryRun {
            print(diff(event: event, changes: changes))
            return
        }

        let updated = try Agenda.updateEvent(id: id, with: changes, span: span, occurrenceOn: occurrenceDate)
        switch output.format {
        case .json: print(try Output.encode(updated))
        case .text: print(Output.line(updated))
        }
    }

    /// A field-level before/after, so a caller can see exactly what a write will do.
    private func diff(event: AgendaEvent, changes: EventChanges) -> String {
        var lines = ["Would change \"\(event.title)\":"]
        if let title = changes.title { lines.append("  title     \(event.title) → \(title)") }
        if let start = changes.startsAt {
            lines.append("  starts    \(Output.stamp.string(from: event.startsAt)) → \(Output.stamp.string(from: start))")
        }
        if let end = changes.endsAt {
            lines.append("  ends      \(Output.stamp.string(from: event.endsAt)) → \(Output.stamp.string(from: end))")
        }
        if let location = changes.location {
            lines.append("  location  \(event.location ?? "—") → \(location)")
        }
        if let notes = changes.notes {
            lines.append("  notes     \(event.notes ?? "—") → \(notes)")
        }
        if let calendar = changes.calendar {
            lines.append("  calendar  \(event.calendar) → \(calendar)")
        }
        if let availability = changes.availability {
            lines.append("  free/busy \(event.availability.rawValue) → \(availability.rawValue)")
        }
        if let recurrence = changes.recurrence {
            let before = event.recurrence?.summary ?? "does not repeat"
            lines.append("  repeat    \(before) → \(recurrence?.summary ?? "does not repeat")")
        }
        if let alarms = changes.alarms {
            let before = event.alarms.isEmpty ? "none" : event.alarms.map(\.summary).joined(separator: ", ")
            let after = alarms.isEmpty ? "none" : alarms.map(\.summary).joined(separator: ", ")
            lines.append("  alerts    \(before) → \(after)")
        }
        if event.isRecurring {
            lines.append("  scope     \(span == .future ? "this and all later occurrences" : "this occurrence only")")
        }
        return lines.joined(separator: "\n")
    }
}
