//
//  DoctorCommand.swift
//  agenda
//
//  `agenda doctor` — report permission state and how to fix it.
//
//  Created by David Sherlock on 7/19/26.
//

import AgendaKit
import ArgumentParser
import EventKit
import Foundation

struct DoctorCommand: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check calendar and reminder permissions.",
        discussion: """
            macOS permission state is otherwise invisible until a command returns \
            nothing and you cannot tell whether that means "empty" or "blocked". \
            Run this first when something looks wrong.
            """
    )

    @Flag(name: .long, help: "Trigger the permission prompts for anything not yet granted.")
    var fix = false

    @OptionGroup var output: OutputOptions

    /// One permission row.
    struct Check: Codable {
        let name: String
        let status: String
        let remedy: String?
    }

    func run() async throws {
        try output.apply()
        if fix {
            // Failures are expected here — a denied entity throws, and the report
            // below is what the user actually reads.
            try? await Agenda.requestAccess(to: .event)
            try? await Agenda.requestAccess(to: .reminder)
        }

        let checks = [
            Check(name: "Calendars",
                  status: Agenda.access(to: .event).rawValue,
                  remedy: Agenda.access(to: .event).remedy),
            Check(name: "Reminders",
                  status: Agenda.access(to: .reminder).rawValue,
                  remedy: Agenda.access(to: .reminder).remedy)
        ]

        switch output.format {
        case .json:
            print(try Output.encode(checks))
        case .text:
            for check in checks {
                let mark = check.remedy == nil ? "✓" : "✗"
                print("\(mark) \(check.name)  \(check.status)")
                if let remedy = check.remedy { print("    \(remedy)") }
            }
            if checks.contains(where: { $0.remedy != nil }) {
                print("\nRun `agenda doctor --fix` to prompt, or open:")
                print("  System Settings → Privacy & Security → Calendars / Reminders")
            }
        }

        // Non-zero exit so a script can gate on this without parsing the output.
        if checks.contains(where: { $0.remedy != nil }) {
            throw ExitCode(1)
        }
    }
}
