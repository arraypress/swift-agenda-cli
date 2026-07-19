//
//  MCPTools.swift
//  agenda
//
//  The tool surface exposed to MCP clients.
//
//  Created by David Sherlock on 7/19/26.
//

import AgendaKit
import EventKit
import Foundation

/// The five tools this server offers.
///
/// Deliberately coarser than the CLI's thirteen subcommands. Every tool definition
/// occupies the model's context permanently, whether it is called or not, and a model
/// chooses more reliably among five clear options than thirteen overlapping ones — so
/// the read commands collapse into one `mode` parameter rather than one tool each.
enum MCPTools {

    /// The tool list, as MCP's `tools/list` expects it.
    static var definitions: JSONValue {
        .array([
            tool(
                name: "agenda_query",
                description: """
                    Read the user's Apple Calendar and Reminders. Use for "what's on today", \
                    "am I free Thursday", "what's coming up", or listing calendars. \
                    Dates accept plain language: today, tomorrow, next friday, +2d.
                    """,
                properties: [
                    "mode": string("""
                        What to read. today | tomorrow | events | reminders | free | calendars
                        """),
                    "from": string("Range start for mode=events, e.g. today, monday, 2026-07-20."),
                    "to": string("Range end for mode=events."),
                    "next": string("Forward window for mode=events instead of from/to, e.g. 7d, 2w."),
                    "duration": string("For mode=free: the minimum gap wanted, e.g. 90m, 2h."),
                    "within": string("For mode=free: how far ahead to look, e.g. 2w."),
                    "overdue": bool("For mode=reminders: only items past their due date."),
                    "due": string("For mode=reminders: only items due within this window, e.g. 7d."),
                    "calendar": string("Restrict to a calendar or reminder list by name."),
                    "timezone": string("IANA zone to compute and display in, e.g. Europe/London.")
                ],
                required: ["mode"]
            ),
            tool(
                name: "agenda_search",
                description: """
                    Find events and reminders matching text. Searches titles, notes, locations, \
                    and URLs — a booking reference or flight number usually sits in the notes, \
                    not the title. Case- and accent-insensitive.
                    """,
                properties: [
                    "query": string("Text to look for, e.g. flight, dentist, berlin."),
                    "within": string("How far ahead to search. Defaults to 1y."),
                    "past": string("How far back to search. Defaults to 30d."),
                    "kind": string("Narrow to events or reminders. Omit for both.")
                ],
                required: ["query"]
            ),
            tool(
                name: "agenda_create",
                description: """
                    Create a calendar event or a reminder. Confirm the details with the user \
                    before calling this — it writes to their real calendar.
                    """,
                properties: [
                    "title": string("What it is called."),
                    "kind": string("event or reminder. Defaults to event."),
                    "at": string("When it starts or is due: tomorrow 9am, next friday, 2026-08-01T14:00."),
                    "duration": string("How long an event runs, e.g. 30m, 1h. Ignored for reminders."),
                    "allDay": bool("All-day event, or a reminder due on a date with no time."),
                    "calendar": string("Target calendar, or reminder list."),
                    "location": string("Where it happens."),
                    "notes": string("Free-text notes."),
                    "alert": string("Alert before it starts, e.g. 15m, 1d."),
                    "priority": string("Reminder priority, 1 highest to 9."),
                    "repeat": string("daily | weekly | monthly | yearly."),
                    "repeatEvery": string("Repeat interval, e.g. 2 with repeat=weekly for fortnightly."),
                    "repeatOn": string("Weekdays for a weekly repeat, e.g. MO,WE,FR."),
                    "repeatOnDay": string("Days of month for a monthly repeat, e.g. 1 or last."),
                    "repeatTimes": string("Stop after this many occurrences."),
                    "repeatUntil": string("Stop repeating after this date."),
                    "dryRun": bool("Describe what would be created without saving it.")
                ],
                required: ["title"]
            ),
            tool(
                name: "agenda_update",
                description: """
                    Change an existing event or reminder. Get the id from agenda_query or \
                    agenda_search first. Editing one occurrence of a repeating event needs both \
                    span=this and the occurrence date.
                    """,
                properties: [
                    "id": string("The item's id, from a query or search result."),
                    "kind": string("event or reminder. Defaults to event."),
                    "title": string("New title."),
                    "at": string("New start or due time: tomorrow 9am, next friday."),
                    "shiftBy": string("Move by a duration instead of setting a time, e.g. 1h, 1d."),
                    "location": string("New location. Events only."),
                    "notes": string("New notes."),
                    "priority": string("New reminder priority, 1 highest to 9, 0 to clear."),
                    "completed": bool("Tick off or reopen a reminder."),
                    "clearDue": bool("Remove a reminder's due date, leaving it unscheduled."),
                    "span": string("For repeating events: this | future. Required to edit one."),
                    "occurrence": string("Which occurrence of a repeating event, e.g. 2026-08-10."),
                    "dryRun": bool("Show a before/after diff without saving.")
                ],
                required: ["id"]
            ),
            tool(
                name: "agenda_delete",
                description: """
                    Delete an event or reminder. Irreversible — confirm with the user first. \
                    Deleting a repeating event requires span: 'this' removes one occurrence, \
                    'future' removes every remaining one and cannot be undone.
                    """,
                properties: [
                    "id": string("The item's id."),
                    "kind": string("event or reminder. Defaults to event."),
                    "span": string("For repeating events: this | future."),
                    "occurrence": string("Which occurrence to remove, e.g. 2026-08-10.")
                ],
                required: ["id"]
            )
        ])
    }

    // MARK: - Schema helpers

    private static func tool(name: String, description: String,
                             properties: [String: JSONValue], required: [String]) -> JSONValue {
        .object([
            "name": .string(name),
            "description": .string(description),
            "inputSchema": .object([
                "type": .string("object"),
                "properties": .object(properties),
                "required": .array(required.map(JSONValue.string))
            ])
        ])
    }

    private static func string(_ description: String) -> JSONValue {
        .object(["type": .string("string"), "description": .string(description)])
    }

    private static func bool(_ description: String) -> JSONValue {
        .object(["type": .string("boolean"), "description": .string(description)])
    }
}
