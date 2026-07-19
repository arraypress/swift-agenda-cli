//
//  AgendaKitTests.swift
//  SwiftAgenda
//
//  Unit tests for the pure logic — parsing, slot maths, model derivation.
//  Nothing here touches EventKit, so the suite runs without permissions.
//
//  Created by David Sherlock on 7/19/26.
//

import XCTest
@testable import AgendaKit

final class DurationParsingTests: XCTestCase {

    func testUnits() throws {
        XCTAssertEqual(try Agenda.duration("30m"), 1_800)
        XCTAssertEqual(try Agenda.duration("4h"), 14_400)
        XCTAssertEqual(try Agenda.duration("7d"), 604_800)
        XCTAssertEqual(try Agenda.duration("2w"), 1_209_600)
    }

    func testBareNumberIsMinutes() throws {
        XCTAssertEqual(try Agenda.duration("90"), 5_400)
    }

    func testCaseAndWhitespaceTolerated() throws {
        XCTAssertEqual(try Agenda.duration(" 4H "), 14_400)
    }

    func testRejectsNonsense() {
        // `5y` is valid — see ExtendedDurationTests for the month/year units.
        for raw in ["", "abc", "-5m", "0h", "m", "5q"] {
            XCTAssertThrowsError(try Agenda.duration(raw), "expected \(raw) to fail")
        }
    }
}

final class DateParsingTests: XCTestCase {

    func testDateOnlyResolvesToStartOfDay() throws {
        let parsed = try Agenda.date("2026-07-19")
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour], from: parsed)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 7)
        XCTAssertEqual(parts.day, 19)
        XCTAssertEqual(parts.hour, 0)
    }

    func testDateAndTime() throws {
        let parsed = try Agenda.date("2026-07-19T14:30")
        let parts = Calendar.current.dateComponents([.hour, .minute], from: parsed)
        XCTAssertEqual(parts.hour, 14)
        XCTAssertEqual(parts.minute, 30)
    }

    func testRejectsGarbage() {
        // "next tuesday" is valid now — see RelativeDateTests for the spoken grammar.
        XCTAssertThrowsError(try Agenda.date("sometime soon"))
    }
}

final class MeetingURLTests: XCTestCase {

    func testFindsZoomInNotes() {
        let url = Agenda.meetingURL(
            notes: "Dial in at https://acme.zoom.us/j/123456789?pwd=abc or call in",
            location: nil, url: nil
        )
        XCTAssertEqual(url, "https://acme.zoom.us/j/123456789?pwd=abc")
    }

    func testFindsMeetInLocation() {
        let url = Agenda.meetingURL(notes: nil, location: "https://meet.google.com/abc-defg-hij", url: nil)
        XCTAssertEqual(url, "https://meet.google.com/abc-defg-hij")
    }

    func testKnownProviderBeatsPlainURLField() {
        let url = Agenda.meetingURL(
            notes: "Join https://acme.zoom.us/j/999",
            location: nil,
            url: "https://example.com/agenda"
        )
        XCTAssertEqual(url, "https://acme.zoom.us/j/999")
    }

    func testFallsBackToURLField() {
        let url = Agenda.meetingURL(notes: "no link here", location: nil, url: "https://example.com/x")
        XCTAssertEqual(url, "https://example.com/x")
    }

    func testNilWhenNothingPresent() {
        XCTAssertNil(Agenda.meetingURL(notes: nil, location: nil, url: nil))
        XCTAssertNil(Agenda.meetingURL(notes: "just a note", location: "Room 4", url: nil))
    }
}

final class FreeSlotTests: XCTestCase {

    func testFitsAndMinutes() {
        let start = Date()
        let slot = FreeSlot(startsAt: start, endsAt: start.addingTimeInterval(5_400))
        XCTAssertEqual(slot.minutes, 90)
        XCTAssertTrue(slot.fits(3_600))
        XCTAssertFalse(slot.fits(7_200))
    }
}

final class WorkingHoursTests: XCTestCase {

