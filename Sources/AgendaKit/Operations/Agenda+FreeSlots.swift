//
//  Agenda+FreeSlots.swift
//  SwiftAgenda
//
//  Finding unbooked windows between events.
//
//  Created by David Sherlock on 7/19/26.
//

import Foundation

extension Agenda {

    /// Gaps of at least `interval` between now and `end`.
    ///
    /// ```swift
    /// let slots = try Agenda.freeSlots(
    ///     ofAtLeast: try Agenda.duration("30m"),
    ///     through: Date().addingTimeInterval(try Agenda.duration("7d"))
    /// )
    /// ```
    ///
    /// Walks the event list once, tracking the running end of the busy period. Events
    /// are merged as it goes, so back-to-back and overlapping meetings collapse into a
    /// single block rather than producing zero-length gaps between them.
    ///
    /// Only events that genuinely consume time count as busy (see
    /// ``AgendaEvent/blocksTime``). All-day markers, events you set to "free", and
    /// cancelled invitations are all skipped — otherwise every holiday reads as a
    /// fully booked day and a declined meeting keeps blocking its slot.
    ///
    /// - Parameters:
    ///   - interval: The minimum gap worth returning.
    ///   - start: When to begin looking. Defaults to now.
    ///   - end: When to stop looking.
    ///   - hours: An optional daily working window to clip slots to.
    /// - Returns: Gaps in chronological order.
    public static func freeSlots(ofAtLeast interval: TimeInterval,
                                 from start: Date = Date(),
                                 through end: Date,
                                 within hours: WorkingHours? = nil,
                                 calendars: [String] = []) throws -> [FreeSlot] {
        guard end > start else { return [] }
        let busy = try events(from: start, to: end, calendars: calendars)
            .filter(\.blocksTime)
            .sorted { $0.startsAt < $1.startsAt }

        var slots: [FreeSlot] = []
        var cursor = start

        for event in busy {
            if event.startsAt > cursor {
                slots.append(FreeSlot(startsAt: cursor, endsAt: min(event.startsAt, end)))
            }
            // Guard against a long event nested inside a longer one pulling the cursor
            // backwards, which would emit a bogus gap.
            cursor = max(cursor, event.endsAt)
            if cursor >= end { break }
        }
        if cursor < end {
            slots.append(FreeSlot(startsAt: cursor, endsAt: end))
        }

        let clipped = hours.map { window in slots.flatMap { window.clip($0) } } ?? slots
        return clipped.filter { $0.fits(interval) }
    }

    /// The soonest gap that fits `interval`.
    public static func nextFreeSlot(ofAtLeast interval: TimeInterval,
                                    within horizon: TimeInterval = 604_800,
                                    hours: WorkingHours? = nil,
                                    calendars: [String] = []) throws -> FreeSlot? {
        let now = Date()
        return try freeSlots(ofAtLeast: interval,
                             from: now,
                             through: now.addingTimeInterval(horizon),
                             within: hours,
                             calendars: calendars).first
    }
}

/// A daily window to confine free-slot results to.
///
/// Without this, "when am I free for an hour?" answers 2am — technically true and
/// operationally useless.
public struct WorkingHours: Sendable, Equatable {

    /// Hour of day work starts, 0–23.
    public let startHour: Int

    /// Hour of day work ends, 0–23. Must be later than ``startHour``.
    public let endHour: Int

    /// Weekdays counted as working days, as `Calendar` weekday numbers (1 = Sunday).
    public let weekdays: Set<Int>

    /// Monday–Friday, 9am–6pm.
    public static let standard = WorkingHours(startHour: 9, endHour: 18, weekdays: [2, 3, 4, 5, 6])

    /// Creates a working window. Defaults to Monday–Friday.
    public init(startHour: Int, endHour: Int, weekdays: Set<Int> = [2, 3, 4, 5, 6]) {
        self.startHour = startHour
        self.endHour = endHour
        self.weekdays = weekdays
    }

    /// Splits `slot` into the portions falling inside this window, dropping the rest.
    ///
    /// A slot spanning several days yields one piece per working day it touches.
    func clip(_ slot: FreeSlot) -> [FreeSlot] {
        let calendar = Agenda.calendar
        var pieces: [FreeSlot] = []
        var day = calendar.startOfDay(for: slot.startsAt)
        let lastDay = calendar.startOfDay(for: slot.endsAt)

        while day <= lastDay {
            defer { day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400) }
            guard weekdays.contains(calendar.component(.weekday, from: day)),
                  let open = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: day),
                  let close = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: day)
            else { continue }

            let from = max(slot.startsAt, open)
            let to = min(slot.endsAt, close)
            if to > from { pieces.append(FreeSlot(startsAt: from, endsAt: to)) }
        }
        return pieces
    }
}
