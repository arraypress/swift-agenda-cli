//
//  RecurrenceTests.swift
//  SwiftAgenda
//
//  Round-trip and summary tests for repeat rules and alarms. These build real
//  EKRecurrenceRule/EKAlarm objects, which needs no store and no permissions.
//
//  Created by David Sherlock on 7/19/26.
//

import EventKit
import XCTest
@testable import AgendaKit

final class RecurrenceRoundTripTests: XCTestCase {

    /// Rebuilds a rule through EventKit to prove nothing is dropped in translation.
    private func roundTrip(_ recurrence: Recurrence) -> Recurrence {
        Recurrence(recurrence.ekRule)
    }

    func testWeeklyOnWeekdays() {
        let original = Recurrence(frequency: .weekly, weekdays: [.monday, .wednesday, .friday])
        let result = roundTrip(original)
        XCTAssertEqual(result.frequency, .weekly)
        XCTAssertEqual(Set(result.weekdays), [.monday, .wednesday, .friday])
    }

    func testIntervalSurvives() {
        XCTAssertEqual(roundTrip(Recurrence(frequency: .weekly, interval: 3)).interval, 3)
    }

    func testLastFridayOfMonth() {
        let original = Recurrence(frequency: .monthly, weekdays: [.friday], setPositions: [-1])
        let result = roundTrip(original)
        XCTAssertEqual(result.frequency, .monthly)
        XCTAssertEqual(result.weekdays, [.friday])
        XCTAssertEqual(result.setPositions, [-1])
    }

    func testDaysOfMonth() {
        let result = roundTrip(Recurrence(frequency: .monthly, daysOfMonth: [1, 15]))
        XCTAssertEqual(Set(result.daysOfMonth), [1, 15])
    }

    func testYearlyWithMonths() {
        let result = roundTrip(Recurrence(frequency: .yearly, monthsOfYear: [3, 9]))
        XCTAssertEqual(result.frequency, .yearly)
        XCTAssertEqual(Set(result.monthsOfYear), [3, 9])
    }

    func testOccurrenceCountSurvives() {
        XCTAssertEqual(roundTrip(Recurrence(frequency: .daily, occurrences: 10)).occurrences, 10)
    }

    /// Regression: EventKit materialises one fewer event than the count it stores, so
    /// `occurrences: 4` must be written as 5 to produce four events. Verified against
    /// the real store at counts 1, 2 and 4.
    func testOccurrenceCountIsOffsetForEventKit() {
        XCTAssertEqual(Recurrence(frequency: .daily, occurrences: 4).ekRule.recurrenceEnd?.occurrenceCount, 5)
        XCTAssertEqual(Recurrence(frequency: .daily, occurrences: 1).ekRule.recurrenceEnd?.occurrenceCount, 2)
    }

    func testOccurrenceCountRoundTripsAcrossTheOffset() {
        for count in 1...12 {
            XCTAssertEqual(roundTrip(Recurrence(frequency: .weekly, occurrences: count)).occurrences, count)
        }
    }

    func testEndDateDoesNotProduceAnOccurrenceCount() {
        let rule = Recurrence(frequency: .weekly, endDate: Date().addingTimeInterval(86_400 * 30)).ekRule
        // An end-dated rule reports count 0; the -1 on read must not turn that into -1.
        XCTAssertNil(Recurrence(rule).occurrences)
    }

    func testEndDateSurvives() {
        let end = Calendar.current.startOfDay(for: Date().addingTimeInterval(86_400 * 30))
        let result = roundTrip(Recurrence(frequency: .weekly, endDate: end))
        XCTAssertNotNil(result.endDate)
        XCTAssertNil(result.occurrences, "an end date must not surface as an occurrence count")
    }

    func testNoEndConditionStaysNil() {
        let result = roundTrip(Recurrence(frequency: .daily))
        XCTAssertNil(result.endDate)
        XCTAssertNil(result.occurrences, "EventKit reports count 0 for unbounded; that must read as nil")
    }

    func testIntervalIsClampedToOne() {
        XCTAssertEqual(Recurrence(frequency: .daily, interval: 0).interval, 1)
        XCTAssertEqual(Recurrence(frequency: .daily, interval: -5).interval, 1)
    }
}

final class RecurrenceSummaryTests: XCTestCase {

