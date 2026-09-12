//
//  HiddenCalendars.swift
//  agenda
//
//  Created by David Sherlock on 2026.
//
//  The calendars EventKit will not show you.
//
//  CALENDAR.APP SEES MORE THAN EVENTKIT DOES, and nothing in the API says so. A real machine
//  listed eight calendars in Calendar.app and six through `EKEventStore` — the two missing
//  were "Siri Suggestions" and "Scheduled Reminders", which macOS fills in from Mail. A
//  booking confirmation that has not been accepted yet lives there.
//
//  MEASURED, not inferred: `store.events(matching:)` over a window containing a suggested
//  flight, with NO calendar filter, returns zero events. The calendar is not hidden behind a
//  flag or a filter this tool could lift. EventKit cannot reach it.
//
//  WHY IT MATTERS ENOUGH TO CHECK. The failure is silent and it is the worst shape a failure
//  can take: `agenda today` answers "Nothing scheduled" while Calendar.app shows a flight
//  leaving in an hour. An empty answer that is wrong reads exactly like an empty answer that
//  is right. So when the answer IS empty, this looks over the fence and says what it saw.
//
//  IT ASKS CALENDAR.APP, and that needs Automation permission which EventKit access does not
//  cover. A refusal is silent on purpose: the warning is a courtesy on an empty result, and
//  turning it into a second permission prompt would make the tool worse for everyone who
//  never had a suggested event in the first place.
//

import AgendaKit
import EventKit
import Foundation

enum HiddenCalendars {

    /// Calendars Calendar.app lists that EventKit does not.
    ///
    /// Empty when there are none, when Calendar.app cannot be asked, or when anything at all
    /// goes wrong — this is advisory and must never be the reason a command fails.
    static func names() -> [String] {
        guard let visible = try? Agenda.calendars(for: .event).map(\.title) else { return [] }
        guard let shown = ask() else { return [] }
        let known = Set(visible.map { $0.lowercased() })
        // Reminder lists show up in Calendar.app's list too and are not missing events, so
        // anything EventKit knows as a reminder list is not news.
        let lists = Set(((try? Agenda.calendars(for: .reminder)) ?? []).map { $0.title.lowercased() })
        return shown.filter { !known.contains($0.lowercased()) && !lists.contains($0.lowercased()) }
    }

    /// Calendar.app's own list of calendar titles.
    private static func ask() -> [String]? {
        let script = "tell application \"Calendar\" to return title of every calendar"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// The line to print after an empty answer, or `nil` when there is nothing to add.
    static func note() -> String? {
        let hidden = names()
        guard !hidden.isEmpty else { return nil }
        return "\nNote: Calendar.app also shows \(hidden.joined(separator: " and "))"
             + ", which EventKit does not expose — anything in there is invisible here."
             + "\nSuggested events from Mail live in Siri Suggestions until you accept them."
    }
}
