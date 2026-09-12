//
//  FreeCommand.swift
//  agenda
//
//  `agenda free` — find unbooked windows.
//
//  Created by David Sherlock on 7/19/26.
//

import AgendaKit
import ArgumentParser
import CLIKit
import EventKit
import Foundation

struct FreeCommand: AgendaVerb {

    static let configuration = CommandConfiguration(
        commandName: "free",
        abstract: "Find gaps long enough to schedule something.",
        discussion: """
            Confined to working hours by default, because the literally-correct answer \
            to "when am I free for an hour?" is 3am. Pass --any-time to lift that.
            """
    )

    @Argument(help: "Minimum gap length: 30m, 1h, 90m.")
    var length: String = "30m"

    @Option(name: .long, help: "How far ahead to look: 7d, 2w.")
    var within: String = "7d"

    @Option(name: .long, help: "Working day start hour, 0-23.")
    var startHour: Int = 9

    @Option(name: .long, help: "Working day end hour, 0-23.")
    var endHour: Int = 18

    @Flag(name: .long, help: "Ignore working hours and weekends.")
    var anyTime = false

    @Flag(name: .long, help: "Return only the first matching slot.")
    var first = false

    @Option(name: .long, help: "Restrict to a calendar by title or id. Repeatable.")
    var calendar: [String] = []

    @OptionGroup var zone: ZoneOptions
    @OptionGroup var common: CommonOptions

    func execute() async throws {
        try zone.apply()
        try await Agenda.requestAccess(to: .event)

        let minimum = try Agenda.duration(length)
        let horizon = try Agenda.duration(within)
        let hours = anyTime ? nil : WorkingHours(startHour: startHour, endHour: endHour)

        var slots = try Agenda.freeSlots(
            ofAtLeast: minimum,
            through: Date().addingTimeInterval(horizon),
            within: hours,
            calendars: calendar
        )
        if first { slots = Array(slots.prefix(1)) }

        try emit(slots.map(SlotPayload.init), empty: "No free \(length) window in the next \(within).", options: common)
    }
}
