//
//  RelativeDateTests.swift
//  SwiftAgenda
//
//  The plain-language date grammar. Pinned to a fixed zone so weekday maths does not
//  depend on where the machine sits.
//
//  Created by David Sherlock on 7/19/26.
//

import XCTest
@testable import AgendaKit

final class RelativeDateTests: TimeZonedTestCase {

    override func setUp() {
        super.setUp()
        use("UTC")
    }

    private func parts(_ date: Date) -> DateComponents {
        Agenda.calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: date)
    }

    private func daysFromToday(_ date: Date) -> Int {
        let today = Agenda.calendar.startOfDay(for: Date())
        let target = Agenda.calendar.startOfDay(for: date)
        return Agenda.calendar.dateComponents([.day], from: today, to: target).day ?? 0
    }

    // MARK: - Keywords

    func testNowIsImmediate() throws {
        let parsed = try Agenda.date("now")
        XCTAssertEqual(parsed.timeIntervalSinceNow, 0, accuracy: 2)
    }

    func testTodayTomorrowYesterday() throws {
        XCTAssertEqual(daysFromToday(try Agenda.date("today")), 0)
        XCTAssertEqual(daysFromToday(try Agenda.date("tomorrow")), 1)
        XCTAssertEqual(daysFromToday(try Agenda.date("yesterday")), -1)
    }

    func testBareDayIsMidnight() throws {
        XCTAssertEqual(parts(try Agenda.date("tomorrow")).hour, 0)
        XCTAssertEqual(parts(try Agenda.date("tomorrow")).minute, 0)
    }

    func testIsCaseInsensitive() throws {
        XCTAssertEqual(daysFromToday(try Agenda.date("TOMORROW")), 1)
        XCTAssertEqual(daysFromToday(try Agenda.date("Tomorrow")), 1)
    }

    // MARK: - Times

    func testTwelveHourTimes() throws {
        XCTAssertEqual(parts(try Agenda.date("today 9am")).hour, 9)
        XCTAssertEqual(parts(try Agenda.date("today 5pm")).hour, 17)
        XCTAssertEqual(parts(try Agenda.date("today 9:30am")).minute, 30)
    }

    func testTwentyFourHourTimes() throws {
        XCTAssertEqual(parts(try Agenda.date("today 14:30")).hour, 14)
        XCTAssertEqual(parts(try Agenda.date("today 14:30")).minute, 30)
        XCTAssertEqual(parts(try Agenda.date("today 00:15")).hour, 0)
    }

    /// The two hours everyone gets wrong.
    func testMidnightAndNoon() throws {
        XCTAssertEqual(parts(try Agenda.date("today 12am")).hour, 0)
        XCTAssertEqual(parts(try Agenda.date("today 12pm")).hour, 12)
    }

    func testRejectsImpossibleTimes() {
        // Clamping 25:00 to 1am would schedule this on the wrong day entirely.
        XCTAssertThrowsError(try Agenda.date("today 25:00"))
        XCTAssertThrowsError(try Agenda.date("today 13pm"))
        XCTAssertThrowsError(try Agenda.date("today 9:75"))
    }

    // MARK: - Weekdays

    func testBareWeekdayIsUpcomingIncludingToday() throws {
        for (name, number) in [("sunday", 1), ("monday", 2), ("friday", 6)] {
            let parsed = try Agenda.date(name)
            XCTAssertEqual(parts(parsed).weekday, number, "\(name) landed on the wrong weekday")
            let offset = daysFromToday(parsed)
            XCTAssertTrue((0...6).contains(offset), "\(name) was \(offset) days out")
        }
    }

    func testAbbreviationsWork() throws {
        XCTAssertEqual(parts(try Agenda.date("mon")).weekday, 2)
        XCTAssertEqual(parts(try Agenda.date("fri")).weekday, 6)
    }

    /// `next monday` must never collapse onto the same day as `monday`, or the word
    /// "next" carries no meaning.
    func testNextWeekdayIsAlwaysAWeekLater() throws {
        for name in ["sunday", "monday", "wednesday", "saturday"] {
            let bare = try Agenda.date(name)
            let next = try Agenda.date("next \(name)")
            XCTAssertEqual(parts(bare).weekday, parts(next).weekday)
            XCTAssertEqual(daysFromToday(next) - daysFromToday(bare), 7,
                           "next \(name) should be exactly a week after \(name)")
        }
    }

    func testWeekdayWithTime() throws {
        let parsed = try Agenda.date("monday 14:30")
        XCTAssertEqual(parts(parsed).weekday, 2)
        XCTAssertEqual(parts(parsed).hour, 14)
    }

    func testNextWeekdayWithTimeKeepsTwoWordPhrase() throws {
        let parsed = try Agenda.date("next friday 9am")
        XCTAssertEqual(parts(parsed).weekday, 6)
        XCTAssertEqual(parts(parsed).hour, 9)
        XCTAssertGreaterThanOrEqual(daysFromToday(parsed), 7)
    }

    // MARK: - Offsets

    func testForwardOffsets() throws {
        XCTAssertEqual(try Agenda.date("+2d").timeIntervalSinceNow, 172_800, accuracy: 2)
        XCTAssertEqual(try Agenda.date("+90m").timeIntervalSinceNow, 5_400, accuracy: 2)
        XCTAssertEqual(try Agenda.date("+1y").timeIntervalSinceNow, 31_536_000, accuracy: 2)
    }

    func testSignedBackwardOffset() throws {
        XCTAssertEqual(try Agenda.date("-1w").timeIntervalSinceNow, -604_800, accuracy: 2)
    }

    /// `ago` exists because argument parsers read a leading `-` as an option name,
    /// making `--at -1w` unusable without `=` quoting.
    func testAgoMatchesTheSignedForm() throws {
        let signed = try Agenda.date("-2d")
        let spoken = try Agenda.date("2d ago")
        XCTAssertEqual(signed.timeIntervalSince(spoken), 0, accuracy: 2)
    }

    // MARK: - Fallthrough

    func testISOStillParses() throws {
        let parsed = try Agenda.date("2026-07-19T14:30")
        XCTAssertEqual(parts(parsed).year, 2026)
        XCTAssertEqual(parts(parsed).hour, 14)
    }

    func testRejectsUnknownPhrases() {
        for raw in ["someday", "next", "next quarter", "the 5th", ""] {
            XCTAssertThrowsError(try Agenda.date(raw), "expected \"\(raw)\" to fail")
        }
    }

    func testRelativeParserReturnsNilForISO() {
        // ISO input must fall through to the strict parser rather than being guessed at.
        XCTAssertNil(Agenda.relativeDate("2026-07-19"))
        XCTAssertNil(Agenda.relativeDate("2026-07-19T14:30"))
    }
}
