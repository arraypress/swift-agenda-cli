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
import EventKit
import Foundation

struct DoneCommand: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "done",
        abstract: "Mark a reminder complete.",
        discussion: "Pass --undo to reopen one instead."
    )

    @Argument(help: "Reminder id.")
    var id: String

    @Flag(name: .long, help: "Reopen the reminder instead of completing it.")
    var undo = false

    @OptionGroup var output: OutputOptions

    func run() async throws {
        try output.apply()
        try await Agenda.requestAccess(to: .reminder)
        let updated = try Agenda.completeReminder(id: id, completed: !undo)

        switch output.format {
        case .json: print(try Output.encode(updated))
        case .text: print(Output.line(updated))
        }
    }
}
