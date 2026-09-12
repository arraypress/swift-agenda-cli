//
//  Agenda.swift
//  agenda
//
//  Command-line entry point.
//
//  Created by David Sherlock on 7/19/26.
//

import ArgumentParser
import CLIKit
import Foundation

struct AgendaCommand: AsyncParsableCommand, ServiceProviding {

    /// Local, and nothing to authenticate against. The gates are macOS privacy permissions,
    /// which are not credentials and cannot be stored.
    static let service = ServiceSpec(
        id: "agenda",
        displayName: "Calendar and Reminders",
        toolName: "agenda",
        credentials: []
    )

    static let configuration = CommandConfiguration(
        commandName: "agenda",
        abstract: "Query and edit your Apple Calendar and Reminders.",
        discussion: """
            Reads are safe to run freely. Writes that touch a repeating event require \
            an explicit --span so a whole series is never rewritten by accident.

            Durations accept 30m, 4h, 7d, 2w, 6mo, 1y.
            Dates accept plain language — now, today, tomorrow, next friday, +2d,
            "tomorrow 9am" — as well as ISO 8601 like 2026-07-19T14:00.
            """,
        version: "1.0.2",
        subcommands: [
            EventsCommand.self,
            TodayCommand.self,
            TomorrowCommand.self,
            RemindersCommand.self,
            SearchCommand.self,
            FreeCommand.self,
            AddCommand.self,
            DoneCommand.self,
            EditCommand.self,
            MoveCommand.self,
            DeleteCommand.self,
            CalendarsCommand.self,
            DoctorCommand.self,
            DescribeCommand<AgendaCommand>.self,
            MCPCommand<AgendaCommand>.self
        ],
        defaultSubcommand: EventsCommand.self
    )
}

// MARK: - Entry Point

/// `CLIRunner` rather than `@main` on the command itself, so the exit codes are the family's:
/// ArgumentParser's 64 becomes the documented 2, and a thrown `CLIError` maps to its own code
/// instead of a bare 1.
@main
enum Main {
    static func main() async { await CLIRunner.run(AgendaCommand.self) }
}
