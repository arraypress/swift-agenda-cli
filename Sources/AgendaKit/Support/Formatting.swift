//
//  Formatting.swift
//  AgendaKit
//
//  Created by David Sherlock on 2026.
//
//  The alarm-offset label rule: minutes up to an hour, whole hours up
//  to a day, whole days beyond. A pure function so the bucket
//  boundaries are pinned by name.
//

import Foundation

/// Presentation formatting for derived, human-readable strings.
enum Formatting {

    /// An offset in minutes as `"45m"`, `"3h"` or `"2d"`.
    static func offsetLabel(minutes: Int) -> String {
        switch minutes {
        case ..<60:    return "\(minutes)m"
        case ..<1_440: return "\(minutes / 60)h"
        default:       return "\(minutes / 1_440)d"
        }
    }
}