    /// A Monday, so the standard weekday set applies.
    private func monday(hour: Int, minute: Int = 0) -> Date {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 7; parts.day = 20
        parts.hour = hour; parts.minute = minute
        return Calendar.current.date(from: parts)!
    }

    func testClipsToWorkingWindow() {
        let hours = WorkingHours(startHour: 9, endHour: 18)
        let overnight = FreeSlot(startsAt: monday(hour: 6), endsAt: monday(hour: 12))
        let clipped = hours.clip(overnight)

        XCTAssertEqual(clipped.count, 1)
        XCTAssertEqual(Calendar.current.component(.hour, from: clipped[0].startsAt), 9)
        XCTAssertEqual(Calendar.current.component(.hour, from: clipped[0].endsAt), 12)
    }

    func testDropsSlotEntirelyOutsideHours() {
        let hours = WorkingHours(startHour: 9, endHour: 18)
        let nightly = FreeSlot(startsAt: monday(hour: 1), endsAt: monday(hour: 5))
        XCTAssertTrue(hours.clip(nightly).isEmpty)
    }

    func testSkipsWeekends() {
        // 2026-07-18 is a Saturday.
        var parts = DateComponents()
        parts.year = 2026; parts.month = 7; parts.day = 18; parts.hour = 10
        let saturday = Calendar.current.date(from: parts)!
        let slot = FreeSlot(startsAt: saturday, endsAt: saturday.addingTimeInterval(7_200))
        XCTAssertTrue(WorkingHours.standard.clip(slot).isEmpty)
    }

    func testSplitsMultiDaySlotPerWorkingDay() {
        let hours = WorkingHours(startHour: 9, endHour: 18)
        // Monday 10am through Wednesday 10am spans three working days.
        let long = FreeSlot(startsAt: monday(hour: 10),
                            endsAt: monday(hour: 10).addingTimeInterval(2 * 86_400))
        XCTAssertEqual(hours.clip(long).count, 3)
    }
}

final class AgendaEventTests: XCTestCase {

    private func event(from start: Double, to end: Double) -> AgendaEvent {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        return AgendaEvent(
            id: UUID().uuidString, title: "T", calendar: "Work",
            startsAt: base.addingTimeInterval(start), endsAt: base.addingTimeInterval(end),
            isAllDay: false
        )
    }

    func testOverlapDetection() {
        XCTAssertTrue(event(from: 0, to: 3_600).overlaps(event(from: 1_800, to: 5_400)))
        XCTAssertFalse(event(from: 0, to: 3_600).overlaps(event(from: 3_600, to: 7_200)))
    }

    func testCoversInstant() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let meeting = event(from: 0, to: 3_600)
        XCTAssertTrue(meeting.covers(base.addingTimeInterval(600)))
        XCTAssertFalse(meeting.covers(base.addingTimeInterval(3_600)))  // half-open
    }
}

final class AgendaReminderTests: XCTestCase {

    func testOverdueOnlyWhenDatedAndOpen() {
        let past = Date().addingTimeInterval(-3_600)
        XCTAssertTrue(AgendaReminder(id: "1", title: "T", list: "L", dueAt: past).isOverdue)
        XCTAssertFalse(AgendaReminder(id: "2", title: "T", list: "L", dueAt: past, isCompleted: true).isOverdue)
        XCTAssertFalse(AgendaReminder(id: "3", title: "T", list: "L").isOverdue)
    }

    func testPriorityLabels() {
        XCTAssertEqual(AgendaReminder(id: "1", title: "T", list: "L", priority: 1).priorityLabel, "high")
        XCTAssertEqual(AgendaReminder(id: "2", title: "T", list: "L", priority: 5).priorityLabel, "medium")
        XCTAssertEqual(AgendaReminder(id: "3", title: "T", list: "L", priority: 9).priorityLabel, "low")
        XCTAssertNil(AgendaReminder(id: "4", title: "T", list: "L", priority: 0).priorityLabel)
    }
}
