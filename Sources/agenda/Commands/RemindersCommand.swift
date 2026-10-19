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

    static let commandEffect = CommandEffect.readOnly

    static let configuration = CommandConfiguration(
        commandName: "reminders",
        abstract: "List reminders.",
        discussion: """
            Open reminders only, soonest due first, undated ones last. Reminders with \
            no due date are kept — they are still open work, just unscheduled.

            agenda reminders --tag errands
            agenda reminders --list Groceries               # grouped by section
            agenda reminders --list Groceries --section Produce

            Tags, sections and subtasks come from Reminders' own store, which EventKit \
            cannot see: read from a private copy, never written, and it needs Full Disk \
            Access for the terminal. Without it reminders still print, without them, and \
            a note says so; --tag and --section fail (exit 3) rather than guess. Subtasks \
            print under their parent. With one --list, text output is grouped by section.
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

    @Option(name: .long, help: "Only reminders with this tag (no #). Repeatable: any of them.")
    var tag: [String] = []

    @Option(name: .long, help: "Only reminders in this list section. Repeatable: any of them.")
    var section: [String] = []

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
        // The limit applies after the tag and section filters, not before them.
        filter.limit = tag.isEmpty && section.isEmpty ? limit : nil

        let fetched = try await Agenda.reminders(matching: filter)
        let store = StoreDetails.load()
        if !tag.isEmpty || !section.isEmpty {
            _ = try store.require(for: tag.isEmpty ? "--section" : "--tag")
        }
        store.warn(common)

        var reminders = ReminderTree.filter(fetched, tags: tag, sections: section, store: store.contents)
        if let limit, reminders.count > limit { reminders = Array(reminders.prefix(limit)) }
        let placed = ReminderTree.nest(reminders, store: store.contents)
        let empty = overdue ? "Nothing overdue." : "No reminders."

        // One list, in text: under its section headings, as Reminders shows it.
        guard common.format == .text, list.count == 1, !placed.isEmpty,
              let groups = Optional(ReminderTree.group(placed, store: store.contents)),
              groups.contains(where: { $0.section != nil }) else {
            try emit(placed.map(ReminderPayload.init), empty: empty, options: common)
            return
        }
        for (index, group) in groups.enumerated() {
            if let name = group.section {
                Terminal.writeLine((index == 0 ? "" : "\n") + "── \(Untrusted.text(name))")
            }
            try common.emitter.emitAll(group.reminders.map(ReminderPayload.init))
        }
    }
}
