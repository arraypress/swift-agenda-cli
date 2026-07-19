//
//  LocationAlarmTests.swift
//  SwiftAgenda
//
//  Geofenced alarms, structured locations, and calendar metadata.
//
//  Created by David Sherlock on 7/19/26.
//

import EventKit
import XCTest
@testable import AgendaKit

final class LocationTests: XCTestCase {

    func testRoundTripsThroughEventKit() {
        let original = AgendaLocation(title: "Office", latitude: 51.5074, longitude: -0.1278, radius: 200)
        guard let result = AgendaLocation(original.ekLocation) else {
            return XCTFail("location did not survive the round trip")
        }
        XCTAssertEqual(result.title, "Office")
        XCTAssertEqual(result.latitude ?? 0, 51.5074, accuracy: 0.0001)
        XCTAssertEqual(result.longitude ?? 0, -0.1278, accuracy: 0.0001)
        XCTAssertEqual(result.radius, 200)
    }

    func testTitleOnlyLocationHasNoCoordinates() {
        let location = AgendaLocation(title: "Somewhere")
        XCTAssertFalse(location.hasCoordinates)
        // A half-specified location must not be geocoded to (0, 0) off West Africa.
        XCTAssertNil(AgendaLocation(location.ekLocation)?.latitude)
    }

    func testEmptyLocationIsNil() {
        XCTAssertNil(AgendaLocation(nil))
        XCTAssertNil(AgendaLocation(EKStructuredLocation(title: "")))
    }
}

final class ProximityAlarmTests: XCTestCase {

    private let office = AgendaLocation(title: "Office", latitude: 51.5074, longitude: -0.1278, radius: 150)

    func testArrivingAlarmRoundTrips() {
        let result = AgendaAlarm(AgendaAlarm.arriving(at: office).ekAlarm)
        XCTAssertEqual(result.proximity, .enter)
        XCTAssertTrue(result.isLocationBased)
        XCTAssertEqual(result.location?.title, "Office")
    }

    func testLeavingAlarmRoundTrips() {
        let result = AgendaAlarm(AgendaAlarm.leaving(office).ekAlarm)
        XCTAssertEqual(result.proximity, .leave)
        XCTAssertTrue(result.isLocationBased)
    }

    func testTimeAlarmIsNotLocationBased() {
        XCTAssertFalse(AgendaAlarm.before(900).isLocationBased)
        XCTAssertEqual(AgendaAlarm(AgendaAlarm.before(900).ekAlarm).proximity, .none)
    }

    func testLocationWithoutProximityIsNotGeofenced() {
        // Both halves are required — a location with no direction has nothing to fire on.
        let alarm = AgendaAlarm(location: office, proximity: .none)
        XCTAssertFalse(alarm.isLocationBased)
        XCTAssertEqual(AgendaAlarm(alarm.ekAlarm).proximity, .none)
    }

    func testSummaryNamesThePlace() {
        XCTAssertEqual(AgendaAlarm.arriving(at: office).summary, "on arriving at Office")
        XCTAssertEqual(AgendaAlarm.leaving(office).summary, "on leaving Office")
    }

    func testProximityRoundTrip() {
        for value in AlarmProximity.allCases {
            XCTAssertEqual(AlarmProximity(value.ekProximity), value)
        }
    }
}

final class CalendarKindTests: XCTestCase {

    func testSubscriptionMapsDistinctly() {
        XCTAssertEqual(CalendarKind(.subscription), .subscription)
        XCTAssertEqual(CalendarKind(.birthday), .birthday)
        XCTAssertEqual(CalendarKind(.calDAV), .calDAV)
        XCTAssertEqual(CalendarKind(.local), .local)
    }
}
