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
import CLIKit
import EventKit
import Foundation

struct CalendarsCommand: AgendaVerb {

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

    @OptionGroup var zone: ZoneOptions
    @OptionGroup var common: CommonOptions

    func execute() async throws {
        try zone.apply()
        let entity: EKEntityType = reminders ? .reminder : .event
        try await Agenda.requestAccess(to: entity)

        let calendars = try Agenda.calendars(for: entity)
        try emit(calendars.map(CalendarPayload.init), empty: reminders ? "No reminder lists." : "No calendars.", options: common)
    }
}
