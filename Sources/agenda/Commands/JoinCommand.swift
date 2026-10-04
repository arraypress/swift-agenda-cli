//
//  JoinCommand.swift
//  agenda
//
//  `agenda join` — open an event's video call.
//
//  Created by David Sherlock on 2026.
//

import AgendaKit
import ArgumentParser
import CLIKit
import EventKit
import Foundation

/// `agenda join` — open the video call of an event, or of the one happening now.
///
/// NO ENVELOPE. This writes nothing to the calendar, so there is no plan to show and nothing
/// to record; `--print` is the way to see the link without acting on it.
struct JoinCommand: AgendaVerb {

    static let configuration = CommandConfiguration(
        commandName: "join",
        abstract: "Open an event's video call — by default, the one happening now.",
        discussion: """
            agenda join                  # the call running now, or starting within 15m
            agenda join <id>             # that event's call
            agenda join --print          # print the link instead of opening it
            agenda join --within 30m     # look further ahead

            With no id: of the calls already running or starting within --within, the one \
            whose start is nearest to now — so at 10:52, in a meeting since 10:00 with \
            another at 10:55, it joins the 10:55. All-day, cancelled and declined events \
            are skipped. Zoom meetings open in the Zoom app when it is installed.

            The call is detected from the location, URL and notes (53 services; Outlook \
            Safe Links unwrapped). No call found exits 1.
            """
    )

    @Argument(help: "Event id, from the second line of any text result. Omit for the call happening now.")
    var id: String?

    @Option(name: .long, help: "With no id, how far ahead to look for a call: 15m, 1h.")
    var within: String = "15m"

    @Flag(name: .customLong("print"), help: "Print the link instead of opening it.")
    var printOnly = false

    @OptionGroup var zone: ZoneOptions
    @OptionGroup var common: CommonOptions

    func execute() async throws {
        try zone.apply()
        try await Agenda.requestAccess(to: .event)

        let event = try find()
        guard let call = event.videoCall else {
            throw CLIError.notFound("\"\(event.title)\" has no video call.", service: "agenda",
                                    hint: event.meetingURL.map { "Its only link is \($0)" })
        }
        if !printOnly {
            try Launcher.open(try url(call.url), preferring: call.appURL.flatMap(URL.init(string:)),
                              app: call.service.displayName)
        }
        try common.emitter.emit(JoinPayload(event: event, call: call, opened: !printOnly))
    }

    /// The event named by id, or the call to join now.
    private func find() throws -> AgendaEvent {
        if let id {
            do { return try Agenda.event(id: id) }
            catch { throw Self.translate(error) }
        }
        let lookahead = try Agenda.duration(within)
        let now = Date()
        // A running call overlaps [now, now + lookahead], so the window fetch includes it.
        let events = try Agenda.events(from: now, to: now.addingTimeInterval(lookahead))
        guard let event = JoinSelection.pick(from: events, at: now, lookahead: lookahead) else {
            throw CLIError.notFound("No video call running now or starting in the next \(within).",
                                    service: "agenda",
                                    hint: "agenda events --next 1d  to see what is coming up")
        }
        return event
    }

    private func url(_ text: String) throws -> URL {
        guard let url = URL(string: text) else {
            throw CLIError.upstream("The call link is not a valid URL: \(text)", service: "agenda")
        }
        return url
    }
}
