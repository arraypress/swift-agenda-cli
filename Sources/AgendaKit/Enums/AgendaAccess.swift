//
//  AgendaAccess.swift
//  SwiftAgenda
//
//  A three-state authorization result, flattened from EventKit's five.
//
//  Created by David Sherlock on 7/19/26.
//

import EventKit
import Foundation

/// Whether an entity type can be read.
///
/// EventKit reports five statuses; only three change what a caller does. `.restricted`
/// and `.writeOnly` both fold into ``denied`` because neither permits the reads this
/// package is built around.
public enum AgendaAccess: String, Codable, Sendable, Equatable {

    /// Never asked. A prompt will appear on first request.
    case notDetermined

    /// Full access granted.
    case authorized

    /// Declined, restricted by policy, or write-only.
    case denied

    /// Flattens an `EKAuthorizationStatus`.
    public init(_ status: EKAuthorizationStatus) {
        switch status {
        case .notDetermined:  self = .notDetermined
        case .fullAccess:     self = .authorized
        case .authorized:     self = .authorized
        default:              self = .denied
        }
    }

    /// The fix to print when this is not ``authorized``, or `nil` when it is.
    public var remedy: String? {
        switch self {
        case .authorized:     return nil
        case .notDetermined:  return "Not yet requested — run any agenda command to trigger the prompt."
        case .denied:         return "Denied — enable agenda in System Settings → Privacy & Security."
        }
    }
}
