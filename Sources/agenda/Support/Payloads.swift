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
