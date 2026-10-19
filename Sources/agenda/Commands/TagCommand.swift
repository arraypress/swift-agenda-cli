//
//  TagCommand.swift
//  agenda
//
//  Created by David Sherlock on 2026.
//
//  `agenda tag` — add or remove tags on a reminder, through Shortcuts.
//

import AgendaKit
import ArgumentParser
import CLIKit
import EventKit
import Foundation

struct TagCommand: AgendaVerb, MutatingCommand {

    /// Removing a tag removes data; doing it twice changes nothing more.
    static let commandEffect = CommandEffect.acting(destructive: true, idempotent: true)

    static let actionName = "tag"

    static let configuration = CommandConfiguration(
        commandName: "tag",
        abstract: "Add or remove a reminder's tags (through Shortcuts).",
        discussion: """
            agenda tag --install --yes                 # once: offers the helper shortcut
            agenda tag <id> --add errands --remove someday
            agenda tag <id> --add errands --yes

            Shows the plan and changes nothing unless --yes is passed.

            EventKit cannot write tags, so this runs a helper shortcut ("agenda add tags" / \\
            "agenda remove tags") that Reminders' "Add or Remove Tags" action does the work \\
            in. Adding a shortcut needs your click: --install opens Shortcuts' Add sheet. \\
            The helper finds the reminder by title, so a reminder whose title another \\
            reminder shares is refused (exit 2). Success is read back from the Reminders \\
            store; tags that do not land exit 5 with "retry" saying whether anything changed.
            """
    )

    @Argument(help: "Reminder id.")
    var id: String?

    @Option(name: .long, help: "Tag to add (no #). Repeatable.")
    var add: [String] = []

    @Option(name: .long, help: "Tag to remove. Repeatable.")
    var remove: [String] = []

    @Flag(name: .long, help: "Offer the helper shortcuts to your Shortcuts library.")
    var install = false

    @Flag(name: .long, help: "Do it. Without this, only the plan is shown.")
    var yes = false

    @OptionGroup var zone: ZoneOptions
    @OptionGroup var common: CommonOptions
    @OptionGroup var write: WriteOptions

    var isPlanOnly: Bool { write.dryRun || !yes }

    func validate() throws {
        if install {
            guard id == nil, add.isEmpty, remove.isEmpty else {
                throw ValidationError("--install takes no id or tags.")
            }
            return
        }
        guard id != nil else { throw ValidationError("Name the reminder: agenda tag <id> --add <tag>.") }
        guard !add.isEmpty || !remove.isEmpty else { throw ValidationError("Pass --add or --remove.") }
        let clash = Set(add.map(ReminderTree.key)).intersection(remove.map(ReminderTree.key))
        guard clash.isEmpty else { throw ValidationError("A tag cannot be both added and removed: \(clash.sorted().joined(separator: ", ")).") }
    }

    func plan() async throws -> [Change] {
        try zone.apply()
        if install {
            let status = try TagShortcuts.status()
            if let note = status.obsoleteNote, !common.quiet { Terminal.writeError(note) }
            var changes = [status.installed
                ? Change(.unchanged, subject: TagShortcuts.name, detail: ["reason": "already installed"])
                : Change(.created, subject: TagShortcuts.name, to: "Shortcuts",
                         detail: ["note": "opens Shortcuts' Add sheet; nothing is added until you click"])]
            changes += status.obsolete.map {
                Change(.unchanged, subject: $0, detail: ["note": "obsolete — no longer used; delete it in Shortcuts"])
            }
            return changes
        }
        let id = id ?? ""
        do {
            try await Agenda.requestAccess(to: .reminder)
            let all = try await Agenda.reminders(matching: ReminderFilter(includeCompleted: true))
            guard let reminder = all.first(where: { $0.id == id }) else { throw AgendaError.notFound(id) }
            let store = try StoreDetails.load().require(for: "Tagging")
            guard let details = store.details(for: id) else {
                throw CLIError.upstream("The Reminders store has no row for \(id), so its tags cannot be read or checked",
                                        service: "agenda")
            }
            let plan = TagPlan.make(current: details.tags, add: add, remove: remove)
            guard !plan.isEmpty else {
                return [Change(.unchanged, subject: id, detail: ["title": reminder.title, "tags": Self.render(details.tags),
                                                                 "reason": "already as asked"])]
            }
            try TitleMatch.requireUnique(reminder.title, id: id, in: all)
            try TagShortcuts.requireInstalled()
            return [Change(.updated, subject: id, from: Self.render(plan.before), to: Self.render(plan.target),
                           detail: ["title": reminder.title])]
        } catch let error as CLIError {
            throw error.retry == nil ? error.with(retry: .notStarted) : error
        } catch {
            throw Self.translate(error)
        }
    }

    func apply(_ plan: [Change]) async throws -> [Change] {
        if install {
            return try plan.map { change in
                guard change.kind == .created else { return change }
                do {
                    let file = try TagShortcuts.offer()
                    return Change(.created, subject: change.subject, to: "Shortcuts",
                                  detail: ["file": file.path, "note": "click Add Shortcut to finish"], retry: .completed)
                } catch {
                    throw CLIError.upstream("Could not offer \(change.subject): \(error.localizedDescription)",
                                            service: "agenda").with(retry: .notStarted)
                }
            }
        }
        guard let change = plan.first, change.kind == .updated, let id else { return plan }
        // Read again just before the set: the helper overwrites, so the target is
        // built from the freshest tags there are. What changes in the second
        // between here and the helper running is lost — see TagShortcuts.
        let current = try StoreDetails.load().require(for: "Tagging").details(for: id)?.tags ?? []
        let tagPlan = TagPlan.make(current: current, add: add, remove: remove)
        let landed = try TagWriter().apply(tagPlan, id: id, title: change.detail["title"] ?? "")
        return [Change(.updated, subject: id, from: Self.render(current), to: Self.render(landed),
                       detail: change.detail.merging(["verified": "read back from the Reminders store"]) { _, new in new },
                       retry: .completed)]
    }

    static func render(_ tags: [String]) -> String {
        tags.isEmpty ? "(no tags)" : tags.map { "#\($0)" }.joined(separator: " ")
    }
}
