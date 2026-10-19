//
//  StoreDetails.swift
//  agenda
//
//  Created by David Sherlock on 2026.
//
//  Tags, sections and subtasks beside EventKit's answer — or a note saying
//  why not.
//
//  THE STORE IS OPTIONAL AND EVENTKIT IS NOT. Reading Reminders' own database
//  needs Full Disk Access and a schema this tool recognises; neither is a
//  reason for `agenda reminders` to fail. Without them every reminder still
//  prints, without its tags, and one line on stderr says what is missing and
//  how to fix it. Only a command that cannot answer at all without the store
//  — a `--tag` filter, `smartlists` — fails, because filtering on data you
//  could not read would return a confident, wrong, empty list.
//

import AgendaKit
import CLIKit
import Foundation

/// The outcome of reading the Reminders store.
enum StoreDetails {
    case read(ReminderStoreContents)
    case unavailable(ReminderStoreError)

    /// Reads the store, never throwing.
    static func load(from folder: URL = RemindersStore.defaultFolder) -> StoreDetails {
        do {
            return .read(try RemindersStore.read(from: folder))
        } catch let error as ReminderStoreError {
            return .unavailable(error)
        } catch {
            return .unavailable(.readFailed(error.localizedDescription))
        }
    }

    var contents: ReminderStoreContents? {
        if case .read(let contents) = self { return contents }
        return nil
    }

    /// What to tell a person on stderr, or `nil` when there is nothing to add.
    var note: String? {
        switch self {
        case .unavailable(let error):
            return "Note: \(error.localizedDescription) "
                 + "Reminders are shown from EventKit without tags, sections or subtasks."
        case .read(let contents) where !contents.isKnownVersion:
            return "Note: the Reminders store is model \(contents.modelVersion ?? "unknown"), newer than "
                 + "the v2026_A this was checked against — tags and sections may be incomplete."
        case .read:
            return nil
        }
    }

    /// The store, or the error a command that cannot work without it throws.
    ///
    /// Full Disk Access refused is exit 3 — something must be granted first —
    /// and everything else is exit 5.
    func require(for purpose: String) throws -> ReminderStoreContents {
        switch self {
        case .read(let contents): return contents
        case .unavailable(let error):
            let message = "\(purpose) needs the Reminders store: \(error.localizedDescription)"
            if case .notPermitted = error {
                throw CLIError.authRequired(message, service: "agenda",
                                            hint: "System Settings ▸ Privacy & Security ▸ Full Disk Access")
            }
            throw CLIError.upstream(message, service: "agenda")
        }
    }

    /// Prints ``note`` unless `--quiet`.
    func warn(_ options: CommonOptions) {
        guard !options.quiet, let note else { return }
        Terminal.writeError(note)
    }
}
