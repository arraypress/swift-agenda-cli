//
//  AgendaAvailability.swift
//  SwiftAgenda
//
//  How an event marks your time, and where it stands.
//
//  Created by David Sherlock on 7/19/26.
//

import EventKit
import Foundation

/// How an event presents your time to others.
///
/// This is what free/busy lookups read, and it is why ``Agenda/freeSlots(ofAtLeast:from:through:within:)``
/// can be told to ignore events marked ``free`` — a "focus block" holding the slot
/// open is not the same as a meeting.
public enum AgendaAvailability: String, Codable, Sendable, Equatable, CaseIterable {

    /// Time is taken. The default for a new event.
    case busy

    /// On the calendar but not consuming the slot — a placeholder or reference.
    case free

    /// Provisionally booked.
    case tentative

    /// Out of office.
    case unavailable

    /// The matching `EKEventAvailability`.
    public var ekAvailability: EKEventAvailability {
        switch self {
        case .busy:        return .busy
        case .free:        return .free
        case .tentative:   return .tentative
        case .unavailable: return .unavailable
        }
    }

    /// Reads an `EKEventAvailability`. `.notSupported` folds into ``busy``, since a
    /// calendar that cannot express availability is conservatively treated as booked.
    public init(_ availability: EKEventAvailability) {
        switch availability {
        case .free:        self = .free
        case .tentative:   self = .tentative
        case .unavailable: self = .unavailable
        default:           self = .busy
        }
    }
}

/// Where an event stands with its attendees.
public enum AgendaStatus: String, Codable, Sendable, Equatable {

    /// No status set — the usual state for an event you created yourself.
    case none

    /// Confirmed by the organizer.
    case confirmed

    /// Provisional.
    case tentative

    /// Called off. Often still visible on the calendar.
    case canceled

    /// Reads an `EKEventStatus`.
    public init(_ status: EKEventStatus) {
        switch status {
        case .confirmed: self = .confirmed
        case .tentative: self = .tentative
        case .canceled:  self = .canceled
        default:         self = .none
        }
    }
}
