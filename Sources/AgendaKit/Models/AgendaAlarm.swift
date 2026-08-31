//
//  AgendaAlarm.swift
//  SwiftAgenda
//
//  Alerts attached to an event or reminder.
//
//  Created by David Sherlock on 7/19/26.
//

import EventKit
import Foundation

/// Whether an alarm fires on crossing a geofence, and in which direction.
public enum AlarmProximity: String, Codable, Sendable, Equatable, CaseIterable {

    /// No geofence — the alarm is purely time-based.
    case none

    /// Fires on arriving at the location.
    case enter

    /// Fires on leaving the location.
    case leave

    /// The matching `EKAlarmProximity`.
    public var ekProximity: EKAlarmProximity {
        switch self {
        case .none:  return .none
        case .enter: return .enter
        case .leave: return .leave
        }
    }

    /// Reads an `EKAlarmProximity`.
    public init(_ proximity: EKAlarmProximity) {
        switch proximity {
        case .enter: self = .enter
        case .leave: self = .leave
        default:     self = .none
        }
    }
}

/// An alert on an event or reminder.
///
/// Either relative to the item's start (the common case — "15 minutes before"),
/// pinned to an absolute moment, or triggered by crossing a geofence.
public struct AgendaAlarm: Codable, Sendable, Equatable {

    /// Seconds relative to the item's start. Negative fires before, which is almost
    /// always what is wanted.
    public var relativeOffset: TimeInterval?

    /// A fixed moment to fire at, independent of the item's start.
    public var absoluteDate: Date?

    /// The geofence to watch, when this is a location alarm.
    public var location: AgendaLocation?

    /// Which direction of geofence crossing fires this.
    public var proximity: AlarmProximity

    /// An alert `interval` before the item starts.
    public static func before(_ interval: TimeInterval) -> AgendaAlarm {
        AgendaAlarm(relativeOffset: -abs(interval))
    }

    /// An alert at a fixed moment.
    public static func at(_ date: Date) -> AgendaAlarm {
        AgendaAlarm(absoluteDate: date)
    }

    /// An alert that fires on arriving at `location`.
    ///
    /// - Note: A geofenced alarm needs coordinates, not just a place name — EventKit
    ///   has nothing to watch without them. Pair with a geocoder to turn an address
    ///   into an ``AgendaLocation``.
    public static func arriving(at location: AgendaLocation) -> AgendaAlarm {
        AgendaAlarm(location: location, proximity: .enter)
    }

    /// An alert that fires on leaving `location`.
    public static func leaving(_ location: AgendaLocation) -> AgendaAlarm {
        AgendaAlarm(location: location, proximity: .leave)
    }

    /// Whether this fires on a geofence rather than a clock.
    public var isLocationBased: Bool { proximity != .none && location != nil }

    /// Creates an alarm. Prefer ``before(_:)``, ``at(_:)``, ``arriving(at:)``, or
    /// ``leaving(_:)`` — this is the memberwise escape hatch.
    public init(relativeOffset: TimeInterval? = nil, absoluteDate: Date? = nil,
                location: AgendaLocation? = nil, proximity: AlarmProximity = .none) {
        self.relativeOffset = relativeOffset
        self.absoluteDate = absoluteDate
        self.location = location
        self.proximity = proximity
    }

    /// A one-line description, e.g. "15m before" or "on arriving at Office".
    public var summary: String {
        if isLocationBased {
            let place = location?.title ?? "location"
            return proximity == .enter ? "on arriving at \(place)" : "on leaving \(place)"
        }
        if let absoluteDate {
            return ISO8601DateFormatter().string(from: absoluteDate)
        }
        guard let relativeOffset else { return "unset" }
        let minutes = Int(abs(relativeOffset) / 60)
        // A zero offset has no direction — "at start before" reads as nonsense.
        guard minutes > 0 else { return "at start" }

        let label = Formatting.offsetLabel(minutes: minutes)
        return relativeOffset < 0 ? "\(label) before" : "\(label) after"
    }
}

// MARK: - EventKit bridging

extension AgendaAlarm {

    /// The matching `EKAlarm`.
    ///
    /// A geofenced alarm still carries a time trigger underneath — EventKit requires
    /// one — so a location alarm is built as a zero-offset relative alarm with the
    /// structured location and proximity attached on top.
    var ekAlarm: EKAlarm {
        let alarm: EKAlarm
        if let absoluteDate {
            alarm = EKAlarm(absoluteDate: absoluteDate)
        } else {
            alarm = EKAlarm(relativeOffset: relativeOffset ?? 0)
        }
        if let location, proximity != .none {
            alarm.structuredLocation = location.ekLocation
            alarm.proximity = proximity.ekProximity
        }
        return alarm
    }

    /// Reads an `EKAlarm`.
    ///
    /// `relativeOffset` is 0 for an absolute alarm, so the absolute date is checked
    /// first — otherwise every fixed-time alert would read as "at start".
    init(_ alarm: EKAlarm) {
        self.init(
            relativeOffset: alarm.absoluteDate == nil ? alarm.relativeOffset : nil,
            absoluteDate: alarm.absoluteDate,
            location: AgendaLocation(alarm.structuredLocation),
            proximity: AlarmProximity(alarm.proximity)
        )
    }
}
