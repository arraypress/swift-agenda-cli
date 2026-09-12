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
import CLIKit
import EventKit
import Foundation

struct EditCommand: AgendaVerb, MutatingCommand {

    static let actionName = "edit"

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

    @OptionGroup var zone: ZoneOptions
    @OptionGroup var common: CommonOptions
    @OptionGroup var write: WriteOptions

    func plan() async throws -> [Change] {
        try zone.apply()
        try await Agenda.requestAccess(to: .reminder)

        let before = try await current()
        let changes = try edits()
        guard !changes.isEmpty else {
            throw CLIError.usage("Nothing to change. See `agenda edit --help` for the available fields.")
        }

        // One change per field, so a receipt can be checked against the reminder afterwards
        // rather than read as a sentence.
        var planned: [Change] = []
        func field(_ name: String, _ was: String, _ now: String) {
            planned.append(Change(.updated, subject: "\(id)#\(name)", from: was, to: now,
                                  detail: ["field": name, "reminder": before.title]))
        }
        if let title = changes.title { field("title", before.title, title) }
        if let notes = changes.notes { field("notes", before.notes ?? "—", notes) }
        if let list = changes.list { field("list", before.list, list) }
        if let priority = changes.priority {
            field("priority", before.priorityLabel ?? "none", priority == 0 ? "none" : String(priority))
        }
        if let due = changes.dueAt {
            let was = before.dueAt.map { (before.isDueAllDay ? Output.day : Output.stamp).string(from: $0) } ?? "none"
            field("due", was, due.map { Output.stamp.string(from: $0) } ?? "none")
        }
        if let recurrence = changes.recurrence {
            field("repeat", before.recurrence?.summary ?? "does not repeat",
                  recurrence?.summary ?? "does not repeat")
        }
        if let alarms = changes.alarms {
            field("alerts",
                  before.alarms.isEmpty ? "none" : before.alarms.map(\.summary).joined(separator: ", "),
                  alarms.isEmpty ? "none" : alarms.map(\.summary).joined(separator: ", "))
        }
        return planned
    }

    func apply(_ plan: [Change]) async throws -> [Change] {
        do { _ = try Agenda.updateReminder(id: id, with: try edits()) }
        catch let error as CLIError { throw error }
        catch { throw Self.translate(error) }
        return plan
    }

    /// The reminder as it stands, since there is no single-reminder fetch.
    private func current() async throws -> AgendaReminder {
        let all = try await Agenda.reminders(matching: ReminderFilter(includeCompleted: true))
        guard let match = all.first(where: { $0.id == id }) else { throw AgendaError.notFound(id) }
        return match
    }

    /// The edits these flags describe.
    private func edits() throws -> ReminderChanges {
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

        return changes
    }
}
