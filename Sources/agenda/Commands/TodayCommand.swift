//
//  TodayCommand.swift
//  agenda
//
//  `agenda today` and `agenda tomorrow` — a single day, edge to edge.
//
//  Created by David Sherlock on 7/19/26.
//

import AgendaKit
import ArgumentParser
import EventKit
import Foundation

/// Shared implementation for the two day-shaped shortcuts.
///
/// These exist because `--next 24h` is not the same question: it runs from *now* into
/// tomorrow morning, so it both hides what already happened today and pads the answer
/// with events that are not today's.
struct TodayCommand: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "today",
        abstract: "Everything on today — events, plus reminders due.",
        discussion: """
            agenda today
            agenda tomorrow
            agenda today --events

            Covers the whole calendar day, including anything earlier that has already \
            finished. Use `agenda events --next 24h` for a rolling window instead.
            """
    )

    /// Which day to show. ``TomorrowCommand`` reuses ``runDay(offset:)`` with 1.
    var dayOffset: Int { 0 }

    @Flag(name: .long, help: "Events only.")
    var events = false

    @Flag(name: .long, help: "Reminders only.")
    var reminders = false

    @Option(name: .long, help: "Restrict to a calendar or list. Repeatable.")
    var calendar: [String] = []

    @OptionGroup var output: OutputOptions

    func run() async throws {
        try output.apply()
        try await runDay(offset: dayOffset)
    }

    /// Prints the day `offset` days from today.
    func runDay(offset: Int) async throws {
        let wantEvents = events || !reminders
        let wantReminders = reminders || !events

        let day = Agenda.calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        let start = Agenda.calendar.startOfDay(for: day)
        let end = Agenda.calendar.date(byAdding: .day, value: 1, to: start) ?? start

        var lines: [String] = []

        if wantEvents {
            try await Agenda.requestAccess(to: .event)
            let found = try Agenda.events(from: start, to: end, calendars: calendar)
            lines += found.map(Output.line)
        }

        if wantReminders {
            try await Agenda.requestAccess(to: .reminder)
            // Overdue items surface on today's list too — a task that slipped is part
            // of today's work whether or not its due date says so.
            let filter = ReminderFilter(lists: calendar)
            let due = try await Agenda.reminders(matching: filter).filter { reminder in
                guard let dueAt = reminder.dueAt else { return false }
                return dueAt < end && (offset == 0 ? true : dueAt >= start)
            }
            lines += due.map(Output.line)
        }

        guard output.format == .text else {
            // JSON keeps the two kinds distinguishable rather than flattening to text.
            let hits = try await searchResults(start: start, end: end,
                                               wantEvents: wantEvents, wantReminders: wantReminders)
            print(try Output.encode(hits))
            return
        }

        let label = Output.day.string(from: start)
        print(lines.isEmpty ? "Nothing on \(label)." : "\(label)\n" + lines.joined(separator: "\n"))
    }

    /// The same day's contents as typed results, for `--json`.
    private func searchResults(start: Date, end: Date,
                               wantEvents: Bool, wantReminders: Bool) async throws -> [SearchResult] {
        var hits: [SearchResult] = []
        if wantEvents {
            hits += try Agenda.events(from: start, to: end, calendars: calendar).map(SearchResult.event)
        }
        if wantReminders {
            hits += try await Agenda.reminders(matching: ReminderFilter(lists: calendar))
                .filter { ($0.dueAt.map { $0 < end }) ?? false }
                .map(SearchResult.reminder)
        }
        return hits
    }
}

/// `agenda tomorrow` — the same view, shifted a day.
struct TomorrowCommand: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "tomorrow",
        abstract: "Everything on tomorrow — events, plus reminders due."
    )

    @Flag(name: .long, help: "Events only.")
    var events = false

    @Flag(name: .long, help: "Reminders only.")
    var reminders = false

    @Option(name: .long, help: "Restrict to a calendar or list. Repeatable.")
    var calendar: [String] = []

    @OptionGroup var output: OutputOptions

    func run() async throws {
        try output.apply()
        var day = TodayCommand()
        day.events = events
        day.reminders = reminders
        day.calendar = calendar
        day.output = output
        try await day.runDay(offset: 1)
    }
}
