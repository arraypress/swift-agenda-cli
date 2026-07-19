//
//  FreeSlot.swift
//  SwiftAgenda
//
//  An unbooked window between events.
//
//  Created by David Sherlock on 7/19/26.
//

import Foundation

/// A gap in the calendar long enough to hold something.
///
/// Returned by ``Agenda/freeSlots(ofAtLeast:from:through:within:)``. Slots are
/// half-open — `endsAt` is the moment the next event begins, so a slot can be
/// scheduled right up to but not including it.
public struct FreeSlot: Codable, Sendable, Equatable {

    /// When the gap opens.
    public let startsAt: Date

    /// When the gap closes — the moment the next commitment begins.
    public let endsAt: Date

    /// How long the gap runs.
    public var duration: TimeInterval { endsAt.timeIntervalSince(startsAt) }

    /// The gap in whole minutes, rounded down.
    public var minutes: Int { Int(duration / 60) }

    /// Creates a slot.
    public init(startsAt: Date, endsAt: Date) {
        self.startsAt = startsAt
        self.endsAt = endsAt
    }

    /// Whether this slot could hold `interval`.
    public func fits(_ interval: TimeInterval) -> Bool { duration >= interval }
}
