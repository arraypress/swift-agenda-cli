//
//  Payloads.swift
//  agenda
//
//  Created by David Sherlock on 2026.
//
//  What a result looks like on the way out.
//
//  EACH ONE WRAPS AN AGENDAKIT MODEL AND ENCODES IT UNTOUCHED, so `--json` says exactly what
//  it said before the tool moved onto CLIKit. What the wrappers add is the rest of the
//  family's contract: `--csv`, `--markdown` and `--fields` for nothing.
//
//  NOT EVERYTHING IS A TABLE, and choosing per type matters here. `TableRenderable` changes
//  only the TEXT rendering — every other format encodes the model either way — so the
//  question is what a person should see. A calendar and a free slot are genuinely tabular:
//  three or four short fields, better aligned in columns. An event is not. Its line carries
//  the location, who is coming, the alarms and the recurrence, and a table wide enough for
//  all of that is unreadable while a table narrow enough drops the reason you looked.
//
//  THE TEXT LINES ARE THE OLD ONES. `Output.line` already knew how to render an event with
//  its location, its attendees, its alarms and its recurrence, and none of that is worth
//  rewriting to prove a point about layering.
//

import AgendaKit
import CLIKit
import Foundation

/// One event.
struct EventPayload: Encodable, TextRenderable {

    let event: AgendaEvent

    init(_ event: AgendaEvent) { self.event = event }

    func encode(to encoder: Encoder) throws { try event.encode(to: encoder) }

    func renderText() -> String { Output.line(event) }

}

/// One reminder.
struct ReminderPayload: Encodable, TextRenderable {

    let reminder: AgendaReminder

    init(_ reminder: AgendaReminder) { self.reminder = reminder }

    func encode(to encoder: Encoder) throws { try reminder.encode(to: encoder) }

    func renderText() -> String { Output.line(reminder) }

}

/// One search hit, which may be either kind.
struct SearchPayload: Encodable, TextRenderable {

    let result: SearchResult

    init(_ result: SearchResult) { self.result = result }

    func encode(to encoder: Encoder) throws { try result.encode(to: encoder) }

    func renderText() -> String { Output.line(result) }

}

/// One gap in the day.
struct SlotPayload: Encodable, TableRenderable {

    let slot: FreeSlot

    init(_ slot: FreeSlot) { self.slot = slot }

    func encode(to encoder: Encoder) throws { try slot.encode(to: encoder) }

    func renderText() -> String { Output.line(slot) }

    static let tableColumns = ["from", "to", "length"]

    var tableRow: [String] {
        let hours = slot.minutes / 60, minutes = slot.minutes % 60
        let length = hours > 0 ? "\(hours)h\(minutes > 0 ? " \(minutes)m" : "")" : "\(minutes)m"
        return [Output.stamp.string(from: slot.startsAt),
                Output.clock.string(from: slot.endsAt), length]
    }
}

/// One calendar or reminder list.
struct CalendarPayload: Encodable, TableRenderable {

    let calendar: AgendaCalendar

    init(_ calendar: AgendaCalendar) { self.calendar = calendar }

    func encode(to encoder: Encoder) throws { try calendar.encode(to: encoder) }

    func renderText() -> String { Output.line(calendar) }

    static let tableColumns = ["name", "account", "flags", "id"]
    static let flexibleColumns = [0, 1, 2]

    var tableRow: [String] {
        let flags = [calendar.isWritable ? nil : "read-only",
                     calendar.isSubscribed ? "subscribed" : nil,
                     calendar.isDefault ? "default" : nil].compactMap { $0 }
        return [calendar.title, calendar.source, flags.joined(separator: ", "), calendar.id]
    }
}

/// The call `agenda join` opened, or would open with `--print`.
///
/// The event's identifying fields and its `videoCall`, under the same names an event
/// carries, plus `opened` — so a caller can tell a printed link from a launched one.
struct JoinPayload: Encodable, TextRenderable {

    let event: AgendaEvent
    let call: VideoCall
    let opened: Bool

    private enum CodingKeys: String, CodingKey {
        case id, title, calendar, startsAt, endsAt, videoCall, opened
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(event.id, forKey: .id)
        try container.encode(event.title, forKey: .title)
        try container.encode(event.calendar, forKey: .calendar)
        try container.encode(event.startsAt, forKey: .startsAt)
        try container.encode(event.endsAt, forKey: .endsAt)
        try container.encode(call, forKey: .videoCall)
        try container.encode(opened, forKey: .opened)
    }

    /// With `--print`, the bare link and nothing else, so `open "$(agenda join --print --text)"`
    /// works. Otherwise what was opened, for the person who just watched a window appear.
    func renderText() -> String {
        guard opened else { return call.url }
        let when = "\(Output.clock.string(from: event.startsAt))–\(Output.clock.string(from: event.endsAt))"
        return "Joining \(call.service.displayName): \(event.title)  \(when)\n    \(call.url)"
    }
}

/// The day or event `agenda open` showed, or would show with `--print`.
///
/// Exactly one of `url` and `script` is present: Calendar.app has no link for a date, so a
/// day there is the AppleScript that drives it.
struct OpenPayload: Encodable, TextRenderable {

    let app: CalendarApp
    let date: Date
    let event: AgendaEvent?
    let launch: Launch
    let opened: Bool

    private enum CodingKeys: String, CodingKey {
        case app, id, title, date, url, script, opened
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(app, forKey: .app)
        try container.encodeIfPresent(event?.id, forKey: .id)
        try container.encodeIfPresent(event?.title, forKey: .title)
        try container.encode(date, forKey: .date)
        switch launch {
        case .url(let url):       try container.encode(url.absoluteString, forKey: .url)
        case .script(let script): try container.encode(script, forKey: .script)
        }
        try container.encode(opened, forKey: .opened)
    }

    /// With `--print`, the bare link — or the script, ready to pipe into `osascript`.
    func renderText() -> String {
        guard opened else {
            switch launch {
            case .url(let url):       return url.absoluteString
            case .script(let script): return script
            }
        }
        let subject = event.map { "\"\($0.title)\"" } ?? Output.day.string(from: date)
        return "Opened \(subject) in \(app.displayName)."
    }
}
