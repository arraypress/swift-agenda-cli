//
//  AgendaCommand.swift
//  agenda
//
//  Created by David Sherlock on 2026.
//
//  What every `agenda` subcommand shares, now that the tool is on CLIKit.
//
//  IT USED TO SHARE A PRIVATE COPY OF CLIKIT. `SafeOutput` was a reimplementation of
//  `Terminal`, `OutputOptions` of `CommonOptions`, `Output.render` of the emitter, and there
//  were hand-written `describe` and `mcp` commands beside the generic ones. Each was a
//  reasonable call at the time — the comment on `SafeOutput` said as much, "not worth a
//  dependency for fifteen lines" — and together they had become the whole surface, minus the
//  formats every other tool in the family answers to.
//

import AgendaKit
import ArgumentParser
import CLIKit
import Foundation

/// An `agenda` subcommand.
protocol AgendaVerb: CLICommand {}

extension AgendaVerb {
    static var serviceID: String { "agenda" }

    /// Turn an AgendaKit failure into the right exit code.
    ///
    /// A refused calendar permission is exit 3, like a missing credential: something has to
    /// be granted before anything works, and the message is the onboarding.
    static func translate(_ error: Error) -> Error {
        guard let agendaError = error as? AgendaError else { return error }
        switch agendaError {
        case .accessDenied:
            return CLIError.authRequired(
                agendaError.localizedDescription,
                service: "agenda",
                hint: "System Settings ▸ Privacy & Security ▸ Calendars (and Reminders)"
            )
        case .notFound(let id):
            return CLIError.notFound("No event or reminder with id \(id)", service: "agenda")
        default:
            return CLIError.upstream(agendaError.localizedDescription, service: "agenda")
        }
    }
}

extension AgendaVerb {

    /// Emit results, or say there are none.
    ///
    /// "YOU HAVE NOTHING ON" IS A SUCCESSFUL ANSWER, not a failure — `agenda today` on a free
    /// day exits 0 and always has. CLIKit's emitter prints nothing for an empty list in text,
    /// which would turn that answer into silence, so the message is kept. Every other format
    /// gets the empty array it expects, because a script parsing JSON wants `[]` and not prose.
    func emit<T: Encodable & TableRenderable>(_ values: [T], empty: String,
                                              options: CommonOptions) throws {
        guard !values.isEmpty || options.format != .text else {
            sayNothing(empty, options: options)
            return
        }
        try options.emitter.emitAll(values)
    }

    /// The same, for results that render as a line rather than a row.
    func emit<T: Encodable & TextRenderable>(_ values: [T], empty: String,
                                             options: CommonOptions) throws {
        guard !values.isEmpty || options.format != .text else {
            sayNothing(empty, options: options)
            return
        }
        try options.emitter.emitAll(values)
    }

    /// Report an empty answer, and whether it might be the wrong one.
    ///
    /// AN EMPTY ANSWER THAT IS WRONG READS EXACTLY LIKE AN EMPTY ANSWER THAT IS RIGHT, which
    /// is why this is worth the extra line. Calendar.app can hold calendars EventKit does not
    /// expose — Siri Suggestions, where a flight from an unconfirmed booking sits — and
    /// without this the tool says "Nothing scheduled" over the top of one.
    ///
    /// Only on an empty result, and only in text: a script asking for JSON wants `[]`, and a
    /// day that genuinely has things on it needs no caveat.
    func sayNothing(_ empty: String, options: CommonOptions) {
        Terminal.writeLine(empty)
        guard !options.quiet, let note = HiddenCalendars.note() else { return }
        Terminal.writeError(note)
    }
}

/// `--timezone`, which is agenda's alone.
///
/// Separate from ``CommonOptions`` because it is not a family-wide flag, and separate from
/// each command because every one of them needs it: a date means nothing until you know the
/// zone it is being read in.
struct ZoneOptions: ParsableArguments {

    init() {}

    @Option(name: .long,
            help: ArgumentHelp("Compute dates in this zone, e.g. Asia/Tokyo. Defaults to the system zone.",
                               valueName: "zone"))
    var timezone: String?

    /// Applies `--timezone` to the package and the output formatters.
    ///
    /// MUST RUN BEFORE ANY DATE IS PARSED OR RENDERED — `Agenda.calendar` decides what a bare
    /// `2026-07-19` means, so setting it afterwards would leave the parse in one zone and the
    /// display in another.
    func apply() throws {
        guard let timezone else { return }
        guard let zone = TimeZone(identifier: timezone) else {
            throw ValidationError("Unknown time zone \"\(timezone)\". Use an IANA name like Europe/London.")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        Agenda.calendar = calendar
        Output.applyTimeZone(zone)
    }
}
