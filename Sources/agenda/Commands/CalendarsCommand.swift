//
//  CalendarsCommand.swift
//  agenda
//
//  `agenda calendars` — list calendars and reminder lists.
//
//  Created by David Sherlock on 7/19/26.
//

import AgendaKit
import ArgumentParser
import EventKit
import Foundation

struct CalendarsCommand: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "calendars",
        abstract: "List calendars, or reminder lists with --reminders.",
        discussion: """
            Read-only calendars are marked. Creating into one fails, so check here \
            before scripting a write against an unfamiliar calendar name.
            """
    )

    @Flag(name: .long, help: "List reminder lists instead of calendars.")
    var reminders = false

    @OptionGroup var output: OutputOptions

    func run() async throws {
        try output.apply()
        let entity: EKEntityType = reminders ? .reminder : .event
        try await Agenda.requestAccess(to: entity)

        let calendars = try Agenda.calendars(for: entity)
        try Output.render(calendars, format: output.format,
                          empty: reminders ? "No reminder lists." : "No calendars.",
                          line: Output.line)
    }
}
