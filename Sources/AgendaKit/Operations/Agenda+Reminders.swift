//
//  Agenda+Reminders.swift
//  SwiftAgenda
//
//  Reading reminders.
//
//  Created by David Sherlock on 7/19/26.
//

import EventKit
import Foundation

/// What to include when listing reminders.
public struct ReminderFilter: Sendable, Equatable {

    /// Reminder list titles or identifiers to restrict to. Empty means all.
    public var lists: [String] = []

    /// Include reminders already ticked off.
    public var includeCompleted: Bool = false

    /// Only reminders due within this many seconds from now. `nil` means no due filter,
    /// which also keeps reminders that have no due date at all.
    public var dueWithin: TimeInterval?

    /// Only reminders whose due date has already passed.
    public var overdueOnly: Bool = false

    /// Cap on returned rows. `nil` means uncapped.
    public var limit: Int?

    /// Creates a filter. Defaults to open reminders across every list.
    public init(lists: [String] = [], includeCompleted: Bool = false,
                dueWithin: TimeInterval? = nil, overdueOnly: Bool = false, limit: Int? = nil) {
        self.lists = lists
        self.includeCompleted = includeCompleted
        self.dueWithin = dueWithin
        self.overdueOnly = overdueOnly
        self.limit = limit
    }
}

extension Agenda {

    /// Reminders matching `filter`, due soonest first.
    ///
    /// ```swift
    /// var filter = ReminderFilter()
    /// filter.dueWithin = try Agenda.duration("7d")
    /// let soon = try await Agenda.reminders(matching: filter)
    /// ```
    ///
    /// `fetchReminders(matching:)` is callback-only with no async variant, so it is
    /// bridged through a continuation here. EventKit fires the callback exactly once,
    /// including on failure (where it passes nil).
    ///
    /// - Throws: ``AgendaError/accessDenied(_:)`` or ``AgendaError/unknownCalendar(_:)``.
    public static func reminders(matching filter: ReminderFilter = .init()) async throws -> [AgendaReminder] {
        try requireAccess(to: .reminder)
        let resolved = try resolveCalendars(filter.lists, for: .reminder)
        let predicate = store.predicateForReminders(in: resolved)

        let fetched: [EKReminder] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }

        let now = Date()
        let cutoff = filter.dueWithin.map { now.addingTimeInterval($0) }

        var results = fetched
            .map(AgendaReminder.init)
            .filter { reminder in
                if !filter.includeCompleted && reminder.isCompleted { return false }
                if filter.overdueOnly && !reminder.isOverdue { return false }
                if let cutoff {
                    guard let due = reminder.dueAt else { return false }
                    if due > cutoff { return false }
                }
                return true
            }
            .sorted { lhs, rhs in
                // Undated reminders sort last rather than being dropped — they are
                // still open work, just unscheduled.
                switch (lhs.dueAt, rhs.dueAt) {
                case let (l?, r?): return l < r
                case (nil, _?):    return false
                case (_?, nil):    return true
                default:           return lhs.title < rhs.title
                }
            }

        if let limit = filter.limit, results.count > limit {
            results = Array(results.prefix(limit))
        }
        return results
    }

    /// Open reminders whose due date has passed.
    public static func overdueReminders(lists: [String] = []) async throws -> [AgendaReminder] {
        try await reminders(matching: ReminderFilter(lists: lists, overdueOnly: true))
    }
}
