//
//  DoneCommand.swift
//  agenda
//
//  `agenda done` — tick off a reminder.
//
//  Created by David Sherlock on 7/19/26.
//

import AgendaKit
import ArgumentParser
import CLIKit
import EventKit
import Foundation

struct DoneCommand: AgendaVerb {

    static let configuration = CommandConfiguration(
        commandName: "done",
        abstract: "Mark a reminder complete.",
        discussion: "Pass --undo to reopen one instead."
    )

    @Argument(help: "Reminder id.")
    var id: String

    @Flag(name: .long, help: "Reopen the reminder instead of completing it.")
    var undo = false

    @OptionGroup var zone: ZoneOptions
    @OptionGroup var common: CommonOptions

    // NO ENVELOPE, and that is the judgement rather than an omission: `--undo` reverses
    // this exactly, so there is nothing to plan and nothing to record that the reminder
    // itself does not already say.
    func execute() async throws {
        try zone.apply()
        try await Agenda.requestAccess(to: .reminder)
        do {
            let updated = try Agenda.completeReminder(id: id, completed: !undo)
            try common.emitter.emit(ReminderPayload(updated))
        } catch {
            throw Self.translate(error)
        }
    }
}
