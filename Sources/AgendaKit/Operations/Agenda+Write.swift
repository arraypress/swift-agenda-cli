//
//  Agenda+Write.swift
//  SwiftAgenda
//
//  Creating, updating, and deleting events and reminders.
//
//  Created by David Sherlock on 7/19/26.
//

import EventKit
import Foundation

/// The fields needed to create an event.
public struct EventDraft: Sendable, Equatable {

    /// The event's title.
    public var title: String

    /// When it begins.
    public var startsAt: Date

    /// When it ends. Ignored when ``isAllDay`` is set.
    public var endsAt: Date

    /// Create an all-day marker rather than a timed event.
    public var isAllDay: Bool = false

    /// Free-text location.
    public var location: String?

    /// Notes body.
    public var notes: String?

    /// The event's URL field.
    public var url: String?

    /// Repeat rule. `nil` creates a one-off event.
    public var recurrence: Recurrence?

    /// Alerts to attach.
    public var alarms: [AgendaAlarm] = []

    /// How the event marks your time for free/busy purposes.
    public var availability: AgendaAvailability = .busy

    /// The event's time zone. `nil` creates a floating event in local time.
    public var timeZone: TimeZone?

    /// Target calendar title or identifier. `nil` uses EventKit's default.
    public var calendar: String?

    /// Describes an event to create.
    public init(title: String, startsAt: Date, endsAt: Date, isAllDay: Bool = false,
                location: String? = nil, notes: String? = nil, url: String? = nil,
                recurrence: Recurrence? = nil, alarms: [AgendaAlarm] = [],
                availability: AgendaAvailability = .busy, timeZone: TimeZone? = nil,
                calendar: String? = nil) {
        self.title = title
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.url = url
        self.recurrence = recurrence
        self.alarms = alarms
        self.availability = availability
        self.timeZone = timeZone
        self.calendar = calendar
    }
}

/// The fields needed to create a reminder.
public struct ReminderDraft: Sendable, Equatable {

    /// The reminder's title.
    public var title: String

    /// When it is due. Nil creates an unscheduled reminder.
    public var dueAt: Date?

    /// Notes body.
    public var notes: String?

    /// When the task becomes actionable, as distinct from when it is due.
    public var startsAt: Date?

    /// Whether ``dueAt`` should carry a time of day. False stores date-only
    /// components, which is how Reminders.app models "sometime Tuesday".
    public var dueHasTime: Bool = true

    /// EventKit's 0–9 scale, 0 meaning unset. 1 is highest.
    public var priority: Int = 0

    /// Repeat rule. `nil` creates a one-off reminder.
    public var recurrence: Recurrence?

    /// Alerts to attach.
    public var alarms: [AgendaAlarm] = []

    /// The reminder's URL field.
    public var url: String?

    /// Target list title or identifier. `nil` uses EventKit's default.
    public var list: String?

    /// Describes a reminder to create.
    public init(title: String, dueAt: Date? = nil, notes: String? = nil,
                startsAt: Date? = nil, dueHasTime: Bool = true, priority: Int = 0,
                recurrence: Recurrence? = nil, alarms: [AgendaAlarm] = [],
                url: String? = nil, list: String? = nil) {
        self.title = title
        self.dueAt = dueAt
        self.notes = notes
        self.startsAt = startsAt
        self.dueHasTime = dueHasTime
        self.priority = priority
        self.recurrence = recurrence
        self.alarms = alarms
        self.url = url
        self.list = list
    }
}

extension Agenda {

    // MARK: - Events

    /// Creates an event and returns it as saved.
    ///
    /// - Throws: ``AgendaError/unknownCalendar(_:)`` when `draft.calendar` matches
    ///   nothing, or ``AgendaError/storeFailure(_:)`` when EventKit refuses — most
    ///   often because the target calendar is subscribed and therefore read-only.
    @discardableResult
    public static func createEvent(_ draft: EventDraft) throws -> AgendaEvent {
        try requireAccess(to: .event)

        let event = EKEvent(eventStore: store)
        event.title = draft.title
        event.startDate = draft.startsAt
        event.endDate = draft.endsAt
        event.isAllDay = draft.isAllDay
        event.location = draft.location
        event.notes = draft.notes
        event.url = draft.url.flatMap(URL.init(string:))
        event.timeZone = draft.timeZone
        // Calendar must be assigned before availability: EventKit validates the value
        // against the target calendar's `supportedEventAvailabilities`, and silently
        // discards an unsupported one — so setting it first reverts it to `.busy`.
        event.calendar = try writableCalendar(draft.calendar, for: .event)
        event.availability = draft.availability.ekAvailability
        if let recurrence = draft.recurrence {
            event.recurrenceRules = [recurrence.ekRule]
        }
        for alarm in draft.alarms {
            event.addAlarm(alarm.ekAlarm)
        }

        do {
            // `.futureEvents` on a brand-new recurring event is equivalent to
            // `.thisEvent` — there is no earlier occurrence to leave behind — so the
            // narrower span is used unconditionally here.
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            throw AgendaError.storeFailure(error.localizedDescription)
        }
        return AgendaEvent(event)
    }

