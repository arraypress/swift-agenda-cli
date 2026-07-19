//
//  Agenda+Events.swift
//  SwiftAgenda
//
//  Reading calendar events.
//
//  Created by David Sherlock on 7/19/26.
//

import EventKit
import Foundation

extension Agenda {

    /// Every event overlapping the window, oldest first.
    ///
    /// ```swift
    /// let today = try Agenda.events(from: .now, to: .now.addingTimeInterval(86_400))
    /// ```
    ///
    /// EventKit matches on overlap, not containment — an event that began before
    /// `start` and is still running is included, which is what "what am I in right
    /// now?" needs.
    ///
    /// - Parameters:
    ///   - start: Window start.
    ///   - end: Window end. Must be later than `start`.
    ///   - calendars: Calendar titles or identifiers to restrict to. Empty means all.
    /// - Throws: ``AgendaError/accessDenied(_:)`` or ``AgendaError/unknownCalendar(_:)``.
    public static func events(from start: Date, to end: Date, calendars: [String] = []) throws -> [AgendaEvent] {
        try requireAccess(to: .event)
        let resolved = try resolveCalendars(calendars, for: .event)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: resolved)
        return store.events(matching: predicate)
            .map(AgendaEvent.init)
            .sorted { $0.startsAt < $1.startsAt }
    }

    /// Events starting within `interval` from now.
    ///
    /// - Parameter interval: A forward window, e.g. `try Agenda.duration("7d")`.
    public static func upcoming(within interval: TimeInterval, calendars: [String] = []) throws -> [AgendaEvent] {
        let now = Date()
        return try events(from: now, to: now.addingTimeInterval(interval), calendars: calendars)
            .filter { $0.startsAt >= now }
    }

    /// Events falling on the calendar day containing `date`.
    public static func events(on date: Date, calendars: [String] = []) throws -> [AgendaEvent] {
        let calendar = Agenda.calendar
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return try events(from: start, to: end, calendars: calendars)
    }

    /// The single event with this identifier.
    ///
    /// - Parameters:
    ///   - id: The event identifier.
    ///   - occurrenceOn: For a repeating event, which occurrence to fetch. Omit for
    ///     a one-off, or to get the series' first occurrence.
    /// - Throws: ``AgendaError/notFound(_:)`` when nothing matches.
    public static func event(id: String, occurrenceOn date: Date? = nil) throws -> AgendaEvent {
        AgendaEvent(try ekEvent(id: id, occurrenceOn: date))
    }

    /// Resolves an identifier to the exact `EKEvent` instance the caller meant.
    ///
    /// `store.event(withIdentifier:)` returns the *first* occurrence of a series
    /// regardless of which one you were looking at, because every occurrence shares
    /// one identifier. Editing that result with `.thisEvent` therefore rewrites the
    /// wrong day — silently, and in a way that only shows up weeks later. When an
    /// occurrence date is supplied, the instance is located by date predicate instead.
    static func ekEvent(id: String, occurrenceOn date: Date?) throws -> EKEvent {
        try requireAccess(to: .event)

        guard let date else {
            guard let event = store.event(withIdentifier: id) else { throw AgendaError.notFound(id) }
            return event
        }

        // A one-day window around the occurrence: wide enough to survive a time-zone
        // difference between the caller's date and the stored start, narrow enough to
        // stay cheap.
        let from = calendar.startOfDay(for: date)
        let to = calendar.date(byAdding: .day, value: 1, to: from) ?? date.addingTimeInterval(86_400)
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)

        guard let match = store.events(matching: predicate).first(where: { $0.eventIdentifier == id }) else {
            throw AgendaError.notFound(id)
        }
        return match
    }

    /// The event in progress at `date`, if any.
    public static func current(at date: Date = Date(), calendars: [String] = []) throws -> AgendaEvent? {
        try events(on: date, calendars: calendars).first { $0.covers(date) && !$0.isAllDay }
    }

    /// Pairs of events on `date` whose times overlap.
    ///
    /// All-day events are excluded — they overlap everything by definition and would
    /// report a conflict against every timed event on the day.
    public static func conflicts(on date: Date = Date(), calendars: [String] = []) throws -> [(AgendaEvent, AgendaEvent)] {
        let timed = try events(on: date, calendars: calendars).filter { !$0.isAllDay }
        var found: [(AgendaEvent, AgendaEvent)] = []
        for i in timed.indices {
            for j in timed.index(after: i)..<timed.endIndex where timed[i].overlaps(timed[j]) {
                found.append((timed[i], timed[j]))
            }
        }
        return found
    }
}
