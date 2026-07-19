//
//  MCPServer.swift
//  agenda
//
//  Dispatches MCP requests onto AgendaKit.
//
//  Created by David Sherlock on 7/19/26.
//

import AgendaKit
import EventKit
import Foundation

/// Serves the Model Context Protocol over stdio, wrapping the same `AgendaKit` calls
/// the CLI uses.
///
/// Tool failures are returned as `isError` results rather than JSON-RPC errors: a
/// transport error tells the model only that something broke, whereas an error result
/// carries the message — "run agenda doctor", "this repeats, pass a span" — that lets
/// it recover on the next call.
enum MCPServer {

    /// The protocol revision this server implements.
    private static let protocolVersion = "2024-11-05"

    /// Reads requests until stdin closes.
    static func run() async {
        StdioTransport.log("ready")
        await StdioTransport.serve { request in
            // Notifications carry no id and must never be answered.
            guard let id = request.id else { return nil }

            switch request.method {
            case "initialize":
                return RPCResponse(id: id, result: .object([
                    "protocolVersion": .string(protocolVersion),
                    "capabilities": .object(["tools": .object([:])]),
                    "serverInfo": .object([
                        "name": .string("agenda"),
                        "version": .string("1.0.0")
                    ])
                ]))

            case "tools/list":
                return RPCResponse(id: id, result: .object(["tools": MCPTools.definitions]))

            case "tools/call":
                return await call(request: request, id: id)

            case "ping":
                return RPCResponse(id: id, result: .object([:]))

            default:
                return RPCResponse(id: id, error: .methodNotFound(request.method))
            }
        }
    }

    /// Runs one tool and wraps the outcome.
    private static func call(request: RPCRequest, id: JSONValue) async -> RPCResponse {
        guard let name = request.params?["name"]?.stringValue else {
            return RPCResponse(id: id, error: .invalidParams("Missing tool name."))
        }
        let args = request.params?["arguments"] ?? .object([:])

        do {
            // Unlike the CLI, this process lives for hours while the calendar changes
            // underneath it — from Calendar.app, from iCloud sync, from another agent.
            // EventKit caches fetched objects per store, so without this a later call
            // serves stale rows, and a write against a stale object can silently
            // no-op. Cheap: it drops caches, it does not re-fetch.
            Agenda.reset()

            try applyTimeZone(args)
            let text: String
            switch name {
            case "agenda_query":  text = try await query(args)
            case "agenda_search": text = try await search(args)
            case "agenda_create": text = try await create(args)
            case "agenda_update": text = try await update(args)
            case "agenda_delete": text = try await delete(args)
            default:
                return RPCResponse(id: id, error: .invalidParams("Unknown tool \"\(name)\"."))
            }
            return RPCResponse(id: id, result: content(text))
        } catch {
            return RPCResponse(id: id, result: content(error.localizedDescription, isError: true))
        }
    }

    /// Wraps text in MCP's content envelope.
    private static func content(_ text: String, isError: Bool = false) -> JSONValue {
        .object([
            "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
            "isError": .bool(isError)
        ])
    }