    /// Applies non-nil fields of `changes` to an existing event.
    ///
    /// - Parameters:
    ///   - id: The event identifier.
    ///   - changes: Only the populated fields are written.
    ///   - span: Required when the event repeats. See ``AgendaSpan``.
    ///   - occurrenceOn: Which occurrence of a repeating event to edit. Without it,
    ///     EventKit resolves the identifier to the series' *first* occurrence — so
    ///     `.this` would edit the wrong day.
    /// - Throws: ``AgendaError/spanRequired(_:)`` when the event recurs and `span`
    ///   is nil, ``AgendaError/notFound(_:)``, or ``AgendaError/storeFailure(_:)``.
    @discardableResult
    public static func updateEvent(id: String, with changes: EventChanges,
                                   span: AgendaSpan? = nil,
                                   occurrenceOn date: Date? = nil) throws -> AgendaEvent {
        let event = try ekEvent(id: id, occurrenceOn: date)
        let resolvedSpan = try Self.span(for: event, requested: span)

        if let title = changes.title { event.title = title }
        if let startsAt = changes.startsAt { event.startDate = startsAt }
        if let endsAt = changes.endsAt { event.endDate = endsAt }
        if let isAllDay = changes.isAllDay { event.isAllDay = isAllDay }
        if let location = changes.location { event.location = location }
        if let notes = changes.notes { event.notes = notes }
        if let calendar = changes.calendar {
            event.calendar = try writableCalendar(calendar, for: .event)
        }
        if let availability = changes.availability {
            event.availability = availability.ekAvailability
        }
        if let recurrence = changes.recurrence {
            // An explicitly empty rule set clears the series rather than repeating it.
            event.recurrenceRules = recurrence.map { [$0.ekRule] } ?? []
        }
        if let alarms = changes.alarms {
            event.alarms?.forEach(event.removeAlarm)
            alarms.forEach { event.addAlarm($0.ekAlarm) }
        }

        do {
            try store.save(event, span: resolvedSpan, commit: true)
        } catch {
            throw AgendaError.storeFailure(error.localizedDescription)
        }
        return AgendaEvent(event)
    }

    /// Deletes an event.
    ///
    /// - Parameters:
    ///   - span: Required when the event repeats — `.future` removes every remaining
    ///     occurrence, which is not recoverable.
    ///   - occurrenceOn: Which occurrence to remove. See ``updateEvent(id:with:span:occurrenceOn:)``
    ///     for why omitting it targets the first occurrence rather than the intended one.
    public static func deleteEvent(id: String, span: AgendaSpan? = nil, occurrenceOn date: Date? = nil) throws {
        let event = try ekEvent(id: id, occurrenceOn: date)
        let resolvedSpan = try Self.span(for: event, requested: span)

        do {
            try store.remove(event, span: resolvedSpan, commit: true)
        } catch {
            throw AgendaError.storeFailure(error.localizedDescription)
        }
    }

    // MARK: - Reminders

    /// Creates a reminder and returns it as saved.
    @discardableResult
    public static func createReminder(_ draft: ReminderDraft) throws -> AgendaReminder {
        try requireAccess(to: .reminder)

        let reminder = EKReminder(eventStore: store)
        reminder.title = draft.title
        reminder.notes = draft.notes
        reminder.priority = draft.priority
        reminder.url = draft.url.flatMap(URL.init(string:))
        reminder.calendar = try writableCalendar(draft.list, for: .reminder)

        // Omitting `.hour`/`.minute` is what makes a reminder all-day; supplying them
        // as zero would instead pin it to midnight, which Reminders.app renders as a
        // timed alert at 12:00 AM.
        let fields: Set<Calendar.Component> = draft.dueHasTime
            ? [.year, .month, .day, .hour, .minute]
            : [.year, .month, .day]
        if let dueAt = draft.dueAt {
            reminder.dueDateComponents = Self.calendar.dateComponents(fields, from: dueAt)
        }
        if let startsAt = draft.startsAt {
            reminder.startDateComponents = Self.calendar.dateComponents(fields, from: startsAt)
        }
        if let recurrence = draft.recurrence {
            reminder.recurrenceRules = [recurrence.ekRule]
        }
        for alarm in draft.alarms {
            reminder.addAlarm(alarm.ekAlarm)
        }

        do {
            try store.save(reminder, commit: true)
        } catch {
            throw AgendaError.storeFailure(error.localizedDescription)
        }
        return AgendaReminder(reminder)
    }

