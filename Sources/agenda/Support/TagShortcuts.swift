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
//    import). The one helper, "agenda · Set Tags" — the fleet helper catalogue's
//    `agenda.set-tags`, in swift-apple-shortcuts — is offered by
//    `agenda tag --install`, and every write checks it is installed and
//    current first, and runs it by identifier. The helpers from before the
//    catalogue ("agenda set tags", "agenda add tags", "agenda remove tags")
//    are obsolete; `tag` and `doctor` say so when they find them.
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

    /// The helper, from the fleet's catalogue.
    static var helper: Helper {
        get throws {
            guard let helper = try HelperCatalogue.builtIn().helper("agenda.set-tags") else {
                throw CLIError.upstream("this build has no agenda.set-tags helper", service: "agenda")
            }
            return helper
        }
    }

    /// The helper's name — what it is added under: "agenda · Set Tags".
    static var name: String { (try? helper.name) ?? "agenda · Set Tags" }

    /// The JSON the helper is run with.
    static func input(title: String, tags: [String]) -> [String: PlistValue] {
        ["title": .string(title), "tags": .array(tags.map(PlistValue.string))]
    }

    /// What the library holds: whether the helper is there and runnable, and
    /// which obsolete helpers are.
    struct Status: Equatable {
        let installed: Bool
        let summary: String
        let obsolete: [String]

        /// The line to print about obsolete helpers, or `nil` when there are none.
        var obsoleteNote: String? {
            guard !obsolete.isEmpty else { return nil }
            return "Note: \(obsolete.map { "\"\($0)\"" }.joined(separator: " and ")) "
                 + "\(obsolete.count == 1 ? "is" : "are") no longer used by agenda and can be deleted in Shortcuts."
        }
    }

    static func status(host: any HelperHost = LiveHelperHost()) throws -> Status {
        do {
            let helper = try helper
            let status = try helper.status(host: host)
            let stale = try HelperCatalogue.builtIn().stale(for: "agenda", host: host)
            return Status(installed: status.isRunnable, summary: status.summary, obsolete: stale.map { $0.installedName ?? $0.name })
        } catch let error as CLIError {
            throw error
        } catch {
            throw CLIError.upstream("Could not list your shortcuts: \(error.localizedDescription)", service: "agenda")
        }
    }

    /// Refuses, before anything is attempted, unless the helper is installed
    /// and current. Mentions obsolete helpers on stderr either way.
    @discardableResult
    static func requireInstalled() throws -> Status {
        let status = try status()
        if let note = status.obsoleteNote { Terminal.writeError(note) }
        guard status.installed else {
            throw CLIError(code: .authRequired,
                           message: "Tags are written through Shortcuts, and \"\(name)\" is \(status.summary)",
                           hint: "agenda tag --install --yes, then click Add Shortcut",
                           service: "agenda", retry: .notStarted)
        }
        return status
    }

    /// Writes, signs and offers the helper: Shortcuts shows its Add sheet once.
    static func offer() throws -> URL {
        try helper.offer()
    }

    /// Runs the helper by identifier and waits — up to its timeout, since
    /// Shortcuts may first ask on screen whether it may use Reminders.
    static func run(input: [String: PlistValue]) throws {
        _ = try helper.run(input, onWaiting: {
            Terminal.writeError("Waiting on Shortcuts — it may be asking for permission on screen.")
        })
    }
}
