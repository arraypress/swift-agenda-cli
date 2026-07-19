//
//  TimeZoneTests.swift
//  SwiftAgenda
//
//  Time-zone and daylight-saving behaviour. Every test pins `Agenda.calendar` to a
//  fixed zone so results do not depend on where the machine running them sits.
//
//  Created by David Sherlock on 7/19/26.
//

import XCTest
@testable import AgendaKit

/// Base class that pins and restores the package calendar around each test.
class TimeZonedTestCase: XCTestCase {

    private var original: Calendar!

    override func setUp() {
        super.setUp()
        original = Agenda.calendar
    }

    override func tearDown() {
        Agenda.calendar = original
        super.tearDown()
    }

    /// Points `Agenda.calendar` at `identifier`, failing the test if it is unknown.
    func use(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let zone = TimeZone(identifier: identifier) else {
            return XCTFail("unknown time zone \(identifier)", file: file, line: line)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        Agenda.calendar = calendar
    }

    /// A date built in the currently pinned calendar.
    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var parts = DateComponents()
        parts.year = year; parts.month = month; parts.day = day
        parts.hour = hour; parts.minute = minute
        guard let result = Agenda.calendar.date(from: parts) else {
            XCTFail("could not build \(year)-\(month)-\(day) \(hour):\(minute)")
            return Date()
        }
        return result
    }

    /// The wall-clock hour of `date` in the pinned calendar.
    func hour(of date: Date) -> Int {
        Agenda.calendar.component(.hour, from: date)
    }
}

// MARK: - Parsing

final class DurationTimeZoneTests: TimeZonedTestCase {

    func testDurationIsZoneIndependent() throws {
        // A duration is an elapsed span, not a wall-clock span — it must not shift
        // with the zone, or "7d" would mean different things in different places.
        use("Pacific/Kiritimati")
        let far = try Agenda.duration("7d")
        use("Pacific/Midway")
        XCTAssertEqual(far, try Agenda.duration("7d"))
    }
}

final class DateParsingTimeZoneTests: TimeZonedTestCase {

    func testDateOnlyIsLocalMidnight() throws {
        // ISO8601DateFormatter and the fallback DateFormatter must agree that a bare
        // date means local midnight, not UTC midnight.
        use("America/Los_Angeles")
        let parsed = try Agenda.date("2026-07-19")
        XCTAssertEqual(hour(of: parsed), 0)
        XCTAssertEqual(Agenda.calendar.component(.day, from: parsed), 19)
    }

    func testDateOnlyInAheadOfUTCZone() throws {
        use("Asia/Tokyo")
        let parsed = try Agenda.date("2026-07-19")
        XCTAssertEqual(hour(of: parsed), 0)
        XCTAssertEqual(Agenda.calendar.component(.day, from: parsed), 19)
    }

    func testExplicitOffsetIsHonoured() throws {
        use("America/New_York")
        // 12:00Z is 08:00 in New York on a summer date (EDT, UTC-4).
        let parsed = try Agenda.date("2026-07-19T12:00:00Z")
        XCTAssertEqual(hour(of: parsed), 8)
    }

    func testLocalTimeIsWallClock() throws {
        use("Europe/London")
        let parsed = try Agenda.date("2026-07-19T14:30")
        XCTAssertEqual(hour(of: parsed), 14)
        XCTAssertEqual(Agenda.calendar.component(.minute, from: parsed), 30)
    }
}

// MARK: - Daylight saving

final class DaylightSavingTests: TimeZonedTestCase {

    /// US spring-forward 2026: 8 March, 02:00 → 03:00. There is no 02:30.
    func testSpringForwardDayIsShorter() {
        use("America/New_York")
        let start = Agenda.calendar.startOfDay(for: date(2026, 3, 8))
        let next = Agenda.calendar.date(byAdding: .day, value: 1, to: start)!

        let elapsed = next.timeIntervalSince(start)
        XCTAssertEqual(elapsed, 23 * 3_600, "spring-forward day is 23 hours")
    }