    /// Marks a reminder complete, or reopens it.
    @discardableResult
    public static func completeReminder(id: String, completed: Bool = true) throws -> AgendaReminder {
        try updateReminder(id: id, with: ReminderChanges(isCompleted: completed))
    }

    /// Applies non-nil fields of `changes` to an existing reminder.
    ///
    /// Every `EKReminder` property is writable, so unlike events there is no span to
    /// worry about — a recurring reminder edits in place.
    ///
    /// - Parameters:
    ///   - id: The reminder identifier.
    ///   - changes: Only the populated fields are written.
    /// - Throws: ``AgendaError/notFound(_:)`` when nothing matches, or
    ///   ``AgendaError/storeFailure(_:)`` when EventKit refuses the save.
    @discardableResult
    public static func updateReminder(id: String, with changes: ReminderChanges) throws -> AgendaReminder {
        try requireAccess(to: .reminder)
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw AgendaError.notFound(id)
        }

        if let title = changes.title { reminder.title = title }
        if let notes = changes.notes { reminder.notes = notes }
        if let priority = changes.priority { reminder.priority = priority }
        if let isCompleted = changes.isCompleted { reminder.isCompleted = isCompleted }
        if let url = changes.url { reminder.url = URL(string: url) }
        if let list = changes.list {
            reminder.calendar = try writableCalendar(list, for: .reminder)
        }

        // Whether the due date carries a time is itself an edit — moving "sometime
        // Tuesday" to "Tuesday at 3pm" changes only the component set.
        let fields: Set<Calendar.Component> = (changes.dueHasTime ?? true)
            ? [.year, .month, .day, .hour, .minute]
            : [.year, .month, .day]
        if let dueAt = changes.dueAt {
            reminder.dueDateComponents = dueAt.map { calendar.dateComponents(fields, from: $0) }
        }
        if let startsAt = changes.startsAt {
            reminder.startDateComponents = startsAt.map { calendar.dateComponents(fields, from: $0) }
        }
        if let recurrence = changes.recurrence {
            reminder.recurrenceRules = recurrence.map { [$0.ekRule] } ?? []
        }
        if let alarms = changes.alarms {
            reminder.alarms?.forEach(reminder.removeAlarm)
            alarms.forEach { reminder.addAlarm($0.ekAlarm) }
        }

        do {
            try store.save(reminder, commit: true)
        } catch {
            throw AgendaError.storeFailure(error.localizedDescription)
        }
        return AgendaReminder(reminder)
    }

    /// Deletes a reminder.
    public static func deleteReminder(id: String) throws {
        try requireAccess(to: .reminder)
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw AgendaError.notFound(id)
        }
        do {
            try store.remove(reminder, commit: true)
        } catch {
            throw AgendaError.storeFailure(error.localizedDescription)
        }
    }

    // MARK: - Internal

    /// Resolves a target calendar, refusing read-only ones up front.
    ///
    /// EventKit only rejects a write to a subscribed calendar at save time, by which
    /// point a caller has already reported success to whoever asked for it.
    private static func writableCalendar(_ name: String?, for entity: EKEntityType) throws -> EKCalendar {
        guard let name else {
            guard let fallback = entity == .reminder
                    ? store.defaultCalendarForNewReminders()
                    : store.defaultCalendarForNewEvents else {
                throw AgendaError.storeFailure("No default calendar is configured.")
            }
            return fallback
        }
        guard let resolved = try resolveCalendars([name], for: entity)?.first else {
            throw AgendaError.unknownCalendar(name)
        }
        guard resolved.allowsContentModifications else {
            throw AgendaError.storeFailure("\"\(resolved.title)\" is read-only.")
        }
        return resolved
    }

    /// The `EKSpan` to apply, refusing to guess for a recurring event.
    private static func span(for event: EKEvent, requested: AgendaSpan?) throws -> EKSpan {
        guard event.hasRecurrenceRules else { return .thisEvent }
        guard let requested else { throw AgendaError.spanRequired(event.title ?? "This event") }
        return requested.ekSpan
    }
}

