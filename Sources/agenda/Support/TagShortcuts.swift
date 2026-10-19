//
//  TagShortcuts.swift
//  agenda
//
//  Created by David Sherlock on 2026.
//
//  Writing tags, the only way there is: through Shortcuts.
//
//  WHAT WAS MEASURED ON macOS 27 (2026-10-19), and why this shape:
//  - EventKit has no tag API, and a "#word" in a title saved through EventKit
//    stays text: a reminder created that way had no hashtag row in the store.
//  - Shortcuts' own "New Reminder" (is.workflow.actions.addnewreminder) has NO
//    tags parameter.
//  - Reminders' "Add or Remove Tags" App Intent
//    (com.apple.reminders.AddOrRemoveTagsAppIntent) is in the action catalogue
//    but NOT USABLE ON THE MAC: a shortcut containing it is refused on import
//    ("contains features not supported on this device"), and the Mac editor
//    does not list it.
//  - Shortcuts' "Edit Reminder" (is.workflow.actions.setters.reminders) on its
//    Tags property IS supported on the Mac. Its "Remove" mode shows correctly;
//    its "Add" mode is saved but behaves as SET — a live run replaced a
//    reminder's four tags with the one being added (caught by the read-back,
//    and put right). So only SET is used: agenda works out the whole tag list
//    the reminder should end with — what the store shows now, plus --add,
//    minus --remove — and the helper sets exactly that.
//  - Adding a shortcut takes a person's click (Shortcuts has no headless
//    import). The one helper, "agenda set tags", is offered by
//    `agenda tag --install`, and every write checks it is there first. The
//    earlier "agenda add tags" / "agenda remove tags" helpers are obsolete and
//    can be deleted; `tag` and `doctor` say so when they find them.
//  - The helper finds the reminder BY TITLE — no Shortcuts filter takes an
//    identifier — so a write is refused unless exactly one reminder (open or
//    completed, any list) has that title.
//
//  THE RACE, stated rather than hidden: SET overwrites. A tag added in
//  Reminders between agenda reading the store and the helper running (about
//  a second, re-read just before the run) is lost. Every write is then read
//  back from the store by identifier and must show exactly the target — no
//  tag more, none fewer — before it is reported as done.
//

import AgendaKit
import AppKit
import AppleShortcuts
import CLIKit
import Foundation

enum TagShortcuts {

    /// The helper's name — what it is added and run under.
    static let name = "agenda set tags"

    /// Helpers from the first design, which could not work on the Mac.
    static let obsoleteNames = ["agenda add tags", "agenda remove tags"]

    /// The helper. Input is JSON — `{"title": …, "tags": […]}` — and the tags are
    /// the reminder's whole list afterwards.
    static func recipe() -> Recipe {
        func variable(_ name: String) -> PlistValue {
            .dictionary(["Value": .dictionary(["Type": .string("Variable"), "VariableName": .string(name)]),
                         "WFSerializationType": .string("WFTextTokenAttachment")])
        }
        let titleToken: PlistValue = .dictionary([
            "Value": .dictionary([
                "string": .string("\u{FFFC}"),
                "attachmentsByRange": .dictionary(["{0, 1}": .dictionary(["Type": .string("Variable"),
                                                                          "VariableName": .string("agendaTitle")])]),
            ]),
            "WFSerializationType": .string("WFTextTokenString"),
        ])
        let titleIs: PlistValue = .dictionary([
            "Value": .dictionary([
                "WFActionParameterFilterPrefix": .integer(1),
                "WFContentPredicateBoundedDate": .bool(false),
                "WFActionParameterFilterTemplates": .array([.dictionary([
                    "Operator": .integer(4),     // "is"
                    "Property": .string("Title"),
                    "Removable": .bool(true),
                    "Values": .dictionary(["Unit": .integer(4), "String": titleToken]),
                ])]),
            ]),
            "WFSerializationType": .string("WFContentPredicateTableTemplate"),
        ])
        return Recipe(name: name, actions: [
            RecipeStep(action: "is.workflow.actions.detect.dictionary", parameters: ["WFInput": .string("$input")]),
            RecipeStep(action: "is.workflow.actions.setvariable",
                       parameters: ["WFVariableName": .string("agendaInput"), "WFInput": .string("$previous")]),
            RecipeStep(action: "is.workflow.actions.getvalueforkey",
                       parameters: ["WFGetDictionaryValueType": .string("Value"), "WFDictionaryKey": .string("tags"),
                                    "WFInput": variable("agendaInput")]),
            RecipeStep(action: "is.workflow.actions.setvariable",
                       parameters: ["WFVariableName": .string("agendaTags"), "WFInput": .string("$previous")]),
            RecipeStep(action: "is.workflow.actions.getvalueforkey",
                       parameters: ["WFGetDictionaryValueType": .string("Value"), "WFDictionaryKey": .string("title"),
                                    "WFInput": variable("agendaInput")]),
            RecipeStep(action: "is.workflow.actions.setvariable",
                       parameters: ["WFVariableName": .string("agendaTitle"), "WFInput": .string("$previous")]),
            RecipeStep(action: "is.workflow.actions.filter.reminders", parameters: ["WFContentItemFilter": titleIs]),
            // "Edit Reminder", SET mode only — see the header for why not Add.
            RecipeStep(action: "is.workflow.actions.setters.reminders", parameters: [
                "WFInput": .string("$previous"),
                "WFContentItemPropertyName": .string("Tags"),
                "Mode": .string("Set"),
                "WFReminderContentItemTags": variable("agendaTags"),
            ]),
            // Ends on nothing, so a run has no output for Shortcuts to ask about.
            RecipeStep(action: "is.workflow.actions.nothing"),
        ])
    }

