//
//  OpenCommand.swift
//  agenda
//
//  `agenda open` — show an event or a day in a calendar app.
//
//  Created by David Sherlock on 2026.
//

import AgendaKit
import ArgumentParser
import CLIKit
import EventKit
import Foundation

/// `agenda open` — show an event or a day in Calendar.app, Google Calendar, Fantastical or
/// BusyCal.
///
/// NO ENVELOPE, like `join`: it changes what is on screen, not what is in the calendar.
struct OpenCommand: AgendaVerb {

    static let configuration = CommandConfiguration(
        commandName: "open",
        abstract: "Show an event or a day in a calendar app.",
        discussion: """
            agenda open today                         # Calendar.app, today
            agenda open "next friday" --view week     # that week
            agenda open <id> --in google              # the event's day in Google Calendar
            agenda open <id> --in busycal --print     # print the link instead

            Takes a date phrase or an event id; anything that reads as a date is a day. \
            Calendar.app opens an event itself, and a day by AppleScript (it has no link \
            for a date) — the first run asks for Automation permission. BusyCal finds an \
            event by calendar, title and start. Google Calendar and Fantastical have no \
            link for a single event, so an event opens on its day there.

            --print prints the link, or for a day in Calendar.app the script, ready for \
            `osascript`. --view applies to Google Calendar and Calendar.app only.
            """
    )

    @Argument(help: "Event id, or a date: today, next friday, 2026-10-04.")
    var target: String

    @Option(name: .customLong("in"),
            help: ArgumentHelp("calendar | google | fantastical | busycal.", valueName: "app"))
    var app: OpenApp = .calendar

    @Option(name: .long, help: "For a day: day | week | month.")
    var view: CalendarView = .day

    @Option(name: .long, help: "Which occurrence of a repeating event, e.g. 2026-08-10 or next friday.")
    var occurrence: String?

    @Flag(name: .customLong("print"), help: "Print the link instead of opening it.")
    var printOnly = false

    @OptionGroup var zone: ZoneOptions
    @OptionGroup var common: CommonOptions

    func execute() async throws {
        try zone.apply()
        let calendarApp = app.app

        let payload: OpenPayload
        if let day = OpenTarget.day(from: target) {
            payload = OpenPayload(app: calendarApp, date: day, event: nil,
                                  launch: OpenTarget.launch(day: day, in: calendarApp, view: view),
                                  opened: !printOnly)
        } else {
            try await Agenda.requestAccess(to: .event)
            let event: AgendaEvent
            do { event = try Agenda.event(id: target, occurrenceOn: try occurrence.map(Agenda.date)) }
            catch let error as AgendaError {
                // Not a date and not an id: say both, since either was a fair reading.
                if case .notFound = error {
                    throw CLIError.notFound("\"\(target)\" is neither a date nor an event id.",
                                            service: "agenda",
                                            hint: "Ids print on the second line of `agenda events`.")
                }
                throw Self.translate(error)
            }
            payload = OpenPayload(app: calendarApp, date: event.startsAt, event: event,
                                  launch: OpenTarget.launch(event: event, in: calendarApp),
                                  opened: !printOnly)
        }

        if !printOnly {
            switch payload.launch {
            case .url(let url):       try Launcher.open(url, app: calendarApp.displayName)
            case .script(let script): try Launcher.run(script: script)
            }
        }
        try common.emitter.emit(payload)
    }
}
