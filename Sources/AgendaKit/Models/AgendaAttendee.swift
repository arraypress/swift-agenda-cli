//
//  AgendaAttendee.swift
//  SwiftAgenda
//
//  A meeting participant with their RSVP state.
//
//  Created by David Sherlock on 7/19/26.
//

import EventKit
import Foundation

/// Where a participant stands on an invitation.
public enum AttendeeStatus: String, Codable, Sendable, Equatable {

    /// EventKit has no status for them.
    case unknown

    /// Invited, no reply yet.
    case pending

    /// Coming.
    case accepted

    /// Not coming.
    case declined

    /// Might come.
    case tentative

    /// Handed off to someone else.
    case delegated

    /// Their part is done — reminders and tasks only.
    case completed

    /// Their part is under way — reminders and tasks only.
    case inProcess

    /// Reads an `EKParticipantStatus`.
    public init(_ status: EKParticipantStatus) {
        switch status {
        case .pending:    self = .pending
        case .accepted:   self = .accepted
        case .declined:   self = .declined
        case .tentative:  self = .tentative
        case .delegated:  self = .delegated
        case .completed:  self = .completed
        case .inProcess:  self = .inProcess
        default:          self = .unknown
        }
    }
}

/// What part a participant plays.
public enum AttendeeRole: String, Codable, Sendable, Equatable {

    /// EventKit has no role for them.
    case unknown

    /// Expected to attend.
    case required

    /// Invited but not needed.
    case optional

    /// Running the meeting.
    case chair

    /// Copied in without being expected to attend.
    case nonParticipant

    /// Reads an `EKParticipantRole`.
    public init(_ role: EKParticipantRole) {
        switch role {
        case .required:       self = .required
        case .optional:       self = .optional
        case .chair:          self = .chair
        case .nonParticipant: self = .nonParticipant
        default:              self = .unknown
        }
    }
}

/// One participant on an event.
///
/// Kept as a structure rather than a bare display name so "who hasn't replied yet?"
/// stays answerable — RSVP state is the whole point of an attendee list, and
/// flattening it to strings throws that away.
public struct AgendaAttendee: Codable, Sendable, Equatable {

    /// Display name, or the email address when EventKit has no name for them.
    public let name: String

    /// The email parsed out of the participant URL, when it is a `mailto:`.
    public let email: String?

    /// Their RSVP state.
    public let status: AttendeeStatus

    /// Whether they are required, optional, or chairing.
    public let role: AttendeeRole

    /// Whether this participant is you.
    public let isCurrentUser: Bool

    /// Whether this participant organized the event.
    public let isOrganizer: Bool

    /// Creates an attendee.
    public init(name: String, email: String? = nil, status: AttendeeStatus = .unknown,
                role: AttendeeRole = .unknown, isCurrentUser: Bool = false,
                isOrganizer: Bool = false) {
        self.name = name
        self.email = email
        self.status = status
        self.role = role
        self.isCurrentUser = isCurrentUser
        self.isOrganizer = isOrganizer
    }
}

// MARK: - EventKit bridging

extension AgendaAttendee {

    /// Flattens an `EKParticipant`.
    ///
    /// - Parameters:
    ///   - participant: The attendee.
    ///   - organizerURL: The organizer's URL, used to mark who called the meeting —
    ///     `EKParticipant` carries no organizer flag of its own.
    init(_ participant: EKParticipant, organizerURL: URL? = nil) {
        let raw = participant.url.absoluteString
        let email = raw.hasPrefix("mailto:") ? String(raw.dropFirst("mailto:".count)) : nil
        self.init(
            name: participant.name?.nilIfBlank ?? email ?? "Unknown",
            email: email,
            status: AttendeeStatus(participant.participantStatus),
            role: AttendeeRole(participant.participantRole),
            isCurrentUser: participant.isCurrentUser,
            isOrganizer: organizerURL.map { $0 == participant.url } ?? false
        )
    }
}

/// A place with optional coordinates.
///
/// EventKit keeps a geocoded location alongside the free-text one; the coordinates
/// are what a geofenced alarm fires on, so they are carried rather than collapsed
/// into the title.
public struct AgendaLocation: Codable, Sendable, Equatable {

    /// The place name, when one was given.
    public let title: String?

    /// Degrees north, -90…90. Nil when the location is text-only.
    public let latitude: Double?

    /// Degrees east, -180…180. Nil when the location is text-only.
    public let longitude: Double?

    /// Geofence radius in metres. 0 means EventKit's default.
    public let radius: Double

    /// Creates a location. Supply both coordinates for it to be geofenceable.
    public init(title: String?, latitude: Double? = nil, longitude: Double? = nil, radius: Double = 0) {
        self.title = title
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
    }

    /// Whether this carries usable coordinates.
    public var hasCoordinates: Bool { latitude != nil && longitude != nil }
}

// MARK: - EventKit bridging

extension AgendaLocation {

    /// Flattens an `EKStructuredLocation`, or nil when there is nothing to carry.
    init?(_ location: EKStructuredLocation?) {
        guard let location else { return nil }
        let coordinate = location.geoLocation?.coordinate
        guard location.title?.nilIfBlank != nil || coordinate != nil else { return nil }
        self.init(
            title: location.title?.nilIfBlank,
            latitude: coordinate?.latitude,
            longitude: coordinate?.longitude,
            radius: location.radius
        )
    }

    /// Builds the `EKStructuredLocation` EventKit needs to store this.
    ///
    /// Coordinates are only attached when both are present — a half-specified
    /// location would geofence at the equator.
    var ekLocation: EKStructuredLocation {
        let location = EKStructuredLocation(title: title ?? "")
        if let latitude, let longitude {
            location.geoLocation = CLLocation(latitude: latitude, longitude: longitude)
        }
        location.radius = radius
        return location
    }
}
