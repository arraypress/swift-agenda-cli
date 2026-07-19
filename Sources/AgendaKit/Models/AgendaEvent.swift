//
//  AgendaEvent.swift
//  SwiftAgenda
//
//  A calendar event flattened out of EventKit into a serializable value.
//
//  Created by David Sherlock on 7/19/26.
//

import EventKit
import Foundation

/// One calendar event, detached from its `EKEvent`.
///
/// Built by ``Agenda/events(from:to:calendars:)``. Holding a value rather than the
/// `EKEvent` means results stay valid after the store resets, and encode straight to
/// JSON with no formatting layer in between.
public struct AgendaEvent: Codable, Sendable, Equatable, Identifiable {

    /// EventKit's identifier. Stable for single events; shared across every
    /// occurrence of a recurring series, which is why mutations also need a span.
    ///
    /// Local to this Mac. Use ``externalId`` to match the same event across devices.
    public let id: String

    /// The cross-device identifier.
    ///
    /// Unlike ``id``, this survives the calendar being re-synced or opened on another
    /// device — but it is *not* unique locally, since every occurrence of a series
    /// shares one. Store it to re-find an event later; match on ``id`` within a run.
    public let externalId: String?

    /// The event's title, or "Untitled" when it has none.
    public let title: String

    /// Title of the calendar holding this event.
    public let calendar: String

    /// When the event begins.
    public let startsAt: Date

    /// When the event ends. Half-open — an event does not cover this instant.
    public let endsAt: Date

    /// Whether this is an all-day marker rather than a timed event.
    public let isAllDay: Bool

    /// The repeat rule, when this belongs to a series.
    ///
    /// EventKit permits several rules on one event; only the first is carried, since
    /// nothing in Calendar.app can author a second and round-tripping one would drop
    /// it silently.
    public let recurrence: Recurrence?

    /// Alerts set on this event.
    public let alarms: [AgendaAlarm]

    /// Whether this occurrence has been edited away from its series.
    ///
    /// A detached occurrence keeps its own title, time, and location while still
    /// belonging to the rule — which is why "move just this one" produces an event
    /// that looks recurring but no longer follows the pattern.
    public let isDetached: Bool

    /// The date this occurrence was originally scheduled for, before any detachment.
    /// Equals ``startsAt`` for an untouched occurrence.
    public let occurrenceDate: Date?

    /// How this event marks your time for free/busy purposes.
    public let availability: AgendaAvailability

    /// Where the event stands with its attendees.
    public let status: AgendaStatus

    /// The free-text location. See ``structuredLocation`` for coordinates.
    public let location: String?

    /// The event's notes body.
    public let notes: String?

    /// The event's own URL field, as distinct from any link found in the notes.
    public let url: String?

    /// The event's own time zone, when it pins one. Floating events have none.
    public let timeZone: String?

    /// The geocoded location, when one is attached. Carries coordinates that the
    /// free-text ``location`` does not.
    public let structuredLocation: AgendaLocation?

    /// The organizer's display name, when the event came from an invitation.
    public let organizer: String?

    /// Participants with their RSVP state. Empty for solo events.
    public let attendees: [AgendaAttendee]

    /// The contact this birthday event belongs to, for entries on the Birthdays
    /// calendar. Nil for everything else.
    public let birthdayContactId: String?

    /// The first video-call link found in the notes, location, or URL fields.
    public let meetingURL: String?

    /// When the event was created, when the calendar records it.
    public let createdAt: Date?

    /// When the event was last changed.
    public let modifiedAt: Date?

    /// Whether this belongs to a repeating series.
    public var isRecurring: Bool { recurrence != nil }

    /// How long the event runs.
    public var duration: TimeInterval { endsAt.timeIntervalSince(startsAt) }

    /// Attendees who have not yet responded — the answer to "who am I waiting on?".
    public var awaitingReply: [AgendaAttendee] {
        attendees.filter { $0.status == .pending || $0.status == .unknown }
    }