/// Fields to change on an existing event. Nil means "leave alone".
public struct EventChanges: Sendable, Equatable {

    /// New title, or nil to leave it.
    public var title: String?

    /// New start time, or nil to leave it.
    public var startsAt: Date?

    /// New end time, or nil to leave it.
    public var endsAt: Date?

    /// New all-day flag, or nil to leave it.
    public var isAllDay: Bool?

    /// New location, or nil to leave it.
    public var location: String?

    /// New notes, or nil to leave them.
    public var notes: String?

    /// Move to this calendar, or nil to leave it where it is.
    public var calendar: String?

    /// New free/busy marking, or nil to leave it.
    public var availability: AgendaAvailability?

    /// Double-optional on purpose: `nil` leaves the rule alone, `.some(nil)` clears it,
    /// `.some(rule)` replaces it. Collapsing these would make "stop repeating"
    /// unexpressible.
    public var recurrence: Recurrence??

    /// Replaces the whole alarm set. `.some([])` removes every alert.
    public var alarms: [AgendaAlarm]?

    /// Whether anything at all would change.
    public var isEmpty: Bool {
        title == nil && startsAt == nil && endsAt == nil && isAllDay == nil
            && location == nil && notes == nil && calendar == nil
            && availability == nil && recurrence == nil && alarms == nil
    }

    /// Describes a set of edits. Every field defaults to "leave alone".
    public init(title: String? = nil, startsAt: Date? = nil, endsAt: Date? = nil,
                isAllDay: Bool? = nil, location: String? = nil, notes: String? = nil,
                calendar: String? = nil, availability: AgendaAvailability? = nil,
                recurrence: Recurrence?? = nil, alarms: [AgendaAlarm]? = nil) {
        self.title = title
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.calendar = calendar
        self.availability = availability
        self.recurrence = recurrence
        self.alarms = alarms
    }
}

/// Fields to change on an existing reminder. Nil means "leave alone".
///
/// Several fields are double-optional so that clearing stays expressible: `nil`
/// leaves the value untouched, `.some(nil)` removes it, `.some(value)` replaces it.
/// Collapsing them would make "remove the due date" impossible to say.
public struct ReminderChanges: Sendable, Equatable {

    /// New title, or nil to leave it.
    public var title: String?

    /// New notes, or nil to leave them.
    public var notes: String?

    /// New due date; `.some(nil)` clears it, unscheduling the reminder.
    public var dueAt: Date??

    /// New start date; `.some(nil)` clears it.
    public var startsAt: Date??

    /// Whether the due date should carry a time of day. Defaults to true.
    public var dueHasTime: Bool?

    /// New priority on EventKit's 0–9 scale, where 0 clears it and 1 is highest.
    public var priority: Int?

    /// Tick off or reopen.
    public var isCompleted: Bool?

    /// New URL, or nil to leave it.
    public var url: String?

    /// Move to this reminder list.
    public var list: String?

    /// New repeat rule; `.some(nil)` stops it repeating.
    public var recurrence: Recurrence??

    /// Replaces the whole alarm set. `.some([])` removes every alert.
    public var alarms: [AgendaAlarm]?

    /// Whether anything at all would change.
    public var isEmpty: Bool {
        title == nil && notes == nil && dueAt == nil && startsAt == nil
            && dueHasTime == nil && priority == nil && isCompleted == nil
            && url == nil && list == nil && recurrence == nil && alarms == nil
    }

    /// Describes a set of edits. Every field defaults to "leave alone".
    public init(title: String? = nil, notes: String? = nil, dueAt: Date?? = nil,
                startsAt: Date?? = nil, dueHasTime: Bool? = nil, priority: Int? = nil,
                isCompleted: Bool? = nil, url: String? = nil, list: String? = nil,
                recurrence: Recurrence?? = nil, alarms: [AgendaAlarm]? = nil) {
        self.title = title
        self.notes = notes
        self.dueAt = dueAt
        self.startsAt = startsAt
        self.dueHasTime = dueHasTime
        self.priority = priority
        self.isCompleted = isCompleted
        self.url = url
        self.list = list
        self.recurrence = recurrence
        self.alarms = alarms
    }
}
