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
import CLIKit
import EventKit
import Foundation

struct DoctorCommand: AgendaVerb {

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

    @OptionGroup var zone: ZoneOptions
    @OptionGroup var common: CommonOptions

    /// One permission row.
    struct Check: Codable, TextRenderable {
        let name: String
        let status: String
        let remedy: String?

        func renderText() -> String {
            let mark = remedy == nil ? "✓" : "✗"
            return "\(mark) \(name)  \(status)" + (remedy.map { "\n    \($0)" } ?? "")
        }
    }

    /// Whether Calendar.app holds calendars EventKit cannot reach.
    ///
    /// Not a permission problem and not fixable, so it reports as a note rather than a
    /// failure — `remedy` stays nil and the exit code is unaffected. It is here because the
    /// symptom is an empty answer, which is indistinguishable from a correct one.
    private func calendarGap() -> Check? {
        let hidden = HiddenCalendars.names()
        guard !hidden.isEmpty else { return nil }
        return Check(name: "Hidden calendars",
                     status: "\(hidden.joined(separator: ", ")) — visible in Calendar.app, "
                           + "not exposed by EventKit, so invisible here",
                     remedy: nil)
    }

    func execute() async throws {
        try zone.apply()
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
        ] + [calendarGap()].compactMap { $0 }

        try common.emitter.emitAll(checks)
        if common.format == .text, checks.contains(where: { $0.remedy != nil }) {
            Terminal.writeLine("\nRun `agenda doctor --fix` to prompt, or open:")
            Terminal.writeLine("  System Settings → Privacy & Security → Calendars / Reminders")
        }

        // Non-zero exit so a script can gate on this without parsing the output.
        if checks.contains(where: { $0.remedy != nil }) {
            throw ExitCode(1)
        }
    }
}
