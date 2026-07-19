//
//  AgendaFrequency.swift
//  SwiftAgenda
//
//  How often a recurring item repeats.
//
//  Created by David Sherlock on 7/19/26.
//

import EventKit
import Foundation

/// The base cadence of a recurrence rule.
public enum AgendaFrequency: String, Codable, Sendable, Equatable, CaseIterable {

    /// Every day.
    case daily

    /// Every week.
    case weekly

    /// Every month.
    case monthly

    /// Every year.
    case yearly

    /// The matching `EKRecurrenceFrequency`.
    public var ekFrequency: EKRecurrenceFrequency {
        switch self {
        case .daily:   return .daily
        case .weekly:  return .weekly
        case .monthly: return .monthly
        case .yearly:  return .yearly
        }
    }

    /// Reads an `EKRecurrenceFrequency`.
    public init(_ frequency: EKRecurrenceFrequency) {
        switch frequency {
        case .daily:   self = .daily
        case .weekly:  self = .weekly
        case .monthly: self = .monthly
        case .yearly:  self = .yearly
        @unknown default: self = .daily
        }
    }
}

/// A day of the week, in the two-letter form iCalendar and most CLIs use.
public enum AgendaWeekday: String, Codable, Sendable, Equatable, CaseIterable {

    /// Sunday.
    case sunday = "SU"

    /// Monday.
    case monday = "MO"

    /// Tuesday.
    case tuesday = "TU"

    /// Wednesday.
    case wednesday = "WE"

    /// Thursday.
    case thursday = "TH"

    /// Friday.
    case friday = "FR"

    /// Saturday.
    case saturday = "SA"

    /// The matching `EKWeekday`.
    public var ekWeekday: EKWeekday {
        switch self {
        case .sunday:    return .sunday
        case .monday:    return .monday
        case .tuesday:   return .tuesday
        case .wednesday: return .wednesday
        case .thursday:  return .thursday
        case .friday:    return .friday
        case .saturday:  return .saturday
        }
    }

    /// Reads an `EKWeekday`.
    public init(_ weekday: EKWeekday) {
        switch weekday {
        case .sunday:    self = .sunday
        case .monday:    self = .monday
        case .tuesday:   self = .tuesday
        case .wednesday: self = .wednesday
        case .thursday:  self = .thursday
        case .friday:    self = .friday
        case .saturday:  self = .saturday
        @unknown default: self = .monday
        }
    }

    /// Parses a two-letter code, case-insensitively.
    public init?(code: String) {
        guard let match = Self(rawValue: code.trimmingCharacters(in: .whitespaces).uppercased()) else {
            return nil
        }
        self = match
    }
}