    func testSingularAndPlural() {
        XCTAssertEqual(Recurrence(frequency: .weekly).summary, "every week")
        XCTAssertEqual(Recurrence(frequency: .weekly, interval: 2).summary, "every 2 weeks")
    }

    func testWeekdaysListed() {
        let text = Recurrence(frequency: .weekly, weekdays: [.monday, .friday]).summary
        XCTAssertEqual(text, "every week on MO, FR")
    }

    func testLastPositionReadsAsLast() {
        let text = Recurrence(frequency: .monthly, weekdays: [.friday], setPositions: [-1]).summary
        XCTAssertTrue(text.contains("last"), "got \(text)")
    }

    func testOccurrenceCountShown() {
        XCTAssertTrue(Recurrence(frequency: .daily, occurrences: 5).summary.contains("5 times"))
    }

    func testEveryWeekdayPreset() {
        XCTAssertEqual(Recurrence.everyWeekday.weekdays.count, 5)
        XCTAssertFalse(Recurrence.everyWeekday.weekdays.contains(.sunday))
    }
}

final class WeekdayParsingTests: XCTestCase {

    func testParsesCodesCaseInsensitively() {
        XCTAssertEqual(AgendaWeekday(code: "mo"), .monday)
        XCTAssertEqual(AgendaWeekday(code: " FR "), .friday)
    }

    func testRejectsUnknown() {
        XCTAssertNil(AgendaWeekday(code: "XX"))
    }

    func testEKWeekdayRoundTrip() {
        for day in AgendaWeekday.allCases {
            XCTAssertEqual(AgendaWeekday(day.ekWeekday), day)
        }
    }
}

final class AlarmTests: XCTestCase {

    func testRelativeAlarmIsAlwaysBefore() {
        XCTAssertEqual(AgendaAlarm.before(900).relativeOffset, -900)
        // A positive input still means "before" — that is what a calendar UI means
        // by a 15-minute alert.
        XCTAssertEqual(AgendaAlarm.before(-900).relativeOffset, -900)
    }

    func testRelativeRoundTrip() {
        let result = AgendaAlarm(AgendaAlarm.before(3_600).ekAlarm)
        XCTAssertEqual(result.relativeOffset, -3_600)
        XCTAssertNil(result.absoluteDate)
    }

    func testAbsoluteRoundTripDoesNotCollapseToStart() {
        let when = Date(timeIntervalSince1970: 1_800_000_000)
        let result = AgendaAlarm(AgendaAlarm.at(when).ekAlarm)
        XCTAssertEqual(result.absoluteDate?.timeIntervalSince1970, when.timeIntervalSince1970)
        XCTAssertNil(result.relativeOffset, "an absolute alarm must not read as a 0 offset")
    }

    func testSummaryUnits() {
        XCTAssertEqual(AgendaAlarm.before(900).summary, "15m before")
        XCTAssertEqual(AgendaAlarm.before(7_200).summary, "2h before")
        XCTAssertEqual(AgendaAlarm.before(86_400).summary, "1d before")
        XCTAssertEqual(AgendaAlarm(relativeOffset: 0).summary, "at start")
    }
}

final class AvailabilityTests: XCTestCase {

    func testRoundTrip() {
        for value in AgendaAvailability.allCases {
            XCTAssertEqual(AgendaAvailability(value.ekAvailability), value)
        }
    }

    func testUnsupportedFoldsToBusy() {
        XCTAssertEqual(AgendaAvailability(.notSupported), .busy)
    }
}

final class BlocksTimeTests: XCTestCase {

    private func event(allDay: Bool = false,
                       availability: AgendaAvailability = .busy,
                       status: AgendaStatus = .none) -> AgendaEvent {
        AgendaEvent(id: "1", title: "T", calendar: "C",
                    startsAt: Date(), endsAt: Date().addingTimeInterval(3_600),
                    isAllDay: allDay, availability: availability, status: status)
    }

    func testOrdinaryEventBlocks() {
        XCTAssertTrue(event().blocksTime)
    }

    func testAllDayDoesNotBlock() {
        XCTAssertFalse(event(allDay: true).blocksTime)
    }

    func testFreeDoesNotBlock() {
        XCTAssertFalse(event(availability: .free).blocksTime)
    }

    func testCancelledDoesNotBlock() {
        XCTAssertFalse(event(status: .canceled).blocksTime)
    }

    func testTentativeStillBlocks() {
        XCTAssertTrue(event(availability: .tentative).blocksTime)
    }
}