    /// Applies a per-call `timezone` argument, resetting to the system zone otherwise.
    ///
    /// The server is long-lived, so a zone left set by one call would silently skew
    /// every later one.
    private static func applyTimeZone(_ args: JSONValue) throws {
        guard let name = args["timezone"]?.stringValue, !name.isEmpty else {
            Agenda.calendar = Calendar.current
            return
        }
        guard let zone = TimeZone(identifier: name) else {
            throw AgendaError.badTimeZone(name)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        Agenda.calendar = calendar
    }

    // MARK: - Tools

    private static func query(_ args: JSONValue) async throws -> String {
        let mode = args["mode"]?.stringValue?.lowercased() ?? "today"
        let calendars = args["calendar"].map { $0.stringArray } ?? []

        switch mode {
        case "calendars":
            try await Agenda.requestAccess(to: .event)
            let found = try Agenda.calendars(for: .event)
            return render(found, empty: "No calendars.", line: Output.line)

        case "reminders":
            try await Agenda.requestAccess(to: .reminder)
            var filter = ReminderFilter(lists: calendars)
            filter.overdueOnly = args["overdue"]?.boolValue ?? false
            filter.dueWithin = try args["due"]?.stringValue.map(Agenda.duration)
            let found = try await Agenda.reminders(matching: filter)
            return render(found, empty: "No reminders.", line: Output.line)

        case "free":
            try await Agenda.requestAccess(to: .event)
            let minimum = try Agenda.duration(args["duration"]?.stringValue ?? "30m")
            let horizon = try Agenda.duration(args["within"]?.stringValue ?? "7d")
            let slots = try Agenda.freeSlots(ofAtLeast: minimum,
                                             through: Date().addingTimeInterval(horizon),
                                             within: .standard,
                                             calendars: calendars)
            return render(slots, empty: "No free window that long.", line: Output.line)

        case "today", "tomorrow":
            return try await day(offset: mode == "today" ? 0 : 1, calendars: calendars)

        default:
            try await Agenda.requestAccess(to: .event)
            let start = try args["from"]?.stringValue.map(Agenda.date) ?? Date()
            let end: Date
            if let to = args["to"]?.stringValue {
                end = try Agenda.date(to)
            } else {
                end = start.addingTimeInterval(try Agenda.duration(args["next"]?.stringValue ?? "7d"))
            }
            let found = try Agenda.events(from: start, to: end, calendars: calendars)
            return render(found, empty: "Nothing scheduled.", line: Output.line)
        }
    }

    /// One whole calendar day: events plus anything due that day.
    private static func day(offset: Int, calendars: [String]) async throws -> String {
        try await Agenda.requestAccess(to: .event)
        try await Agenda.requestAccess(to: .reminder)

        let day = Agenda.calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        let start = Agenda.calendar.startOfDay(for: day)
        let end = Agenda.calendar.date(byAdding: .day, value: 1, to: start) ?? start

        var lines = try Agenda.events(from: start, to: end, calendars: calendars).map(Output.line)
        lines += try await Agenda.reminders(matching: ReminderFilter(lists: calendars))
            .filter { ($0.dueAt.map { $0 < end }) ?? false }
            .map(Output.line)

        let label = Output.day.string(from: start)
        return lines.isEmpty ? "Nothing on \(label)." : "\(label)\n" + lines.joined(separator: "\n")
    }

    private static func search(_ args: JSONValue) async throws -> String {
        guard let query = args["query"]?.stringValue, !query.isEmpty else {
            throw AgendaError.invalidArgument("A search query is required.")
        }
        let kind = args["kind"]?.stringValue?.lowercased()
        if kind != "reminder" { try await Agenda.requestAccess(to: .event) }
        if kind != "event" { try await Agenda.requestAccess(to: .reminder) }

        let hits = try await Agenda.search(
            query,
            within: try Agenda.duration(args["within"]?.stringValue ?? "1y"),
            past: try Agenda.duration(args["past"]?.stringValue ?? "30d"),
            includeEvents: kind != "reminder",
            includeReminders: kind != "event"
        )
        return render(hits, empty: "Nothing matching \"\(query)\".", line: Output.line)
    }

    private static func create(_ args: JSONValue) async throws -> String {
        guard let title = args["title"]?.stringValue, !title.isEmpty else {
            throw AgendaError.invalidArgument("A title is required.")
        }
        let isReminder = args["kind"]?.stringValue?.lowercased() == "reminder"
        let allDay = args["allDay"]?.boolValue ?? false
        let when = try args["at"]?.stringValue.map(Agenda.date)
        let recurrence = try repeatRule(args)
        let alarms = try args["alert"]?.stringValue.map { [AgendaAlarm.before(try Agenda.duration($0))] } ?? []
        let dryRun = args["dryRun"]?.boolValue ?? false

        if isReminder {
            try await Agenda.requestAccess(to: .reminder)
            let draft = ReminderDraft(
                title: title, dueAt: when, notes: args["notes"]?.stringValue,
                dueHasTime: !allDay, priority: args["priority"]?.intValue ?? 0,
                recurrence: recurrence, alarms: alarms, list: args["calendar"]?.stringValue
            )
            if dryRun {
                return "Would create reminder: \(title)"
                    + (when.map { " due \(Output.stamp.string(from: $0))" } ?? "")
                    + (recurrence.map { ", \($0.summary)" } ?? "")
            }
            return Output.line(try Agenda.createReminder(draft))
        }

        try await Agenda.requestAccess(to: .event)
        let start = when ?? Date()
        let length = try Agenda.duration(args["duration"]?.stringValue ?? "1h")
        let draft = EventDraft(
            title: title, startsAt: start, endsAt: allDay ? start : start.addingTimeInterval(length),
            isAllDay: allDay, location: args["location"]?.stringValue,
            notes: args["notes"]?.stringValue, recurrence: recurrence, alarms: alarms,
            calendar: args["calendar"]?.stringValue
        )
        if dryRun {
            return "Would create event: \(title) \(Output.stamp.string(from: draft.startsAt))"
                + (recurrence.map { ", \($0.summary)" } ?? "")
        }
        return Output.line(try Agenda.createEvent(draft))
    }

    private static func update(_ args: JSONValue) async throws -> String {
        guard let id = args["id"]?.stringValue else {
            throw AgendaError.invalidArgument("An id is required. Get one from agenda_query or agenda_search first.")
        }
        let isReminder = args["kind"]?.stringValue?.lowercased() == "reminder"

        if isReminder {
            try await Agenda.requestAccess(to: .reminder)
            var changes = ReminderChanges(
                title: args["title"]?.stringValue,
                notes: args["notes"]?.stringValue,
                priority: args["priority"]?.intValue,
                isCompleted: args["completed"]?.boolValue
            )
            if args["clearDue"]?.boolValue == true {
                changes.dueAt = .some(nil)
            } else if let at = args["at"]?.stringValue {
                changes.dueAt = .some(try Agenda.date(at))
            }
            guard !changes.isEmpty else { return "Nothing to change." }
            return Output.line(try Agenda.updateReminder(id: id, with: changes))
        }

        try await Agenda.requestAccess(to: .event)
        let occurrence = try args["occurrence"]?.stringValue.map(Agenda.date)
        let event = try Agenda.event(id: id, occurrenceOn: occurrence)
        let span = args["span"]?.stringValue.flatMap(AgendaSpan.init(rawValue:))

        var changes = EventChanges(title: args["title"]?.stringValue,
                                   location: args["location"]?.stringValue,
                                   notes: args["notes"]?.stringValue)
        if let at = args["at"]?.stringValue {
            let start = try Agenda.date(at)
            changes.startsAt = start
            changes.endsAt = start.addingTimeInterval(event.duration)
        } else if let by = args["shiftBy"]?.stringValue {
            let shift = try Agenda.duration(by)
            changes.startsAt = event.startsAt.addingTimeInterval(shift)
            changes.endsAt = event.endsAt.addingTimeInterval(shift)
        }
        guard !changes.isEmpty else { return "Nothing to change." }

        if args["dryRun"]?.boolValue == true {
            return "Would change \"\(event.title)\""
                + (changes.startsAt.map { " to \(Output.stamp.string(from: $0))" } ?? "")
                + (changes.title.map { ", title → \($0)" } ?? "")
        }
        let updated = try Agenda.updateEvent(id: id, with: changes, span: span, occurrenceOn: occurrence)
        return Output.line(updated)
    }

    private static func delete(_ args: JSONValue) async throws -> String {
        guard let id = args["id"]?.stringValue else {
            throw AgendaError.invalidArgument("An id is required.")
        }
        if args["kind"]?.stringValue?.lowercased() == "reminder" {
            try await Agenda.requestAccess(to: .reminder)
            try Agenda.deleteReminder(id: id)
            return "Deleted the reminder."
        }

        try await Agenda.requestAccess(to: .event)
        let occurrence = try args["occurrence"]?.stringValue.map(Agenda.date)
        let event = try Agenda.event(id: id, occurrenceOn: occurrence)
        let span = args["span"]?.stringValue.flatMap(AgendaSpan.init(rawValue:))
        try Agenda.deleteEvent(id: id, span: span, occurrenceOn: occurrence)

        let scope = event.isRecurring
            ? (span == .future ? " and every later occurrence" : " (this occurrence only)")
            : ""
        return "Deleted \"\(event.title)\"\(scope)."
    }

    /// Assembles a repeat rule from the flat `repeat*` arguments.
    private static func repeatRule(_ args: JSONValue) throws -> Recurrence? {
        guard let raw = args["repeat"]?.stringValue,
              let frequency = AgendaFrequency(rawValue: raw.lowercased()) else { return nil }

        let weekdays = (args["repeatOn"]?.stringValue ?? "")
            .split(separator: ",")
            .compactMap { AgendaWeekday(code: String($0)) }

        let monthDays = (args["repeatOnDay"]?.stringValue ?? "")
            .split(separator: ",")
            .compactMap { part -> Int? in
                let text = part.trimmingCharacters(in: .whitespaces).lowercased()
                return text == "last" ? -1 : Int(text)
            }

        return Recurrence(
            frequency: frequency,
            interval: args["repeatEvery"]?.intValue ?? 1,
            weekdays: weekdays,
            daysOfMonth: monthDays,
            endDate: try args["repeatUntil"]?.stringValue.map(Agenda.date),
            occurrences: args["repeatTimes"]?.intValue
        )
    }

    /// Renders rows, or the empty message when there are none.
    private static func render<T>(_ values: [T], empty: String, line: (T) -> String) -> String {
        values.isEmpty ? empty : values.map(line).joined(separator: "\n")
    }
}
