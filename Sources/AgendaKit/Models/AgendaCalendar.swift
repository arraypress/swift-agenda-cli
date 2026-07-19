//
//  AgendaCalendar.swift
//  SwiftAgenda
//
//  A calendar or reminder list, flattened for listing and filtering.
//
//  Created by David Sherlock on 7/19/26.
//

import AppKit
import EventKit
import Foundation

/// Where a calendar's data lives.
public enum CalendarKind: String, Codable, Sendable, Equatable {

    /// Stored only on this Mac.
    case local

    /// Synced over CalDAV — iCloud calendars report as this.
    case calDAV

    /// An Exchange account.
    case exchange

    /// A read-only subscribed feed, e.g. a holiday calendar.
    case subscription

    /// The generated Birthdays calendar, sourced from Contacts.
    case birthday

    /// Anything EventKit adds later.
    case unknown

    /// Reads an `EKCalendarType`.
    public init(_ type: EKCalendarType) {
        switch type {
        case .local:        self = .local
        case .calDAV:       self = .calDAV
        case .exchange:     self = .exchange
        case .subscription: self = .subscription
        case .birthday:     self = .birthday
        @unknown default:   self = .unknown
        }
    }
}

/// One calendar (for events) or list (for reminders).
///
/// Built by ``Agenda/calendars(for:)``. ``isWritable`` matters before any create —
/// subscribed and holiday calendars are read-only and EventKit only says so at save
/// time, well after an agent has decided the write should work.
public struct AgendaCalendar: Codable, Sendable, Equatable, Identifiable {

    /// EventKit's calendar identifier.
    public let id: String

    /// The display name, as shown in Calendar.app.
    public let title: String

    /// The account backing this calendar — "iCloud", "Google", "On My Mac".
    public let source: String

    /// Where the data lives, which is what makes a subscribed feed distinguishable
    /// from a calendar you happen to lack write access to.
    public let kind: CalendarKind

    /// Whether new items can be added. False for subscribed and holiday calendars.
    public let isWritable: Bool

    /// Whether this is a subscribed feed rather than a calendar you own.
    public let isSubscribed: Bool

    /// Whether EventKit forbids editing the calendar itself — its title, colour, or
    /// existence — as opposed to the items inside it.
    public let isImmutable: Bool

    /// Whether EventKit marks this as the default for new items.
    public let isDefault: Bool

    /// The calendar's colour as a `#RRGGBB` hex string, when it has one.
    public let color: String?

    /// Availability values this calendar accepts.
    ///
    /// Setting an unsupported one is silently discarded at save time, so a caller
    /// that cares should check here first rather than trusting the write.
    public let supportedAvailabilities: [AgendaAvailability]

    /// Whether this calendar can hold events, reminders, or both.
    public let allowedTypes: [String]

    /// Creates a calendar record.
    public init(id: String, title: String, source: String, kind: CalendarKind = .unknown,
                isWritable: Bool, isSubscribed: Bool = false, isImmutable: Bool = false,
                isDefault: Bool = false, color: String? = nil,
                supportedAvailabilities: [AgendaAvailability] = [],
                allowedTypes: [String] = []) {
        self.id = id
        self.title = title
        self.source = source
        self.kind = kind
        self.isWritable = isWritable
        self.isSubscribed = isSubscribed
        self.isImmutable = isImmutable
        self.isDefault = isDefault
        self.color = color
        self.supportedAvailabilities = supportedAvailabilities
        self.allowedTypes = allowedTypes
    }
}

// MARK: - EventKit bridging

extension AgendaCalendar {

    /// Flattens an `EKCalendar`.
    ///
    /// - Parameters:
    ///   - calendar: The calendar.
    ///   - isDefault: Whether the store nominates this for new items. Passed in
    ///     because `EKCalendar` has no self-knowledge of it.
    init(_ calendar: EKCalendar, isDefault: Bool = false) {
        self.init(
            id: calendar.calendarIdentifier,
            title: calendar.title,
            source: calendar.source?.title ?? "Unknown",
            kind: CalendarKind(calendar.type),
            isWritable: calendar.allowsContentModifications,
            isSubscribed: calendar.isSubscribed,
            isImmutable: calendar.isImmutable,
            isDefault: isDefault,
            color: Self.hex(from: calendar.color),
            supportedAvailabilities: Self.availabilities(calendar.supportedEventAvailabilities),
            allowedTypes: Self.entityTypes(calendar.allowedEntityTypes)
        )
    }

    /// Renders an `NSColor` as `#RRGGBB`.
    ///
    /// Converted into sRGB first — a calendar colour can arrive in a device or
    /// generic colour space where the component accessors trap.
    private static func hex(from color: NSColor?) -> String? {
        guard let converted = color?.usingColorSpace(.sRGB) else { return nil }
        let red = Int((converted.redComponent * 255).rounded())
        let green = Int((converted.greenComponent * 255).rounded())
        let blue = Int((converted.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    /// Unpacks the availability bitmask into the values it permits.
    private static func availabilities(_ mask: EKCalendarEventAvailabilityMask) -> [AgendaAvailability] {
        var found: [AgendaAvailability] = []
        if mask.contains(.busy) { found.append(.busy) }
        if mask.contains(.free) { found.append(.free) }
        if mask.contains(.tentative) { found.append(.tentative) }
        if mask.contains(.unavailable) { found.append(.unavailable) }
        return found
    }

    /// Unpacks the entity bitmask into readable names.
    private static func entityTypes(_ mask: EKEntityMask) -> [String] {
        var found: [String] = []
        if mask.contains(.event) { found.append("event") }
        if mask.contains(.reminder) { found.append("reminder") }
        return found
    }
}