    /// Whether you have declined this event.
    ///
    /// A declined invitation usually still sits on the calendar, so this is what
    /// separates "on my calendar" from "actually attending".
    public var isDeclinedByMe: Bool {
        attendees.contains { $0.isCurrentUser && $0.status == .declined }
    }

    /// Whether this event actually consumes time, for free/busy maths.
    ///
    /// All-day markers, events explicitly marked free, cancelled invitations, and
    /// anything you have declined do not block a slot.
    public var blocksTime: Bool {
        !isAllDay && availability != .free && status != .canceled && !isDeclinedByMe
    }

    /// Whether `date` falls inside this event.
    public func covers(_ date: Date) -> Bool {
        startsAt <= date && endsAt > date
    }

    /// Whether this event's time overlaps `other`'s.
    public func overlaps(_ other: AgendaEvent) -> Bool {
        startsAt < other.endsAt && other.startsAt < endsAt
    }

    /// Creates an event record. Reads build these from `EKEvent`; the memberwise form
    /// exists for tests and for callers assembling results by hand.
    public init(id: String, title: String, calendar: String, startsAt: Date, endsAt: Date,
                isAllDay: Bool, externalId: String? = nil, recurrence: Recurrence? = nil,
                alarms: [AgendaAlarm] = [], isDetached: Bool = false, occurrenceDate: Date? = nil,
                availability: AgendaAvailability = .busy, status: AgendaStatus = .none,
                location: String? = nil, notes: String? = nil, url: String? = nil,
                timeZone: String? = nil, structuredLocation: AgendaLocation? = nil,
                organizer: String? = nil, attendees: [AgendaAttendee] = [],
                birthdayContactId: String? = nil, meetingURL: String? = nil,
                createdAt: Date? = nil, modifiedAt: Date? = nil) {
        self.id = id
        self.externalId = externalId
        self.title = title
        self.calendar = calendar
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.isAllDay = isAllDay
        self.recurrence = recurrence
        self.alarms = alarms
        self.isDetached = isDetached
        self.occurrenceDate = occurrenceDate
        self.availability = availability
        self.status = status
        self.location = location
        self.notes = notes
        self.url = url
        self.timeZone = timeZone
        self.structuredLocation = structuredLocation
        self.organizer = organizer
        self.attendees = attendees
        self.birthdayContactId = birthdayContactId
        self.meetingURL = meetingURL
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

// MARK: - EventKit bridging

extension AgendaEvent {

    /// Flattens an `EKEvent`.
    ///
    /// `title`, `startDate`, and `endDate` are nominally optional on `EKEvent` but are
    /// never nil for an event returned by a date predicate; they fall back to a
    /// placeholder title and `.distantPast`/`.distantFuture` rather than dropping the
    /// row, so a malformed event stays visible instead of silently vanishing.
    init(_ event: EKEvent) {
        let organizerURL = event.organizer?.url
        self.init(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: event.title ?? "Untitled",
            calendar: event.calendar?.title ?? "Unknown",
            startsAt: event.startDate ?? .distantPast,
            endsAt: event.endDate ?? .distantFuture,
            isAllDay: event.isAllDay,
            externalId: event.calendarItemExternalIdentifier,
            recurrence: event.recurrenceRules?.first.map(Recurrence.init),
            alarms: event.alarms?.map(AgendaAlarm.init) ?? [],
            isDetached: event.isDetached,
            occurrenceDate: event.occurrenceDate,
            availability: AgendaAvailability(event.availability),
            status: AgendaStatus(event.status),
            location: event.location?.nilIfBlank,
            notes: event.notes?.nilIfBlank,
            url: event.url?.absoluteString,
            timeZone: event.timeZone?.identifier,
            structuredLocation: AgendaLocation(event.structuredLocation),
            organizer: event.organizer?.name?.nilIfBlank,
            attendees: event.attendees?.map { AgendaAttendee($0, organizerURL: organizerURL) } ?? [],
            birthdayContactId: event.birthdayContactIdentifier,
            meetingURL: Agenda.meetingURL(
                notes: event.notes,
                location: event.location,
                url: event.url?.absoluteString
            ),
            createdAt: event.creationDate,
            modifiedAt: event.lastModifiedDate
        )
    }
}
