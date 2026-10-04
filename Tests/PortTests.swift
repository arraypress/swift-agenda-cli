//
//  PortTests.swift
//  AgendaCLITests
//
//  Created by David Sherlock on 2026.
//
//  What the move onto CLIKit has to keep true.
//
//  Nothing here touches a calendar. These assert the contract — the options parse, the
//  payloads render, the envelope splits plan from apply — because the alternative is testing
//  against whatever the machine happens to have in it, which passes or fails by accident.
//

import AgendaKit
import ArgumentParser
import CLIKit
import Foundation
import XCTest
@testable import agenda

final class OptionTests: XCTestCase {

    func testEveryVerbAcceptsTheFamilyFormatFlags() throws {
        // The point of the port: `--markdown` and `--fields` did not exist before.
        for arguments in [["--json"], ["--text"], ["--csv"], ["--markdown"], ["--ndjson"],
                          ["--fields", "title"], ["--quiet"]] {
            XCTAssertNoThrow(try CalendarsCommand.parse(arguments), "calendars \(arguments)")
        }
    }

    func testTheTimezoneOptionSurvivedTheMove() throws {
        // It is agenda's alone, so it did not come across in CommonOptions and had to be
        // carried deliberately.
        XCTAssertNoThrow(try ZoneOptions.parse(["--timezone", "Asia/Tokyo"]))
        XCTAssertThrowsError(try ZoneOptions.parse(["--timezone", "Mars/Olympus"]).apply())
    }

    func testAnUnknownZoneNamesTheFixture() {
        do {
            try ZoneOptions.parse(["--timezone", "Nowhere"]).apply()
            XCTFail("an unknown zone was accepted")
        } catch {
            XCTAssertTrue("\(error)".contains("IANA"), "the message should say what a zone looks like")
        }
    }

    func testDryRunReachedTheVerbsThatChangeSomething() throws {
        XCTAssertTrue(try AddCommand.parse(["x", "--dry-run"]).write.dryRun)
        XCTAssertTrue(try DeleteCommand.parse(["id", "--dry-run"]).write.dryRun)
        XCTAssertTrue(try MoveCommand.parse(["id", "--dry-run"]).write.dryRun)
        XCTAssertTrue(try EditCommand.parse(["id", "--dry-run"]).write.dryRun)
    }

    func testDoneHasNoDryRunBecauseUndoReversesIt() {
        // Deliberate, not an oversight: `--undo` puts it back exactly.
        XCTAssertThrowsError(try DoneCommand.parse(["id", "--dry-run"]))
    }

    func testReceiptsCanBeAskedForOnTheVerbsThatWrite() throws {
        XCTAssertEqual(try DeleteCommand.parse(["id", "--receipt", "/tmp/x.json"]).write.receipt,
                       "/tmp/x.json")
    }
}

final class PayloadRenderingTests: XCTestCase {

    func testACalendarIsATableAndAnEventIsNot() {
        // TableRenderable changes only the TEXT rendering, so the choice is about what a
        // person should see: a calendar is three short fields, an event carries its location,
        // its attendees and its recurrence and does not fit in columns.
        XCTAssertEqual(CalendarPayload.tableColumns.count, 4)
        XCTAssertEqual(SlotPayload.tableColumns.count, 3)
        XCTAssertFalse((EventPayload.self as Any) is any TableRenderable.Type)
        XCTAssertFalse((ReminderPayload.self as Any) is any TableRenderable.Type)
    }

    func testTheIdColumnIsNeverShortened() {
        // Every write verb takes an id back, so a truncated one is unusable.
        XCTAssertFalse(CalendarPayload.flexibleColumns.contains(
            CalendarPayload.tableColumns.firstIndex(of: "id")!))
    }
}

final class HiddenCalendarTests: XCTestCase {

    func testItIsAdvisoryAndNeverThrows() {
        // The whole point is a courtesy note on an empty answer. If Calendar.app cannot be
        // asked — no Automation permission, say — it must stay quiet rather than fail a read.
        XCTAssertNoThrow(HiddenCalendars.names())
        XCTAssertNoThrow(HiddenCalendars.note())
    }

    func testANoteIsOnlyProducedWhenSomethingIsActuallyHidden() {
        // On a machine with nothing hidden this is nil, and the tool says nothing extra.
        if HiddenCalendars.names().isEmpty {
            XCTAssertNil(HiddenCalendars.note())
        } else {
            let note = HiddenCalendars.note()
            XCTAssertNotNil(note)
            XCTAssertTrue(note?.contains("EventKit") ?? false)
        }
    }
}

final class VersionTests: XCTestCase {

    func testTheEmbeddedInfoPlistCarriesTheSameVersion() throws {
        // The plist is linked into the binary for TCC, and it sat at 1.0.0 through
        // three releases because nothing compared it with --version.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/agenda/Info.plist")
        let plist = try XCTUnwrap(NSDictionary(contentsOf: url))
        XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, AgendaCommand.configuration.version)
    }
}
