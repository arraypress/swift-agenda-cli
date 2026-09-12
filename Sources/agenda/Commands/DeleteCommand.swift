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
import CLIKit
import EventKit
import Foundation

/// `agenda delete` — remove an event or reminder.
///
/// ON THE ENVELOPE because this is the verb here that cannot be taken back. There is no
/// Recently Deleted for a calendar, and `--span future` removes every remaining occurrence
/// of a series at once. So `--dry-run` says exactly what would go, and `--receipt` records
/// exactly what did — by id and title, so it can be looked up in a backup afterwards.
struct DeleteCommand: AgendaVerb, MutatingCommand {

    static let actionName = "delete"

    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete an event or reminder by id.",
        discussion: """
            Deleting a repeating event requires --span. `--span future` removes every \
            remaining occurrence and cannot be undone, so it is never the default.

            Confirmation is required unless --yes is passed. There is no Recently Deleted \
            for a calendar, so --dry-run is worth running first: it names what would go and \
            touches nothing.
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

    @OptionGroup var zone: ZoneOptions
    @OptionGroup var common: CommonOptions
    @OptionGroup var write: WriteOptions

    func plan() async throws -> [Change] {
        try zone.apply()
        do {
            if remind {
                try await Agenda.requestAccess(to: .reminder)
                let reminder = try await find(id: id)
                return [Change(.deleted, subject: id, from: reminder.list,
                               detail: ["kind": "reminder", "title": reminder.title])]
            }
            try await Agenda.requestAccess(to: .event)
            let event = try Agenda.event(id: id, occurrenceOn: try occurrence.map(Agenda.date))
            var detail = ["kind": "event", "title": event.title]
            if event.isRecurring {
                detail["scope"] = span == .future ? "this and every later occurrence"
                                                  : "this occurrence only"
            }
            return [Change(.deleted, subject: id, from: event.calendar, detail: detail)]
        } catch {
            throw Self.translate(error)
        }
    }

    func apply(_ plan: [Change]) async throws -> [Change] {
        // The prompt stays alongside --dry-run. They answer different questions: --dry-run
        // is "what would this do", the prompt is "are you sure". With nothing to put back
        // afterwards, both earn their place.
        let what = plan.first?.detail["title"] ?? id
        let scope = plan.first?.detail["scope"].map { " (\($0))" } ?? ""
        guard confirm("Delete \"\(what)\"\(scope)?") else {
            // Declined is recorded rather than silent: a receipt should be able to say the
            // deletion was considered and turned down.
            return plan.map {
                Change(.unchanged, subject: $0.subject, from: $0.from,
                       detail: $0.detail.merging(["reason": "declined at the prompt"]) { a, _ in a })
            }
        }
        do {
            if remind {
                try Agenda.deleteReminder(id: id)
            } else {
                try Agenda.deleteEvent(id: id, span: span,
                                       occurrenceOn: try occurrence.map(Agenda.date))
            }
        } catch {
            throw Self.translate(error)
        }
        return plan
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
            return false
        }
        return true
    }
}

extension AgendaSpan: ExpressibleByArgument {}
