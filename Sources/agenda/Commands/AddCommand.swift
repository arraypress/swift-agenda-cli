//
//  AddCommand.swift
//  agenda
//
//  `agenda add` — create an event or reminder.
//
//  Created by David Sherlock on 7/19/26.
//

import AgendaKit
import ArgumentParser
import EventKit
import Foundation

struct AddCommand: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Create an event, or a reminder with --remind.",
        discussion: """
            agenda add "Standup" --at 2026-07-20T09:30 --for 15m --repeat weekly --on MO,TU,WE,TH,FR
            agenda add "Rent" --remind --at 2026-08-01 --all-day --repeat monthly --on-day 1
            agenda add "Retro" --at 2026-07-31T16:00 --repeat monthly --on FR --nth -1
            agenda add "Dentist" --at 2026-07-22T10:00 --alert 1d --alert 30m

            Pass --dry-run to print what would be created without saving.
            """
    )

    @Argument(help: "Title.")
    var title: String

    @Option(name: .long, help: "Start: now, tomorrow 9am, next friday, +2d, or ISO 8601. Defaults to now.")
    var at: String?

    @Option(name: .customLong("for"), help: "Duration: 30m, 1h. Ignored with --remind.")
    var length: String = "1h"

    @Flag(name: .long, help: "Create a reminder instead of an event.")
    var remind = false

    @Flag(name: .long, help: "All-day event.")
    var allDay = false

    /// Accepts `--list` too, so a reminder does not have to be filed into a "calendar" —
    /// EventKit models the two identically, but nobody thinks of them that way.
    @Option(name: [.customLong("calendar"), .customLong("list")],
            help: "Target calendar, or reminder list with --remind.")
    var calendar: String?

    @Option(name: .long, help: "Location.")
    var location: String?

    @Option(name: .long, help: "Notes.")
    var notes: String?

    @Option(name: .long, help: "Alert before start: 15m, 1h, 1d. Repeatable. Use 0 for at-start.")
    var alert: [String] = []

    @Option(name: .long, help: "Geofenced alert: enter:LAT,LON[,RADIUS][,TITLE]. Repeatable.")
    var alertAt: [String] = []

    @Option(name: .long, help: "Free/busy marking: busy | free | tentative | unavailable.")
    var availability: AgendaAvailability = .busy

    @Option(name: .long, help: "Priority for reminders, 1 (highest) to 9.")
    var priority: Int = 0

    @Flag(name: .long, help: "Print what would be created without saving.")
    var dryRun = false

    @OptionGroup var repeats: RecurrenceOptions

    @OptionGroup var output: OutputOptions

    func run() async throws {
        try output.apply()
        let start = try at.map(Agenda.date) ?? Date()
        let recurrence = try repeats.resolve()
        let alarms = try AlertParsing.alarms(from: alert) + alertAt.map(AlertParsing.locationAlarm)

        if remind {
            try await Agenda.requestAccess(to: .reminder)
            let draft = ReminderDraft(
                title: title,
                dueAt: at == nil ? nil : start,
                notes: notes,
                dueHasTime: !allDay,
                priority: priority,
                recurrence: recurrence,
                alarms: alarms,
                list: calendar
            )
            guard !dryRun else {
                print("Would create reminder: \(draft.title)"
                      + (draft.dueAt.map { " due \(Output.stamp.string(from: $0))" } ?? "")
                      + (recurrence.map { ", \($0.summary)" } ?? "")
                      + (draft.list.map { " in [\($0)]" } ?? ""))
                return
            }
            let created = try Agenda.createReminder(draft)
            try printResult(created, line: Output.line)
        } else {
            try await Agenda.requestAccess(to: .event)
            let end = allDay ? start : start.addingTimeInterval(try Agenda.duration(length))
            let draft = EventDraft(
                title: title, startsAt: start, endsAt: end, isAllDay: allDay,
                location: location, notes: notes,
                recurrence: recurrence, alarms: alarms,
                availability: availability, calendar: calendar
            )
            guard !dryRun else {
                print("Would create event: \(draft.title) "
                      + "\(Output.stamp.string(from: draft.startsAt))–\(Output.clock.string(from: draft.endsAt))"
                      + (recurrence.map { ", \($0.summary)" } ?? "")
                      + (alarms.isEmpty ? "" : ", alerts \(alarms.map(\.summary).joined(separator: " + "))")
                      + (draft.calendar.map { " in [\($0)]" } ?? ""))
                return
            }
            let created = try Agenda.createEvent(draft)
            try printResult(created, line: Output.line)
        }
    }

    private func printResult<T: Encodable>(_ value: T, line: (T) -> String) throws {
        switch output.format {
        case .json: print(try Output.encode(value))
        case .text: print(line(value))
        }
    }
}
