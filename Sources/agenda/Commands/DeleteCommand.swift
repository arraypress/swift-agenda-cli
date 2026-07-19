//
//  DeleteCommand.swift
//  agenda
//
//  `agenda delete` — remove an event or reminder.
//
//  Created by David Sherlock on 7/19/26.
//

import AgendaKit
import ArgumentParser
import EventKit
import Foundation

struct DeleteCommand: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete an event or reminder by id.",
        discussion: """
            Deleting a repeating event requires --span. `--span future` removes every \
            remaining occurrence and cannot be undone, so it is never the default.

            Confirmation is required unless --yes is passed.
            """
    )

    @Argument(help: "Event or reminder id, from the second line of any text result.")
    var id: String

    @Flag(name: .long, help: "The id refers to a reminder.")
    var remind = false

    @Option(name: .long, help: "For repeating events: this | future.")
    var span: AgendaSpan?

    @Option(name: .long, help: "Which occurrence of a repeating event, e.g. 2026-08-10 or next friday.")
    var occurrence: String?

    @Flag(name: .long, help: "Skip the confirmation prompt.")
    var yes = false

    func run() async throws {
        if remind {
            try await Agenda.requestAccess(to: .reminder)
            let reminder = try await find(id: id)
            guard confirm("Delete reminder \"\(reminder.title)\"?") else { return }
            try Agenda.deleteReminder(id: id)
            print("Deleted \"\(reminder.title)\".")
        } else {
            try await Agenda.requestAccess(to: .event)
            let occurrenceDate = try occurrence.map(Agenda.date)
            let event = try Agenda.event(id: id, occurrenceOn: occurrenceDate)
            let scope = event.isRecurring
                ? (span == .future ? " and every later occurrence" : " (this occurrence only)")
                : ""
            guard confirm("Delete \"\(event.title)\"\(scope)?") else { return }
            try Agenda.deleteEvent(id: id, span: span, occurrenceOn: occurrenceDate)
            print("Deleted \"\(event.title)\"\(scope).")
        }
    }

    /// Locates a reminder by id, since there is no direct single-reminder fetch.
    private func find(id: String) async throws -> AgendaReminder {
        let all = try await Agenda.reminders(matching: ReminderFilter(includeCompleted: true))
        guard let match = all.first(where: { $0.id == id }) else {
            throw AgendaError.notFound(id)
        }
        return match
    }

    /// Prompts unless `--yes`. Answers other than y/yes abort.
    ///
    /// Reads from the terminal, so a non-interactive caller without `--yes` gets a
    /// refusal rather than a hang on empty stdin.
    private func confirm(_ question: String) -> Bool {
        guard !yes else { return true }
        print("\(question) [y/N] ", terminator: "")
        guard let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased(),
              answer == "y" || answer == "yes" else {
            print("Cancelled.")
            return false
        }
        return true
    }
}

extension AgendaSpan: ExpressibleByArgument {}
