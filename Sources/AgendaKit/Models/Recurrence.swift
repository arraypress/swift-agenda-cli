//
//  Recurrence.swift
//  SwiftAgenda
//
//  A repeat rule, round-tripped between EventKit and the command surface.
//
//  Created by David Sherlock on 7/19/26.
//

import EventKit
import Foundation

/// How an item repeats.
///
/// Covers the shapes people actually schedule — "every weekday", "every other
/// Tuesday", "the 1st of each month", "the last Friday of the month" — without
/// exposing the full iCalendar grammar.
///
/// ```swift
/// // Every other Monday, Wednesday, Friday, twelve times.
/// Recurrence(frequency: .weekly, interval: 2,
///            weekdays: [.monday, .wednesday, .friday], occurrences: 12)
/// ```
public struct Recurrence: Codable, Sendable, Equatable {

    /// The base cadence — daily, weekly, monthly, or yearly.
    public var frequency: AgendaFrequency

    /// Repeat every N periods. 1 means every period.
    public var interval: Int

    /// Which weekdays it lands on. Meaningful for `.weekly` and, with
    /// ``setPositions``, for `.monthly`.
    public var weekdays: [AgendaWeekday]

    /// Days of the month, 1–31 or negative from the end (-1 is the last day).
    public var daysOfMonth: [Int]

    /// Months of the year, 1–12. Meaningful for `.yearly`.
    public var monthsOfYear: [Int]

    /// Which occurrence within the period to pick — 1 is first, -1 is last.
    ///
    /// This is what makes "the last Friday of the month" expressible: `.monthly`
    /// frequency, `weekdays: [.friday]`, `setPositions: [-1]`.
    public var setPositions: [Int]

    /// Stop repeating after this date. Mutually exclusive with ``occurrences``.
    public var endDate: Date?

    /// Stop after this many occurrences, counting the first. Mutually exclusive with
    /// ``endDate``.
    ///
    /// - Note: EventKit's own `occurrenceCount` behaves as "repeats *after* the first",
    ///   so a stored count of 4 materialises three events. This property is the total a
    ///   person means by "four times", and the translation is handled in ``ekRule``.
    public var occurrences: Int?

    /// Creates a repeat rule. `interval` is clamped to at least 1.
    public init(frequency: AgendaFrequency, interval: Int = 1,
                weekdays: [AgendaWeekday] = [], daysOfMonth: [Int] = [],
                monthsOfYear: [Int] = [], setPositions: [Int] = [],
                endDate: Date? = nil, occurrences: Int? = nil) {
        self.frequency = frequency
        self.interval = max(1, interval)
        self.weekdays = weekdays
        self.daysOfMonth = daysOfMonth
        self.monthsOfYear = monthsOfYear
        self.setPositions = setPositions
        self.endDate = endDate
        self.occurrences = occurrences
    }

    /// Monday through Friday, every week.
    public static let everyWeekday = Recurrence(
        frequency: .weekly,
        weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday]
    )

    /// A one-line description, e.g. "every 2 weeks on MO, WE until 1 Dec 2026".
    public var summary: String {
        var text = interval == 1 ? "every \(unitName)" : "every \(interval) \(unitName)s"
        if !weekdays.isEmpty {
            text += " on \(weekdays.map(\.rawValue).joined(separator: ", "))"
        }
        if !daysOfMonth.isEmpty {
            text += " on day \(daysOfMonth.map(String.init).joined(separator: ", "))"
        }
        if !setPositions.isEmpty {
            text += " (\(setPositions.map { $0 == -1 ? "last" : "#\($0)" }.joined(separator: ", ")))"
        }
        if let occurrences { text += ", \(occurrences) times" }
        return text
    }

    private var unitName: String {
        switch frequency {
        case .daily:   return "day"
        case .weekly:  return "week"
        case .monthly: return "month"
        case .yearly:  return "year"
        }
    }
}

// MARK: - EventKit bridging

extension Recurrence {

    /// Builds the `EKRecurrenceRule` EventKit needs to save this.
    ///
    /// EventKit rejects empty arrays where it expects nil, so each optional list is
    /// collapsed back to nil when unused rather than passed through as `[]`.
    var ekRule: EKRecurrenceRule {
        let end: EKRecurrenceEnd? = {
            // EventKit materialises one fewer event than the count it is given — a
            // stored count of 4 yields three. Verified across counts 2, 3, 4 and 5 on
            // macOS 15. The +1 makes ``occurrences`` mean the total number of events,
            // which is what "repeat 4 times" means to everyone who is not EventKit.
            if let occurrences { return EKRecurrenceEnd(occurrenceCount: occurrences + 1) }
            if let endDate { return EKRecurrenceEnd(end: endDate) }
            return nil
        }()

        return EKRecurrenceRule(
            recurrenceWith: frequency.ekFrequency,
            interval: interval,
            daysOfTheWeek: weekdays.isEmpty
                ? nil
                : weekdays.map { EKRecurrenceDayOfWeek($0.ekWeekday) },
            daysOfTheMonth: daysOfMonth.isEmpty ? nil : daysOfMonth.map(NSNumber.init),
            monthsOfTheYear: monthsOfYear.isEmpty ? nil : monthsOfYear.map(NSNumber.init),
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: setPositions.isEmpty ? nil : setPositions.map(NSNumber.init),
            end: end
        )
    }

    /// Reads an `EKRecurrenceRule` back out.
    init(_ rule: EKRecurrenceRule) {
        self.init(
            frequency: AgendaFrequency(rule.frequency),
            interval: rule.interval,
            weekdays: rule.daysOfTheWeek?.map { AgendaWeekday($0.dayOfTheWeek) } ?? [],
            daysOfMonth: rule.daysOfTheMonth?.map(\.intValue) ?? [],
            monthsOfYear: rule.monthsOfTheYear?.map(\.intValue) ?? [],
            setPositions: rule.setPositions?.map(\.intValue) ?? [],
            endDate: rule.recurrenceEnd?.endDate,
            // Undo the +1 applied in `ekRule`. EventKit reports 0 for "no count limit",
            // which must stay nil so the two stop conditions remain exclusive.
            occurrences: (rule.recurrenceEnd?.occurrenceCount).flatMap { $0 > 0 ? $0 - 1 : nil }
        )
    }
}
