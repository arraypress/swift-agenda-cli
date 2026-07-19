//
//  AgendaReminder.swift
//  SwiftAgenda
//
//  A reminder flattened out of EventKit into a serializable value.
//
//  Created by David Sherlock on 7/19/26.
//

import EventKit
import Foundation

/// One reminder, detached from its `EKReminder`.
///
/// Built by ``Agenda/reminders(matching:)``.
public struct AgendaReminder: Codable, Sendable, Equatable, Identifiable {

    /// EventKit's calendar-item identifier.
    public let id: String

    /// The reminder's title, or "Untitled" when it has none.
    public let title: String

    /// The reminder list this belongs to — EventKit models lists as calendars.
    public let list: String

    /// The reminder's notes body.
    public let notes: String?

    /// When the reminder becomes relevant. Distinct from ``dueAt`` — a task can be
    /// startable on Monday and not due until Friday.
    public let startsAt: Date?

    /// When it is due. Nil for an unscheduled reminder, which is still open work.
    public let dueAt: Date?

    /// True when ``dueAt`` carries no time of day, i.e. "sometime Tuesday".
    public let isDueAllDay: Bool

    /// Whether it has been ticked off.
    public let isCompleted: Bool

    /// When it was completed, when known.
    public let completedAt: Date?

    /// EventKit's 0–9 scale, where 0 means unset. See ``priorityLabel``.
    public let priority: Int

    /// The repeat rule, for recurring reminders.
    public let recurrence: Recurrence?

    /// Alerts set on this reminder.
    public let alarms: [AgendaAlarm]

    /// The reminder's URL field.
    public let url: String?

    /// When the reminder was created.
    public let createdAt: Date?

    /// When the reminder was last changed.
    public let modifiedAt: Date?

    /// True when a due date exists and has passed, and the reminder is still open.
    public var isOverdue: Bool {
        guard let dueAt, !isCompleted else { return false }
        return dueAt < Date()
    }

    /// Whether this belongs to a repeating series.
    public var isRecurring: Bool { recurrence != nil }

    /// The 0–9 priority as the label Reminders.app shows.
    ///
    /// Apple's mapping is non-obvious and inverted — 1 is the *highest* — so it is
    /// spelled out here rather than left as a bare integer.
    public var priorityLabel: String? {
        switch priority {
        case 1...4: return "high"
        case 5:     return "medium"
        case 6...9: return "low"
        default:    return nil
        }
    }

    /// Creates a reminder record.
    public init(id: String, title: String, list: String, notes: String? = nil,
                startsAt: Date? = nil, dueAt: Date? = nil, isDueAllDay: Bool = false,
                isCompleted: Bool = false, completedAt: Date? = nil, priority: Int = 0,
                recurrence: Recurrence? = nil, alarms: [AgendaAlarm] = [],
                url: String? = nil, createdAt: Date? = nil, modifiedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.list = list
        self.notes = notes
        self.startsAt = startsAt
        self.dueAt = dueAt
        self.isDueAllDay = isDueAllDay
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.priority = priority
        self.recurrence = recurrence
        self.alarms = alarms
        self.url = url
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

// MARK: - EventKit bridging

extension AgendaReminder {

    /// Flattens an `EKReminder`.
    ///
    /// Due dates arrive as `DateComponents` rather than a `Date` because an all-day
    /// reminder genuinely has no time of day; the absence of `.hour` is what
    /// distinguishes "due Tuesday" from "due Tuesday at 3pm", and that distinction is
    /// preserved in ``AgendaReminder/isDueAllDay`` rather than being flattened away.
    init(_ reminder: EKReminder) {
        let due = reminder.dueDateComponents
        self.init(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "Untitled",
            list: reminder.calendar?.title ?? "Unknown",
            notes: reminder.notes?.nilIfBlank,
            startsAt: reminder.startDateComponents?.date,
            dueAt: due?.date,
            isDueAllDay: due != nil && due?.hour == nil,
            isCompleted: reminder.isCompleted,
            completedAt: reminder.completionDate,
            priority: reminder.priority,
            recurrence: reminder.recurrenceRules?.first.map(Recurrence.init),
            alarms: reminder.alarms?.map(AgendaAlarm.init) ?? [],
            url: reminder.url?.absoluteString,
            createdAt: reminder.creationDate,
            modifiedAt: reminder.lastModifiedDate
        )
    }
}