    /// The JSON the helper is run with.
    static func input(title: String, tags: [String]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(["title": .string(title), "tags": .tags(tags)] as [String: InputValue])
    }

    enum InputValue: Encodable {
        case string(String), tags([String])
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let value): try container.encode(value)
            case .tags(let value): try container.encode(value)
            }
        }
    }

    /// What the library holds: whether the helper is there, and which obsolete
    /// helpers are.
    struct Status: Equatable {
        let installed: Bool
        let obsolete: [String]

        init(names: Set<String>) {
            installed = names.contains(TagShortcuts.name)
            obsolete = TagShortcuts.obsoleteNames.filter(names.contains)
        }

        /// The line to print about obsolete helpers, or `nil` when there are none.
        var obsoleteNote: String? {
            guard !obsolete.isEmpty else { return nil }
            return "Note: \(obsolete.map { "\"\($0)\"" }.joined(separator: " and ")) "
                 + "\(obsolete.count == 1 ? "is" : "are") no longer used by agenda and can be deleted in Shortcuts."
        }
    }

    static func status() throws -> Status {
        do {
            return Status(names: Set(try ShortcutLibrary().shortcuts().map(\.name)))
        } catch {
            throw CLIError.upstream("Could not list your shortcuts: \(error.localizedDescription)", service: "agenda")
        }
    }

    /// Refuses, before anything is attempted, when the helper is missing.
    /// Mentions obsolete helpers on stderr either way.
    @discardableResult
    static func requireInstalled() throws -> Status {
        let status = try status()
        if let note = status.obsoleteNote { Terminal.writeError(note) }
        guard status.installed else {
            throw CLIError(code: .authRequired,
                           message: "Tags are written through Shortcuts, and \"\(name)\" is not in your library",
                           hint: "agenda tag --install --yes, then click Add Shortcut",
                           service: "agenda", retry: .notStarted)
        }
        return status
    }

    /// Where offered helper files are written. Shortcuts reads the file after
    /// `open` returns, so it must outlive this process.
    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/agenda/shortcuts")
    }

    /// Writes, signs and offers the helper: Shortcuts shows its Add sheet.
    static func offer() throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = try ShortcutBuilder().write(recipe(), to: folder)
        try ShortcutBuilder.offer(file)
        return file
    }

    /// Runs the helper and waits — up to 30 s, since Shortcuts may first ask
    /// on screen whether it may use Reminders.
    static func run(input: Data) throws {
        _ = try ShortcutRunner.run(name, input: input, patience: 5, timeout: 30, onWaiting: {
            Terminal.writeError("Waiting on Shortcuts — it may be asking for permission on screen.")
        })
    }
}
