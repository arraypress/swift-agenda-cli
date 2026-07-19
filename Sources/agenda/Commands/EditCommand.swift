//
//  EditCommand.swift
//  agenda
//
//  `agenda edit` — change an existing reminder.
//
//  Created by David Sherlock on 7/19/26.
//

import AgendaKit
import ArgumentParser
import EventKit
import Foundation

struct EditCommand: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "edit",
        abstract: "Change an existing reminder.",
        discussion: """
            agenda edit <id> --title "Call the accountant back"
            agenda edit <id> --due 2026-08-15T09:00 --priority 1
            agenda edit <id> --clear-due          # unschedule it
            agenda edit <id> --clear-repeat

            Use `agenda move` for events. Only the fields you pass change.
            """
    )

    @Argument(help: "Reminder id.")
    var id: String

    @Option(name: .long, help: "New title.")
    var title: String?

    @Option(name: .long, help: "New due date: tomorrow 9am, next friday, +2d, or ISO 8601.")
    var due: String?

    @Flag(name: .long, help: "Remove the due date, leaving it unscheduled.")
    var clearDue = false

    @Option(name: .long, help: "New start date — when it becomes actionable.")
    var start: String?

    @Flag(name: .long, help: "Make the due date all-day, with no time.")
    var allDay = false

    @Option(name: .long, help: "New priority, 1 (highest) to 9, or 0 to clear.")
    var priority: Int?

    @Option(name: .long, help: "New notes.")
    var notes: String?

    @Option(name: .long, help: "Move to this reminder list.")
    var list: String?

    @Option(name: .long, help: "Replace alerts: 15m, 1h. Repeatable.")
    var alert: [String] = []

    @Flag(name: .long, help: "Remove all alerts.")
    var clearAlerts = false

    @Flag(name: .long, help: "Stop it repeating.")
    var clearRepeat = false

    @OptionGroup var repeats: RecurrenceOptions

    @OptionGroup var output: OutputOptions

    func run() async throws {
        try output.apply()
        try await Agenda.requestAccess(to: .reminder)

        var changes = ReminderChanges(title: title, notes: notes,
                                      priority: priority, list: list)

        if clearDue {
            changes.dueAt = .some(nil)
        } else if let due {
            changes.dueAt = .some(try Agenda.date(due))
        }
        if let start { changes.startsAt = .some(try Agenda.date(start)) }
        if allDay { changes.dueHasTime = false }

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

        guard !changes.isEmpty else {
            print("Nothing to change. See `agenda edit --help` for the available fields.")
            return
        }

        let updated = try Agenda.updateReminder(id: id, with: changes)
        switch output.format {
        case .json: print(try Output.encode(updated))
        case .text: print(Output.line(updated))
        }
    }
}
