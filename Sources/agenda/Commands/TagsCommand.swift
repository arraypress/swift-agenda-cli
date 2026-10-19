//
//  TagsCommand.swift
//  agenda
//
//  Created by David Sherlock on 2026.
//
//  `agenda tags` — every tag on an open reminder, and how many carry it.
//

import AgendaKit
import ArgumentParser
import CLIKit
import EventKit
import Foundation

struct TagsCommand: AgendaVerb {

    static let commandEffect = CommandEffect.readOnly

    static let configuration = CommandConfiguration(
        commandName: "tags",
        abstract: "List the tags on your reminders, with counts.",
        discussion: "The names `agenda reminders --tag` takes. --all counts completed reminders too."
    )

    @Flag(name: .long, help: "Count completed reminders too.")
    var all = false

    @OptionGroup var zone: ZoneOptions
    @OptionGroup var common: CommonOptions

    func execute() async throws {
        try zone.apply()
        try await Agenda.requestAccess(to: .reminder)
        let reminders = try await Agenda.reminders(matching: ReminderFilter(includeCompleted: all))
        let store = try StoreDetails.load().require(for: "Listing tags")
        let tags = TagCount.tally(reminders, store: store)
        // Not `emit`: its empty-answer note is about hidden calendars, which says nothing here.
        if tags.isEmpty, common.format == .text { Terminal.writeLine("No tags."); return }
        try common.emitter.emitAll(tags)
    }
}

/// A tag and how many reminders carry it.
struct TagCount: Encodable, Equatable, TableRenderable, UntrustedContent {

    static var untrustedFields: Set<String> { ["tag"] }

    let tag: String
    let reminders: Int

    static let tableColumns = ["tag", "reminders"]

    var tableRow: [String] { [Untrusted.text("#\(tag)"), String(reminders)] }

    func renderText() -> String { "\(Untrusted.text("#\(tag)"))  \(reminders)" }

    /// Counts per tag over the reminders EventKit returned, most used first.
    /// Spellings that differ only in case or accents count as one tag.
    static func tally(_ reminders: [AgendaReminder], store: ReminderStoreContents) -> [TagCount] {
        var counts: [String: (name: String, count: Int)] = [:]
        for reminder in reminders {
            for tag in store.details(for: reminder.id)?.tags ?? [] {
                counts[ReminderTree.key(tag), default: (tag, 0)].count += 1
            }
        }
        return counts.values.map { TagCount(tag: $0.name, reminders: $0.count) }
            .sorted { ($0.reminders, $1.tag) > ($1.reminders, $0.tag) }
    }
}
