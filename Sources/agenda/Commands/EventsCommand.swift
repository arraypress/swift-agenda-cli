//
//  EventsCommand.swift
//  agenda
//
//  `agenda events` — list calendar events.
//
//  Created by David Sherlock on 7/19/26.
//

import AgendaKit
import ArgumentParser
import CLIKit
import EventKit
import Foundation

struct EventsCommand: AgendaVerb {

    static let configuration = CommandConfiguration(
        commandName: "events",
        abstract: "List calendar events.",
        discussion: """
            Defaults to the next 7 days. Events already in progress are included, so \
            `agenda events --next 1h` answers "what am I in right now?" as well as \
            "what's coming up?".
            """
    )

    @Option(name: .long, help: "Window forward from now: 4h, 7d, 2w.")
    var next: String = "7d"

    @Option(name: .long, help: "Range start: today, monday, 2026-07-19. Overrides --next.")
    var from: String?

    @Option(name: .long, help: "Range end: friday, +2w, 2026-07-26. Overrides --next.")
    var to: String?

    @Option(name: .long, help: "Restrict to a calendar by title or id. Repeatable.")
    var calendar: [String] = []

    @Flag(name: .long, help: "Only events that overlap another event.")
    var conflicts = false

    @OptionGroup var zone: ZoneOptions
    @OptionGroup var common: CommonOptions

    func execute() async throws {
        try zone.apply()
        try await Agenda.requestAccess(to: .event)

        if conflicts {
            let pairs = try Agenda.conflicts(calendars: calendar)
            let flattened = pairs.flatMap { [$0.0, $0.1] }
            try emit(flattened.map(EventPayload.init), empty: "No conflicts today.", options: common)
            return
        }

        let start = try from.map(Agenda.date) ?? Date()
        let end: Date
        if let to {
            end = try Agenda.date(to)
        } else {
            end = start.addingTimeInterval(try Agenda.duration(next))
        }

        let events = try Agenda.events(from: start, to: end, calendars: calendar)
        try emit(events.map(EventPayload.init), empty: "Nothing scheduled.", options: common)
    }
}