    /// US fall-back 2026: 1 November, 02:00 → 01:00. 01:30 happens twice.
    func testFallBackDayIsLonger() {
        use("America/New_York")
        let start = Agenda.calendar.startOfDay(for: date(2026, 11, 1))
        let next = Agenda.calendar.date(byAdding: .day, value: 1, to: start)!

        XCTAssertEqual(next.timeIntervalSince(start), 25 * 3_600, "fall-back day is 25 hours")
    }

    /// The reason day iteration uses `date(byAdding:)` and not `+ 86_400`.
    func testNaiveDayArithmeticDriftsAcrossDST() {
        use("America/New_York")
        let start = Agenda.calendar.startOfDay(for: date(2026, 3, 8))

        let correct = Agenda.calendar.date(byAdding: .day, value: 1, to: start)!
        let naive = start.addingTimeInterval(86_400)

        XCTAssertNotEqual(correct, naive)
        XCTAssertEqual(hour(of: correct), 0, "calendar arithmetic lands on midnight")
        XCTAssertEqual(hour(of: naive), 1, "adding 86400s overshoots by the DST hour")
    }

    func testWorkingHoursClipHoldsWallClockAcrossSpringForward() {
        use("America/New_York")
        let hours = WorkingHours(startHour: 9, endHour: 18, weekdays: Set(1...7))

        // Friday through Monday, spanning the Sunday clock change.
        let slot = FreeSlot(startsAt: date(2026, 3, 6, 0), endsAt: date(2026, 3, 10, 0))
        let pieces = hours.clip(slot)

        XCTAssertEqual(pieces.count, 4, "one window per day")
        for piece in pieces {
            XCTAssertEqual(hour(of: piece.startsAt), 9, "every window opens at 9am wall clock")
            XCTAssertEqual(hour(of: piece.endsAt), 18, "every window closes at 6pm wall clock")
        }
    }

    func testWorkingHoursClipHoldsWallClockAcrossFallBack() {
        use("America/New_York")
        let hours = WorkingHours(startHour: 9, endHour: 18, weekdays: Set(1...7))

        let slot = FreeSlot(startsAt: date(2026, 10, 30, 0), endsAt: date(2026, 11, 3, 0))
        let pieces = hours.clip(slot)

        XCTAssertEqual(pieces.count, 4)
        for piece in pieces {
            XCTAssertEqual(hour(of: piece.startsAt), 9)
            XCTAssertEqual(hour(of: piece.endsAt), 18)
        }
    }

    /// On a fall-back day the 9–6 window is a real hour longer in elapsed terms.
    func testFallBackWindowIsAnHourLongerInElapsedTime() {
        use("America/New_York")
        // The repeated hour sits inside 01:00–02:00, so a window that starts before it
        // picks up the extra hour.
        let hours = WorkingHours(startHour: 0, endHour: 6, weekdays: Set(1...7))
        let slot = FreeSlot(startsAt: date(2026, 11, 1, 0), endsAt: date(2026, 11, 2, 0))

        let pieces = hours.clip(slot)
        XCTAssertEqual(pieces.count, 1)
        XCTAssertEqual(pieces[0].duration, 7 * 3_600, "00:00–06:00 spans 7 real hours that day")
    }

    /// Europe changes on a different date than the US — a fixed offset would break here.
    func testEuropeanTransitionDiffersFromUS() {
        use("Europe/London")
        // London springs forward 29 March 2026; New York did so on 8 March.
        let londonMarch8 = Agenda.calendar.startOfDay(for: date(2026, 3, 8))
        let nextDay = Agenda.calendar.date(byAdding: .day, value: 1, to: londonMarch8)!
        XCTAssertEqual(nextDay.timeIntervalSince(londonMarch8), 24 * 3_600,
                       "8 March is an ordinary day in London")

        let londonMarch29 = Agenda.calendar.startOfDay(for: date(2026, 3, 29))
        let after = Agenda.calendar.date(byAdding: .day, value: 1, to: londonMarch29)!
        XCTAssertEqual(after.timeIntervalSince(londonMarch29), 23 * 3_600,
                       "29 March is London's short day")
    }
}

// MARK: - Day boundaries

