//
//  OpenTarget.swift
//  agenda
//
//  Created by David Sherlock on 2026.
//
//  What `agenda open` hands to another calendar app.
//
//  THE LINKS ARE AGENDAKIT'S, and so is the record of what each app can take. This file only
//  decides between them: an app with a link gets the link, and Calendar.app — which has no
//  link for a date at all — gets the AppleScript that drives it there instead.
//
//  AN EVENT FALLS BACK TO ITS DAY. Google Calendar and Fantastical cannot be pointed at a
//  single event (EventKit does not expose Google's event id, and Fantastical documents no such
//  link), so AgendaKit already gives the day for those. The one gap left is Calendar.app on a
//  record with no `calendarItemId`, which also lands on the event's day rather than failing.
//

import AgendaKit
import ArgumentParser
import Foundation

/// The apps `--in` accepts, by the short names a person types.
enum OpenApp: String, ExpressibleByArgument, CaseIterable {
    case calendar
    case google
    case fantastical
    case busycal

    /// The AgendaKit app this names.
    var app: CalendarApp {
        switch self {
        case .calendar:    return .appleCalendar
        case .google:      return .googleCalendar
        case .fantastical: return .fantastical
        case .busycal:     return .busyCal
        }
    }
}

extension CalendarView: ExpressibleByArgument {}

/// One way of making an app show something: a link for `open`, or a script for `osascript`.
enum Launch: Equatable {
    case url(URL)
    case script(String)
}

enum OpenTarget {

    /// Reads `phrase` as a day, or `nil` when it is not a date — in which case it is taken
    /// to be an event id.
    ///
    /// Dates are tried first because the parse is pure and an id never reads as one; an id
    /// lookup needs the calendar.
    static func day(from phrase: String) -> Date? {
        try? Agenda.date(phrase)
    }

    /// How to show the `view` around `date` in `app`.
    static func launch(day date: Date, in app: CalendarApp, view: CalendarView) -> Launch {
        if let url = Agenda.openURL(in: app, at: date, view: view) { return .url(url) }
        return .script(Agenda.calendarScript(showing: date, view: view))
    }

    /// How to show `event` in `app`, or its day where the app has no link for the event.
    static func launch(event: AgendaEvent, in app: CalendarApp) -> Launch {
        if let url = event.openURL(in: app) { return .url(url) }
        return launch(day: event.startsAt, in: app, view: .day)
    }
}
