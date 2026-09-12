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
import CLIKit
import EventKit
import Foundation

struct MoveCommand: AgendaVerb, MutatingCommand {

    static let actionName = "move"

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

    @OptionGroup var zone: ZoneOptions
    @OptionGroup var common: CommonOptions
    @OptionGroup var write: WriteOptions

    func plan() async throws -> [Change] {
        try zone.apply()
        try await Agenda.requestAccess(to: .event)
        let occurrenceDate = try occurrence.map(Agenda.date)
        let event: AgendaEvent
        do { event = try Agenda.event(id: id, occurrenceOn: occurrenceDate) }
        catch { throw Self.translate(error) }

        let changes = try edits(for: event)
        guard !changes.isEmpty else {
            throw CLIError.usage("Nothing to change. See `agenda move --help` for the available fields.")
        }

        // ONE CHANGE PER FIELD. This used to be a `diff` function printing a block of
        // "before → after" lines, which is the same information as prose — readable, and
        // impossible for anything else to check against what happened afterwards.
        var planned: [Change] = []
        func field(_ name: String, _ before: String, _ after: String) {
            planned.append(Change(.updated, subject: "\(id)#\(name)", from: before, to: after,
                                  detail: ["field": name, "event": event.title]))
        }
        if let title = changes.title { field("title", event.title, title) }
        if let start = changes.startsAt {
            field("starts", Output.stamp.string(from: event.startsAt), Output.stamp.string(from: start))
        }
        if let end = changes.endsAt {
            field("ends", Output.stamp.string(from: event.endsAt), Output.stamp.string(from: end))
        }
        if let location = changes.location { field("location", event.location ?? "—", location) }
        if let notes = changes.notes { field("notes", event.notes ?? "—", notes) }
        if let calendar = changes.calendar { field("calendar", event.calendar, calendar) }
        if let availability = changes.availability {
            field("free/busy", event.availability.rawValue, availability.rawValue)
        }
        if let recurrence = changes.recurrence {
            field("repeat", event.recurrence?.summary ?? "does not repeat",
                  recurrence?.summary ?? "does not repeat")
        }
        if let alarms = changes.alarms {
            field("alerts",
                  event.alarms.isEmpty ? "none" : event.alarms.map(\.summary).joined(separator: ", "),
                  alarms.isEmpty ? "none" : alarms.map(\.summary).joined(separator: ", "))
        }
        if event.isRecurring {
            // Scope is not a field being changed, it is how far the change reaches — which
            // is the single most important thing to know before rewriting a series.
            planned.append(Change(.unchanged, subject: "\(id)#scope",
                                  to: span == .future ? "this and all later occurrences"
                                                      : "this occurrence only",
                                  detail: ["field": "scope", "event": event.title]))
        }
        return planned
    }

    func apply(_ plan: [Change]) async throws -> [Change] {
        let occurrenceDate = try occurrence.map(Agenda.date)
        do {
            let event = try Agenda.event(id: id, occurrenceOn: occurrenceDate)
            _ = try Agenda.updateEvent(id: id, with: try edits(for: event),
                                       span: span, occurrenceOn: occurrenceDate)
        } catch let error as CLIError {
            throw error
        } catch {
            throw Self.translate(error)
        }
        return plan
    }

    /// The edits these flags describe, against the event as it stands.
    private func edits(for event: AgendaEvent) throws -> EventChanges {
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
        return changes
    }
}
