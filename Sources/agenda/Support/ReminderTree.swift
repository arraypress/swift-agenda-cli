//
//  ReminderTree.swift
//  agenda
//
//  Created by David Sherlock on 2026.
//
//  Filtering on tags and sections, and the order a list prints in: sections
//  in turn, subtasks under their parent.
//

import AgendaKit
import Foundation

/// One reminder in printing order, with what the store says about it.
struct PlacedReminder: Equatable {
    let reminder: AgendaReminder
    let details: ReminderStoreDetails?
    /// 0 for a top-level reminder, 1 for a subtask printed under its parent.
    let depth: Int
}

/// A run of reminders under one section heading — `nil` for those in none.
struct SectionGroup: Equatable {
    let section: String?
    let reminders: [PlacedReminder]
}

enum ReminderTree {

    /// A tag as compared: no `#`, case and accents folded.
    static func key(_ tag: String) -> String {
        let bare = tag.hasPrefix("#") ? String(tag.dropFirst()) : tag
        return bare.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Reminders carrying ANY of `tags` and sitting in ANY of `sections` — an
    /// empty filter passes everything, as `--list` does.
    static func filter(_ reminders: [AgendaReminder], tags: [String], sections: [String],
                       store: ReminderStoreContents?) -> [AgendaReminder] {
        guard !tags.isEmpty || !sections.isEmpty else { return reminders }
        let wantedTags = Set(tags.map(key))
        let wantedSections = Set(sections.map(key))
        return reminders.filter { reminder in
            let details = store?.details(for: reminder.id)
            if !wantedTags.isEmpty, !(details?.tags ?? []).contains(where: { wantedTags.contains(key($0)) }) {
                return false
            }
            if !wantedSections.isEmpty, !wantedSections.contains(key(details?.section ?? "\u{0}")) {
                return false
            }
            return true
        }
    }

    /// Subtasks moved under their parent, keeping the incoming order otherwise.
    /// A subtask whose parent is not in `reminders` stays where it was, at depth 0.
    static func nest(_ reminders: [AgendaReminder], store: ReminderStoreContents?) -> [PlacedReminder] {
        let details = reminders.map { store?.details(for: $0.id) }
        let present = Set(details.compactMap { $0?.id })
        var children: [String: [Int]] = [:]
        var roots: [Int] = []
        for (index, detail) in details.enumerated() {
            if let parent = detail?.parentID, present.contains(parent), parent != detail?.id {
                children[parent, default: []].append(index)
            } else {
                roots.append(index)
            }
        }
        var placed: [PlacedReminder] = []
        var seen = Set<Int>()
        func place(_ index: Int, depth: Int) {
            guard seen.insert(index).inserted else { return }
            placed.append(PlacedReminder(reminder: reminders[index], details: details[index], depth: depth))
            for child in children[details[index]?.id ?? ""] ?? [] { place(child, depth: depth + 1) }
        }
        roots.forEach { place($0, depth: 0) }
        // A cycle leaves its members unplaced; print them flat rather than lose them.
        for index in reminders.indices where !seen.contains(index) { place(index, depth: 0) }
        return placed
    }

    /// Placed reminders grouped by section: those in none first, then each
    /// section in the store's order. A subtask follows its parent's section.
    static func group(_ placed: [PlacedReminder], store: ReminderStoreContents?) -> [SectionGroup] {
        var current: String?
        var sectionOf: [Int: String?] = [:]
        for (index, item) in placed.enumerated() {
            if item.depth == 0 { current = item.details?.section }
            sectionOf[index] = item.depth == 0 ? item.details?.section : current
        }
        let order = (store?.sections.map(\.name) ?? [])
        var names: [String] = []
        for name in order where !names.contains(name) { names.append(name) }
        for (index, _) in placed.enumerated() {
            if let name = sectionOf[index] ?? nil, !names.contains(name) { names.append(name) }
        }
        var groups: [SectionGroup] = []
        let loose = placed.indices.filter { (sectionOf[$0] ?? nil) == nil }.map { placed[$0] }
        if !loose.isEmpty { groups.append(SectionGroup(section: nil, reminders: loose)) }
        for name in names {
            let members = placed.indices.filter { (sectionOf[$0] ?? nil) == name }.map { placed[$0] }
            if !members.isEmpty { groups.append(SectionGroup(section: name, reminders: members)) }
        }
        return groups
    }
}

extension SearchResult {
    /// Whether this hit is a reminder, which is what the store has anything to say about.
    var isReminder: Bool {
        if case .reminder = self { return true }
        return false
    }
}
