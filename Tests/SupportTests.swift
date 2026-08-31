//
//  SupportTests.swift
//  AgendaKitTests
//
//  Created by David Sherlock on 2026.
//
//  The offset-label buckets pinned directly.
//

import XCTest
@testable import AgendaKit

final class SupportTests: XCTestCase {

    func testOffsetLabelBuckets() {
        XCTAssertEqual(Formatting.offsetLabel(minutes: 59), "59m")
        XCTAssertEqual(Formatting.offsetLabel(minutes: 60), "1h")
        XCTAssertEqual(Formatting.offsetLabel(minutes: 1439), "23h")
        XCTAssertEqual(Formatting.offsetLabel(minutes: 1440), "1d")
    }
}
