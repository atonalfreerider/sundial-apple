import Foundation
import XCTest
@testable import SundialCore

final class GalacticGeometryTests: XCTestCase {
    private let zone = TimeZone(identifier: "America/Los_Angeles")!
    private func instant(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    func testContinuousYearRoundTripsAcrossCenturies() {
        for iso in ["1901-07-04T12:00:00Z", "2026-09-23T16:00:00Z", "2400-02-29T00:00:00Z"] {
            let instant = instant(iso)
            let year = GalacticGeometry.continuousYear(instant, zone)
            XCTAssertEqual(Double(instant.epochSecond),
                           Double(GalacticGeometry.instantAt(year, zone).epochSecond), accuracy: 1.0)
        }
        XCTAssertEqual(2026.0, GalacticGeometry.monthStart(2026, 1), accuracy: 1e-12)
        XCTAssertEqual(2027.0, GalacticGeometry.continuousYear(instant("2027-01-01T08:00:00Z"), zone), accuracy: 1e-9)
    }

    func testLaterYearsLieAheadOfTheSunInTheDirectionOfTravel() {
        // Travel points up the screen (canvas y grows downward).
        XCTAssertTrue(GalacticGeometry.travelY < 0)
        XCTAssertEqual(1, GalacticGeometry.travelX * GalacticGeometry.travelX +
            GalacticGeometry.travelY * GalacticGeometry.travelY, accuracy: 1e-6)
        XCTAssertEqual(0, GalacticGeometry.travelX * GalacticGeometry.sideX +
            GalacticGeometry.travelY * GalacticGeometry.sideY, accuracy: 1e-6)
    }

    func testOrbitsRunCounterClockwiseOnScreenAsSeenFromTheDirectionOfTravel() {
        func screen(_ longitude: Double) -> (Double, Double) {
            let (along, side) = GalacticGeometry.orbitOffset(longitude, 1)
            return (
                GalacticGeometry.travelX * along + GalacticGeometry.sideX * side,
                GalacticGeometry.travelY * along + GalacticGeometry.sideY * side
            )
        }
        let a = screen(0.0)
        let b = screen(90.0)
        // Counter-clockwise on a y-down canvas has a negative cross product.
        XCTAssertTrue(a.0 * b.1 - a.1 * b.0 < 0)
    }

    func testRibbonIsClampedOnlyToCivilCalendarYears() {
        XCTAssertEqual(GalacticGeometry.minYear, ZonedDateTime(GalacticGeometry.instantAt(-50.0, zone), zone).year)
        XCTAssertEqual(GalacticGeometry.maxYear, ZonedDateTime(GalacticGeometry.instantAt(20_000.0, zone), zone).year)
    }

    func testNaNLandsOnTheStartOfYearZeroAsOnAndroid() {
        // Kotlin: NaN passes coerceIn, NaN.toInt() and NaN.toLong() are 0.
        let zone = TimeZone(identifier: "America/New_York")!
        XCTAssertEqual(GalacticGeometry.instantAt(.nan, zone).timeIntervalSince1970, -62_167_201_438)
        XCTAssertEqual(Astronomy.instantAtYearFraction(2026, .nan, zone), LocalDate(2026, 1, 1).atStartOfDay(zone))
        XCTAssertEqual(Double.nan.toLong(), 0)
        XCTAssertEqual(Double.infinity.toLong(), .max)
        XCTAssertEqual((-1e300).toLong(), .min)
        XCTAssertEqual((-2.9).toLong(), -2)
        XCTAssertEqual(Double.nan.toInt(), 0)
        XCTAssertEqual(1e12.toInt(), 2_147_483_647)
        XCTAssertEqual((-1e12).toInt(), -2_147_483_648)
    }
}
