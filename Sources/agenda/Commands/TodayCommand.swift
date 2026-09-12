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
import CLIKit
import EventKit
import Foundation

/// Shared implementation for the two day-shaped shortcuts.
///
/// These exist because `--next 24h` is not the same question: it runs from *now* into
/// tomorrow morning, so it both hides what already happened today and pads the answer
/// with events that are not today's.
struct TodayCommand: AgendaVerb {

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

    @OptionGroup var zone: ZoneOptions
    @OptionGroup var common: CommonOptions

    func execute() async throws {
        try zone.apply()
        try await runDay(offset: dayOffset)
    }

    /// Prints the day `offset` days from today.
    func runDay(offset: Int) async throws {
        let wantEvents = events || !reminders
        let wantReminders = reminders || !events

        let day = Agenda.calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        let start = Agenda.calendar.startOfDay(for: day)
        let end = Agenda.calendar.date(byAdding: .day, value: 1, to: start) ?? start

        let hits = try await contents(start: start, end: end, offset: offset,
                                      wantEvents: wantEvents, wantReminders: wantReminders)
        let label = Output.day.string(from: start)

        guard !hits.isEmpty else {
            // "Nothing on Monday" is an answer, so text says it and exits 0; every other
            // format gets the empty array a parser expects.
            if common.format == .text { sayNothing("Nothing on \(label).", options: common) }
            else { try common.emitter.emitAll([SearchPayload]()) }
            return
        }
        if common.format == .text { Terminal.writeLine(label) }
        try common.emitter.emitAll(hits.map(SearchPayload.init))
    }

    /// Everything on the day, as typed results.
    ///
    /// ONE SOURCE OF TRUTH FOR BOTH FORMATS. This used to be two: the text path filtered
    /// reminders to the day with a lower bound, and the JSON path did not — so
    /// `agenda tomorrow --json` returned every overdue reminder from the past as well.
    private func contents(start: Date, end: Date, offset: Int,
                          wantEvents: Bool, wantReminders: Bool) async throws -> [SearchResult] {
        var hits: [SearchResult] = []
        if wantEvents {
            try await Agenda.requestAccess(to: .event)
            hits += try Agenda.events(from: start, to: end, calendars: calendar).map(SearchResult.event)
        }
        if wantReminders {
            try await Agenda.requestAccess(to: .reminder)
            // Overdue items surface on TODAY's list — a task that slipped is part of today's
            // work whether or not its due date says so. On any other day they do not, because
            // last week's slippage is not tomorrow's plan.
            hits += try await Agenda.reminders(matching: ReminderFilter(lists: calendar))
                .filter { reminder in
                    guard let dueAt = reminder.dueAt else { return false }
                    return dueAt < end && (offset == 0 || dueAt >= start)
                }
                .map(SearchResult.reminder)
        }
        return hits
    }
}

/// `agenda tomorrow` — the same day's worth, one day along.
struct TomorrowCommand: AgendaVerb {

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

    @OptionGroup var zone: ZoneOptions
    @OptionGroup var common: CommonOptions

    func execute() async throws {
        try zone.apply()
        var day = TodayCommand()
        day.events = events
        day.reminders = reminders
        day.calendar = calendar
        day.zone = zone
        day.common = common
        try await day.runDay(offset: 1)
    }
}
