//
//  TagWriter.swift
//  agenda
//
//  Created by David Sherlock on 2026.
//
//  Running the tag helper and believing only the store.
//
//  The helper SETS a reminder's whole tag list (see TagShortcuts for why). A
//  shortcut that exits 0 has finished running; it has not shown the tags are
//  right. So every write is read back from the Reminders store, by the
//  reminder's identifier, until the tags are exactly the target — no more, no
//  fewer — or the wait runs out. The verdict follows the store, not Shortcuts.
//

import AgendaKit
import AppleShortcuts
import CLIKit
import Foundation

/// A tag edit: the reminder's tags now, and the whole list it should end with.
struct TagPlan: Equatable {
    let before: [String]
    let target: [String]

    /// Whether the target is what is there already.
    var isEmpty: Bool { TagPlan.same(before, target) }

    /// `current` plus `add` minus `remove`. `#` and blanks are dropped; spellings
    /// that differ only in case or accents are one tag, and an existing
    /// spelling is kept.
    static func make(current: [String], add: [String], remove: [String]) -> TagPlan {
        let gone = Set(clean(remove).map(ReminderTree.key))
        var seen = Set<String>()
        let target = (current + clean(add)).filter {
            let key = ReminderTree.key($0)
            return !gone.contains(key) && seen.insert(key).inserted
        }
        return TagPlan(before: current, target: target)
    }

    /// Tags as given, without `#`, blanks or repeats.
    static func clean(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert(ReminderTree.key($0)).inserted }
    }

    /// The same tags, ignoring order, case and accents — and counting, so a
    /// duplicate in the store is not "the same" as one tag.
    static func same(_ lhs: [String], _ rhs: [String]) -> Bool {
        lhs.map(ReminderTree.key).sorted() == rhs.map(ReminderTree.key).sorted()
    }
}

struct TagWriter {

    /// Runs the helper.
    var run: ([String: PlistValue]) throws -> Void = { try TagShortcuts.run(input: $0) }

    /// What the helper's title filter finds, run in check mode (changes nothing).
    var check: (String) throws -> [String] = { title in
        try TagShortcuts.helper.check(["title": .string(title), "tags": .array([])])
    }

    /// The reminder's tags as the store has them now; `nil` while it has no row.
    var readTags: (String) throws -> [String]? = { id in
        try RemindersStore.read().details(for: id)?.tags
    }

    var attempts = 24
    var interval: TimeInterval = 0.25

    /// Sets the reminder `id`, titled `title`, to `plan.target`.
    ///
    /// - Returns: The tags the store shows, matching the target exactly.
    /// - Throws: A ``CLIError`` naming what was expected and what the store
    ///   shows, with the verdict the store supports.
    func apply(_ plan: TagPlan, id: String, title: String) throws -> [String] {
        // The helper SETS tags on whatever its filter finds. Before it acts, it
        // is asked what it would find: exactly this one reminder, or nothing runs.
        let found = try check(title)
        let wanted = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard found.count == 1, found[0].lowercased() == wanted else {
            throw CLIError(code: .upstream,
                           message: "The tag helper's filter finds \(found.count) reminder\(found.count == 1 ? "" : "s") for \"\(title)\""
                               + (found.isEmpty ? "" : " (\(found.prefix(3).joined(separator: ", "))\(found.count > 3 ? ", …" : ""))")
                               + ", not exactly this one — nothing was changed",
                           hint: "the helper would have set tags on every reminder it found; check the reminder's title in Reminders",
                           service: "agenda", retry: .notStarted)
        }
        var runFailure: Error?
        do {
            try run(TagShortcuts.input(title: title, tags: plan.target))
        } catch {
            runFailure = error
        }

        var seen: [String]?
        for attempt in 0..<attempts {
            seen = try? readTags(id)
            if let seen, TagPlan.same(seen, plan.target) { return seen }
            // A failed run is not waited out — unless it timed out, when it may still land.
            if runFailure != nil, !Self.timedOut(runFailure), attempt >= 3 { break }
            Thread.sleep(forTimeInterval: interval)
        }

        let unchanged = seen.map { TagPlan.same($0, plan.before) } ?? true
        let verdict: RetryVerdict = unchanged && !Self.timedOut(runFailure) ? .notStarted : .mayHaveCompleted
        let reason = runFailure.map { " The shortcut failed: \($0.localizedDescription)." } ?? ""
        throw CLIError(code: .upstream,
                       message: "Tags not as asked on \(id): expected \(Self.render(plan.target)), "
                              + "the store shows \(seen.map(Self.render) ?? "no row for it")."
                              + (unchanged ? " Nothing changed." : "") + reason,
                       hint: verdict == .notStarted
                           ? "run `shortcut run \"\(TagShortcuts.name)\"` by hand to see Shortcuts' error"
                           : "look at the reminder in Reminders before trying again",
                       service: "agenda", retry: verdict)
    }

    static func render(_ tags: [String]) -> String {
        tags.isEmpty ? "(no tags)" : tags.map { "#\($0)" }.joined(separator: " ")
    }

    static func timedOut(_ error: Error?) -> Bool {
        if case .timedOut = error as? ShortcutsError { return true }
        return false
    }
}

/// Exactly one reminder with this title, or why a tag write by title would guess.
enum TitleMatch {

    /// Reminders whose title is `title`, ignoring case and surrounding space —
    /// as loosely as Shortcuts' "Title is" might match.
    static func matches(_ title: String, in reminders: [AgendaReminder]) -> [AgendaReminder] {
        let wanted = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return reminders.filter { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == wanted }
    }

    /// Throws a usage error unless `id` is the only reminder titled `title`.
    static func requireUnique(_ title: String, id: String?, in reminders: [AgendaReminder]) throws {
        let all = matches(title, in: reminders)
        guard all.allSatisfy({ $0.id == id }) else {
            throw CLIError(code: .usage,
                           message: "\(all.count + (id == nil ? 1 : 0)) reminders would be titled \"\(title)\", and Shortcuts finds reminders by title — tagging would be a guess",
                           hint: "rename one (agenda edit <id> --title …) and try again",
                           service: "agenda", retry: .notStarted)
        }
    }
}
