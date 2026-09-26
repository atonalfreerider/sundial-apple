import Foundation
import XCTest
@testable import SundialCore

final class TimeZoneDialTests: XCTestCase {
    private func instant(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    func testTimezoneWheelHas24EquallySpacedSpokesAndTwoCivilDays() {
        let spokes = TimeZoneDial.spokes(instant("2026-09-22T19:30:00Z"))
        XCTAssertEqual(24, spokes.count)
        XCTAssertEqual(2, Set(spokes.map { $0.localDate }).count)
        for (a, b) in zip(spokes, spokes.dropFirst()) {
            // Zones further east are later in the day, so they sit counter-clockwise (north view).
            let separation = ((a.angleDegrees - b.angleDegrees) + 360.0).truncatingRemainder(dividingBy: 360.0)
            XCTAssertEqual(15.0, separation, accuracy: 1e-9)
        }
    }

    func testZoneAtLocalNoonFacesTheSunAndMidnightFacesAway() {
        let instant = instant("2026-09-22T19:00:00Z")
        let spokes = TimeZoneDial.spokes(instant)
        func normalized(_ value: Double) -> Double {
            (value.truncatingRemainder(dividingBy: 360.0) + 360.0).truncatingRemainder(dividingBy: 360.0)
        }
        func single(_ spokes: [TimeZoneDial.Spoke], _ offset: Int) -> TimeZoneDial.Spoke {
            let matches = spokes.filter { $0.offsetHours == offset }
            XCTAssertEqual(matches.count, 1)
            return matches[0]
        }
        XCTAssertEqual(270.0, normalized(single(spokes, -7).angleDegrees), accuracy: 1e-9)
        XCTAssertEqual(90.0, normalized(single(spokes, 5).angleDegrees), accuracy: 1e-9)
        // 06:00 is on the right and 18:00 on the left, matching the Unity hour ring.
        XCTAssertEqual(0.0, normalized(single(spokes, 11).angleDegrees), accuracy: 1e-9)
        XCTAssertEqual(180.0, normalized(single(spokes, -1).angleDegrees), accuracy: 1e-9)
        let south = TimeZoneDial.spokes(instant, north: false)
        XCTAssertEqual(180.0, normalized(single(south, 11).angleDegrees), accuracy: 1e-9)
    }

    func testLosAngelesLocationArrowFollowsDaylightSavingAndCommonName() {
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertEqual(-420, TimeZoneDial.localOffsetMinutes(instant("2026-09-22T19:30:00Z"), zone))
        XCTAssertEqual(-480, TimeZoneDial.localOffsetMinutes(instant("2026-01-22T20:30:00Z"), zone))
        XCTAssertEqual("Pacific Time", TimeZoneDial.localName(zone, instant("2026-09-22T19:30:00Z")))
    }

    func testDateLineSitsAtTheLocalTimeOfUtcPlus12() {
        XCTAssertEqual(7.5, TimeZoneDial.datelineHours(instant("2026-09-22T19:30:00Z")), accuracy: 1e-9)
        XCTAssertEqual(0.0, TimeZoneDial.datelineHours(instant("2026-09-22T12:00:00Z")), accuracy: 1e-9)
    }

    func testTouchSelectionResolvesToClosestCommonTimezoneSpoke() {
        let spokes = TimeZoneDial.spokes(instant("2026-09-22T19:30:00Z"))
        let eastern = spokes.first { $0.offsetHours == -5 }!
        XCTAssertEqual(eastern, TimeZoneDial.nearestSpoke(spokes, eastern.angleDegrees + 3.0))
        XCTAssertTrue(eastern.label.contains("Eastern"))
    }
}
