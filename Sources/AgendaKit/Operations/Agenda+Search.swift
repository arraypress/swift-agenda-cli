//
//  Agenda+Search.swift
//  SwiftAgenda
//
//  Text search across events and reminders.
//
//  Created by David Sherlock on 7/19/26.
//

import EventKit
import Foundation

/// A search hit, which may be either kind of item.
public enum SearchResult: Codable, Sendable, Equatable {

    /// A matching calendar event.
    case event(AgendaEvent)

    /// A matching reminder.
    case reminder(AgendaReminder)

    /// When the item is scheduled, for ordering mixed results. Undated reminders
    /// return `nil` and sort last.
    public var sortDate: Date? {
        switch self {
        case .event(let event):       return event.startsAt
        case .reminder(let reminder): return reminder.dueAt
        }
    }

    /// The item's title.
    public var title: String {
        switch self {
        case .event(let event):       return event.title
        case .reminder(let reminder): return reminder.title
        }
    }
}

extension Agenda {

    /// Finds events and reminders whose text matches `query`.
    ///
    /// ```swift
    /// let hits = try await Agenda.search("flight", from: .now, to: oneYearOut)
    /// ```
    ///
    /// Matching is case- and diacritic-insensitive across title, notes, location, and
    /// URL — a flight confirmation usually names the airport in the location or the
    /// booking reference in the notes, not the title.
    ///
    /// - Note: EventKit offers no text predicate for either entity, so this fetches
    ///   the window and filters in process. Keep the range tight on large calendars;
    ///   the cost is proportional to how many items the range holds, not to how many
    ///   match.
    ///
    /// - Parameters:
    ///   - query: Text to look for. Blank returns nothing rather than everything.
    ///   - start: Range start for events.
    ///   - end: Range end for events.
    ///   - includeEvents: Search the calendar.
    ///   - includeReminders: Search reminders, including completed ones.
    ///   - calendars: Restrict to these calendars or lists.
    /// - Returns: Hits in chronological order, undated ones last.
    public static func search(_ query: String,
                              from start: Date,
                              to end: Date,
                              includeEvents: Bool = true,
                              includeReminders: Bool = true,
                              calendars: [String] = []) async throws -> [SearchResult] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }

        var hits: [SearchResult] = []

        if includeEvents, access(to: .event) == .authorized {
            hits += try events(from: start, to: end, calendars: calendars)
                .filter { matches(needle, in: [$0.title, $0.notes, $0.location, $0.url]) }
                .map(SearchResult.event)
        }

        if includeReminders, access(to: .reminder) == .authorized {
            // Completed reminders are included: "what did I call that flight booking?"
            // is asked about finished items as often as open ones.
            let filter = ReminderFilter(lists: calendars, includeCompleted: true)
            hits += try await reminders(matching: filter)
                .filter { matches(needle, in: [$0.title, $0.notes, $0.url]) }
                .map(SearchResult.reminder)
        }

        return hits.sorted { lhs, rhs in
            switch (lhs.sortDate, rhs.sortDate) {
            case let (l?, r?): return l < r
            case (nil, _?):    return false
            case (_?, nil):    return true
            default:           return lhs.title < rhs.title
            }
        }
    }

    /// Searches a forward window from now.
    ///
    /// - Parameters:
    ///   - query: Text to look for.
    ///   - within: How far ahead to look.
    ///   - past: How far back to look. Defaults to 30 days, so a booking made last
    ///     week is still findable.
    public static func search(_ query: String,
                              within: TimeInterval,
                              past: TimeInterval = 2_592_000,
                              includeEvents: Bool = true,
                              includeReminders: Bool = true,
                              calendars: [String] = []) async throws -> [SearchResult] {
        let now = Date()
        return try await search(query,
                                from: now.addingTimeInterval(-abs(past)),
                                to: now.addingTimeInterval(within),
                                includeEvents: includeEvents,
                                includeReminders: includeReminders,
                                calendars: calendars)
    }

    /// Whether any field contains `needle`.
    ///
    /// Uses `.diacriticInsensitive` so "Zurich" finds "Zürich" — a real problem for
    /// travel, where airline confirmations spell place names properly and people
    /// searching do not.
    static func matches(_ needle: String, in fields: [String?]) -> Bool {
        fields.compactMap { $0 }.contains {
            $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}
