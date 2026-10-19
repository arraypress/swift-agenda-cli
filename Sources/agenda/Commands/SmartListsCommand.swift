//
//  SmartListsCommand.swift
//  agenda
//
//  Created by David Sherlock on 2026.
//
//  `agenda smartlists` — Reminders' smart lists, which EventKit cannot see.
//

import AgendaKit
import ArgumentParser
import CLIKit
import Foundation

struct SmartListsCommand: AgendaVerb {

    static let commandEffect = CommandEffect.readOnly

    static let configuration = CommandConfiguration(
        commandName: "smartlists",
        abstract: "List Reminders' smart lists and their rules (read-only).",
        discussion: """
            Read from Reminders' own store (a private copy; needs Full Disk Access for \\
            the terminal). Rules are the stored filter printed as key: value, uninterpreted. \\
            Built-in lists (today, flagged…) have no name of their own. --all includes them.
            """
    )

    @Flag(name: .long, help: "Include the built-in smart lists.")
    var all = false

    @OptionGroup var zone: ZoneOptions
    @OptionGroup var common: CommonOptions

    func execute() async throws {
        try zone.apply()
        let store = try StoreDetails.load().require(for: "Listing smart lists")
        let lists = store.smartLists.filter { all || $0.kind == "custom" }
        // Not `emit`: its empty-answer note is about hidden calendars, which says nothing here.
        if lists.isEmpty, common.format == .text { Terminal.writeLine("No smart lists."); return }
        try common.emitter.emitAll(lists.map(SmartListPayload.init))
    }
}

/// One smart list.
struct SmartListPayload: Encodable, TextRenderable, UntrustedContent {

    static var untrustedFields: Set<String> { AgendaUntrusted.fields }

    let list: SmartList

    init(_ list: SmartList) { self.list = list }

    func encode(to encoder: Encoder) throws { try list.encode(to: encoder) }

    func renderText() -> String {
        var lines = ["\(list.name.map { Untrusted.text($0) } ?? "(\(list.kind))")  [\(list.kind)]"]
        lines += (list.rules ?? ["(no readable rules)"]).map { "    \(Untrusted.text($0))" }
        lines.append("    \(list.id)")
        return lines.joined(separator: "\n")
    }
}
