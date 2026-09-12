//
//  RemindersCommand.swift
//  agenda
//
//  `agenda reminders` — list reminders.
//
//  Created by David Sherlock on 7/19/26.
//

import AgendaKit
import ArgumentParser
import CLIKit
import EventKit
import Foundation

struct RemindersCommand: AgendaVerb {

    static let configuration = CommandConfiguration(
        commandName: "reminders",
        abstract: "List reminders.",
        discussion: """
            Open reminders only, soonest due first, undated ones last. Reminders with \
            no due date are kept — they are still open work, just unscheduled.
            """
    )

    @Option(name: .long, help: "Restrict to a list by title or id. Repeatable.")
    var list: [String] = []

    @Option(name: .long, help: "Only reminders due within this window: 24h, 7d.")
    var due: String?

    @Flag(name: .long, help: "Only reminders past their due date.")
    var overdue = false

    @Flag(name: .long, help: "Include completed reminders.")
    var all = false

    @Option(name: .long, help: "Maximum rows to return.")
    var limit: Int?

    @OptionGroup var zone: ZoneOptions
    @OptionGroup var common: CommonOptions

    func execute() async throws {
        try zone.apply()
        try await Agenda.requestAccess(to: .reminder)

        var filter = ReminderFilter()
        filter.lists = list
        filter.includeCompleted = all
        filter.overdueOnly = overdue
        filter.dueWithin = try due.map(Agenda.duration)
        filter.limit = limit

        let reminders = try await Agenda.reminders(matching: filter)
        try emit(reminders.map(ReminderPayload.init), empty: overdue ? "Nothing overdue." : "No reminders.", options: common)
    }
}
