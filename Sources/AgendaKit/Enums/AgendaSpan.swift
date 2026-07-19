//
//  AgendaSpan.swift
//  SwiftAgenda
//
//  How far a mutation reaches through a recurring series.
//
//  Created by David Sherlock on 7/19/26.
//

import EventKit
import Foundation

/// Which occurrences of a repeating item a change applies to.
///
/// This is deliberately not defaulted anywhere in the package. `EKSpan.futureEvents`
/// on a weekly standup rewrites every remaining instance, and the difference between
/// that and ``this`` is invisible until months of calendar are already gone — so
/// ``Agenda/deleteEvent(id:span:)`` throws ``AgendaError/spanRequired(_:)`` rather
/// than guessing on the caller's behalf.
public enum AgendaSpan: String, Codable, Sendable, Equatable, CaseIterable {

    /// This occurrence only.
    case this

    /// This occurrence and every later one. Destructive across the series.
    case future

    /// The matching `EKSpan`.
    public var ekSpan: EKSpan {
        switch self {
        case .this:   return .thisEvent
        case .future: return .futureEvents
        }
    }
}