final class DayBoundaryTests: TimeZonedTestCase {

    func testStartOfDayDiffersByZone() {
        use("Asia/Tokyo")
        let tokyo = Agenda.calendar.startOfDay(for: date(2026, 7, 19, 12))

        use("America/Los_Angeles")
        let la = Agenda.calendar.startOfDay(for: date(2026, 7, 19, 12))

        XCTAssertNotEqual(tokyo, la, "midnight is a different instant in each zone")
    }

    func testWeekdayIsEvaluatedInThePinnedZone() {
        // 2026-07-20 is a Monday. Tokyo runs 16 hours ahead of Los Angeles in July,
        // so Monday 08:00 in Tokyo is still Sunday 16:00 in LA — a weekday check has
        // to use the pinned zone rather than the machine's.
        use("Asia/Tokyo")
        let mondayMorning = date(2026, 7, 20, 8)
        XCTAssertEqual(Agenda.calendar.component(.weekday, from: mondayMorning), 2, "Monday in Tokyo")

        use("America/Los_Angeles")
        XCTAssertEqual(Agenda.calendar.component(.weekday, from: mondayMorning), 1, "still Sunday in LA")
    }

    func testWeekendSkippingFollowsThePinnedZone() {
        // The same instant is a working Monday in Tokyo and a non-working Sunday in LA.
        let instant: Date = {
            use("Asia/Tokyo")
            return date(2026, 7, 20, 10)
        }()

        use("Asia/Tokyo")
        let tokyoSlot = FreeSlot(startsAt: instant, endsAt: instant.addingTimeInterval(3_600))
        XCTAssertFalse(WorkingHours.standard.clip(tokyoSlot).isEmpty, "Monday morning in Tokyo")

        use("America/Los_Angeles")
        let laSlot = FreeSlot(startsAt: instant, endsAt: instant.addingTimeInterval(3_600))
        XCTAssertTrue(WorkingHours.standard.clip(laSlot).isEmpty, "Sunday evening in LA")
    }
}

// MARK: - Half-open intervals

final class IntervalBoundaryTests: TimeZonedTestCase {

    func testClipDropsZeroLengthEdgeSlot() {
        use("UTC")
        let hours = WorkingHours(startHour: 9, endHour: 18, weekdays: Set(1...7))

        // A slot ending exactly when the window opens has no overlap to keep.
        let slot = FreeSlot(startsAt: date(2026, 7, 20, 7), endsAt: date(2026, 7, 20, 9))
        XCTAssertTrue(hours.clip(slot).isEmpty)
    }

    func testClipKeepsSlotEndingOneMinuteInside() {
        use("UTC")
        let hours = WorkingHours(startHour: 9, endHour: 18, weekdays: Set(1...7))
        let slot = FreeSlot(startsAt: date(2026, 7, 20, 7), endsAt: date(2026, 7, 20, 9, 1))

        let pieces = hours.clip(slot)
        XCTAssertEqual(pieces.count, 1)
        XCTAssertEqual(pieces[0].duration, 60)
    }

    func testEventCoverageIsHalfOpen() {
        use("UTC")
        let start = date(2026, 7, 20, 9)
        let event = AgendaEvent(id: "1", title: "T", calendar: "C",
                                startsAt: start, endsAt: start.addingTimeInterval(3_600),
                                isAllDay: false)
        XCTAssertTrue(event.covers(start), "start is inside")
        XCTAssertFalse(event.covers(start.addingTimeInterval(3_600)), "end is not")
    }

    func testBackToBackEventsDoNotOverlap() {
        use("UTC")
        let start = date(2026, 7, 20, 9)
        func event(_ from: TimeInterval, _ to: TimeInterval) -> AgendaEvent {
            AgendaEvent(id: UUID().uuidString, title: "T", calendar: "C",
                        startsAt: start.addingTimeInterval(from),
                        endsAt: start.addingTimeInterval(to), isAllDay: false)
        }
        XCTAssertFalse(event(0, 3_600).overlaps(event(3_600, 7_200)))
        XCTAssertTrue(event(0, 3_600).overlaps(event(3_599, 7_200)))
    }
}
