//
//  SearchCommand.swift
//  agenda
//
//  `agenda search` — find events and reminders by text.
//
//  Created by David Sherlock on 7/19/26.
//

import AgendaKit
import ArgumentParser
import CLIKit
import EventKit
import Foundation

struct SearchCommand: AgendaVerb {

    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Find events and reminders matching some text.",
        discussion: """
            agenda search flight
            agenda search "berlin" --within 1y
            agenda search dentist --events

            Searches titles, notes, locations, and URLs — a booking reference usually \
            lives in the notes, not the title. Matching ignores case and accents, so \
            "zurich" finds "Zürich".
            """
    )

    @Argument(help: "Text to look for.")
    var query: String

    @Option(name: .long, help: "How far ahead to search: 30d, 6m, 1y.")
    var within: String = "1y"

    @Option(name: .long, help: "How far back to search.")
    var past: String = "30d"

    @Flag(name: .long, help: "Search events only.")
    var events = false

    @Flag(name: .long, help: "Search reminders only.")
    var reminders = false

    @Option(name: .long, help: "Restrict to a calendar or list. Repeatable.")
    var calendar: [String] = []

    @OptionGroup var zone: ZoneOptions
    @OptionGroup var common: CommonOptions

    func execute() async throws {
        try zone.apply()

        // Neither flag means both, which is the useful default — "find my flight"
        // should not care which app the user happened to put it in.
        let wantEvents = events || !reminders
        let wantReminders = reminders || !events

        if wantEvents { try await Agenda.requestAccess(to: .event) }
        if wantReminders { try await Agenda.requestAccess(to: .reminder) }

        let hits = try await Agenda.search(
            query,
            within: try Agenda.duration(within),
            past: try Agenda.duration(past),
            includeEvents: wantEvents,
            includeReminders: wantReminders,
            calendars: calendar
        )

        try emit(hits.map(SearchPayload.init), empty: "Nothing matching \"\(query)\".", options: common)
    }
}
