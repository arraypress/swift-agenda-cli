//
//  SearchAndEditTests.swift
//  SwiftAgenda
//
//  Text matching, extended duration units, and the change-set semantics that make
//  "clear this field" distinguishable from "leave it alone".
//
//  Created by David Sherlock on 7/19/26.
//

import XCTest
@testable import AgendaKit

final class TextMatchingTests: XCTestCase {

    func testMatchesAnyField() {
        XCTAssertTrue(Agenda.matches("flight", in: ["Flight to Berlin", nil, nil]))
        XCTAssertTrue(Agenda.matches("berlin", in: [nil, "Landing in Berlin at 9", nil]))
        XCTAssertTrue(Agenda.matches("heathrow", in: [nil, nil, "Heathrow T5"]))
    }

    func testIsCaseInsensitive() {
        XCTAssertTrue(Agenda.matches("FLIGHT", in: ["my flight", nil]))
        XCTAssertTrue(Agenda.matches("flight", in: ["MY FLIGHT", nil]))
    }

    func testIsDiacriticInsensitive() {
        // Airlines spell it properly; people searching do not.
        XCTAssertTrue(Agenda.matches("zurich", in: ["Flight to Zürich", nil]))
        XCTAssertTrue(Agenda.matches("Malaga", in: ["Málaga trip", nil]))
    }

    func testMatchesSubstringMidWord() {
        XCTAssertTrue(Agenda.matches("BA278", in: [nil, "Booking ref BA278X", nil]))
    }

    func testIgnoresNilFields() {
        XCTAssertFalse(Agenda.matches("flight", in: [nil, nil, nil]))
    }

    func testNoFalsePositive() {
        XCTAssertFalse(Agenda.matches("flight", in: ["Dentist", "Bring card", "High Street"]))
    }
}

final class ExtendedDurationTests: XCTestCase {

    func testMonthsAndYears() throws {
        XCTAssertEqual(try Agenda.duration("1mo"), 2_592_000)
        XCTAssertEqual(try Agenda.duration("6mo"), 6 * 2_592_000)
        XCTAssertEqual(try Agenda.duration("1y"), 31_536_000)
    }

    /// The suffix table is longest-first so `mo` is not eaten by the `m` rule.
    func testMonthsDoNotCollideWithMinutes() throws {
        XCTAssertEqual(try Agenda.duration("5m"), 300)
        XCTAssertEqual(try Agenda.duration("5mo"), 5 * 2_592_000)
        XCTAssertNotEqual(try Agenda.duration("5m"), try Agenda.duration("5mo"))
    }

    func testFractionalValues() throws {
        XCTAssertEqual(try Agenda.duration("1.5h"), 5_400)
    }

    func testBareNumberStillMinutes() throws {
        XCTAssertEqual(try Agenda.duration("90"), 5_400)
    }

    func testRejectsUnknownUnits() {
        for raw in ["5x", "y", "mo", "-1y", "0mo"] {
            XCTAssertThrowsError(try Agenda.duration(raw), "expected \(raw) to fail")
        }
    }
}

final class ReminderChangesTests: XCTestCase {

    func testEmptyByDefault() {
        XCTAssertTrue(ReminderChanges().isEmpty)
    }

    func testAnyFieldMakesItNonEmpty() {
        XCTAssertFalse(ReminderChanges(title: "x").isEmpty)
        XCTAssertFalse(ReminderChanges(priority: 1).isEmpty)
        XCTAssertFalse(ReminderChanges(alarms: []).isEmpty)
    }

    /// The distinction the double-optional exists for: leaving a due date alone is not
    /// the same as removing it.
    func testClearingIsDistinctFromLeavingAlone() {
        let untouched = ReminderChanges()
        let cleared = ReminderChanges(dueAt: .some(nil))
        let replaced = ReminderChanges(dueAt: .some(Date()))

        XCTAssertTrue(untouched.isEmpty)
        XCTAssertFalse(cleared.isEmpty)
        XCTAssertFalse(replaced.isEmpty)
        XCTAssertNil(untouched.dueAt)
        XCTAssertEqual(cleared.dueAt, .some(nil))
    }

    func testClearingRecurrenceIsExpressible() {
        let stop = ReminderChanges(recurrence: .some(nil))
        XCTAssertFalse(stop.isEmpty)
        XCTAssertEqual(stop.recurrence, .some(nil))
    }
}

final class EventChangesTests: XCTestCase {

    func testEmptyByDefault() {
        XCTAssertTrue(EventChanges().isEmpty)
    }

    func testNewFieldsCountTowardsNonEmpty() {
        XCTAssertFalse(EventChanges(availability: .free).isEmpty)
        XCTAssertFalse(EventChanges(recurrence: .some(nil)).isEmpty)
        XCTAssertFalse(EventChanges(alarms: []).isEmpty)
    }

    func testClearingRepeatIsDistinctFromLeavingAlone() {
        XCTAssertNil(EventChanges().recurrence)
        XCTAssertEqual(EventChanges(recurrence: .some(nil)).recurrence, .some(nil))
    }
}

final class SearchResultTests: XCTestCase {

    private var event: AgendaEvent {
        AgendaEvent(id: "e", title: "Flight", calendar: "Home",
                    startsAt: Date(timeIntervalSince1970: 1_800_000_000),
                    endsAt: Date(timeIntervalSince1970: 1_800_003_600), isAllDay: false)
    }

    func testCarriesSortDateAndTitle() {
        XCTAssertEqual(SearchResult.event(event).title, "Flight")
        XCTAssertEqual(SearchResult.event(event).sortDate, event.startsAt)
    }

    func testUndatedReminderHasNoSortDate() {
        let reminder = AgendaReminder(id: "r", title: "Someday", list: "Yes")
        XCTAssertNil(SearchResult.reminder(reminder).sortDate)
    }
}
