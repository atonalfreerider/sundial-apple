import Foundation
import XCTest
@testable import SundialCore

final class AstronomyTests: XCTestCase {
    private func instant(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }
    private let utc = TimeZone(identifier: "UTC")!

    func testUnixEpochConvertsToCanonicalJulianDate() {
        XCTAssertEqual(Astronomy.julianDate(Date(timeIntervalSince1970: 0)), 2_440_587.5, accuracy: 1e-9)
    }

    func testJ2000InstantAndSiderealAngleAreCorrect() {
        let j2000 = instant("2000-01-01T12:00:00Z")
        XCTAssertEqual(Astronomy.julianDate(j2000), Astronomy.julianDateJ2000, accuracy: 1e-9)
        XCTAssertEqual(Astronomy.greenwichMeanSiderealDegrees(j2000), 280.46061837, accuracy: 1e-7)
    }

    func testGregorianCenturyLeapRulesAreHonored() {
        XCTAssertEqual(Astronomy.daysInYear(1900), 365)
        XCTAssertEqual(Astronomy.daysInYear(2000), 366)
        XCTAssertEqual(Astronomy.daysInYear(2100), 365)
        XCTAssertEqual(Astronomy.daysInYear(2024), 366)
    }

    func testCivilYearFractionPlacesLeapDayAfter59CompleteDays() {
        let leapDay = ZonedDateTime(ZonedDateTime.instant(LocalDate(2024, 2, 29), LocalTime(0, 0), utc), utc)
        XCTAssertEqual(Astronomy.civilYearFraction(leapDay), 59.0 / 366.0, accuracy: 1e-12)
    }

    func testYearFractionRoundTripUsesRequestedYearAndZone() {
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        let target = ZonedDateTime(ZonedDateTime.instant(LocalDate(2024, 7, 2), LocalTime(12, 0), zone), zone)
        let fraction = Astronomy.civilYearFraction(target)
        let rebuilt = ZonedDateTime(Astronomy.instantAtYearFraction(2024, fraction, zone), zone)
        XCTAssertEqual(target.date, rebuilt.date)
        XCTAssertTrue(abs(target.hour - rebuilt.hour) <= 1)
    }

    func testJplApproximatePlanetVectorsTrackHorizonsAtJ2000() {
        let time = instant("2000-01-01T12:00:00Z")
        // Reference vectors are NASA/JPL Horizons heliocentric ecliptic AU values.
        let expected: [Astronomy.Body: [Double]] = [
            .mercury: [-0.130094, -0.447288, -0.024598],
            .venus: [-0.718302, -0.032654, 0.041014],
            .earth: [-0.177159, 0.967219, -0.000001],
            .mars: [1.390716, -0.013416, -0.034468],
        ]
        for (body, reference) in expected {
            let actual = Astronomy.heliocentricPosition(body, time)
            XCTAssertEqual(reference[0], actual.x, accuracy: 0.012, "\(body) x")
            XCTAssertEqual(reference[1], actual.y, accuracy: 0.012, "\(body) y")
            XCTAssertEqual(reference[2], actual.z, accuracy: 0.012, "\(body) z")
        }
    }

    func testLunarPhaseIsNearZeroAtAPublishedNewMoon() {
        let phase = Astronomy.moonPhaseDegrees(instant("2000-01-06T18:14:00Z"))
        let distanceFromNew = min(phase, 360.0 - phase)
        XCTAssertTrue(distanceFromNew < 2.0, "phase=\(phase)")
    }

    func testLunarPhaseComparesMoonAndSunInTheSameEquinoxFrame() {
        // New Moon of the 8 April 2024 total solar eclipse, 18:21 UTC.
        let phase = Astronomy.moonPhaseDegrees(instant("2024-04-08T18:21:00Z"))
        XCTAssertTrue(min(phase, 360.0 - phase) < 0.5, "phase=\(phase)")
    }

    func testLunarPhaseIsNearFullAtAPublishedFullMoon() {
        let phase = Astronomy.moonPhaseDegrees(instant("2024-03-25T07:00:00Z"))
        XCTAssertTrue(abs(phase - 180.0) < 3.0, "phase=\(phase)")
    }

    func testAnnualMappingNeverDependsOnCurrentSystemYear() {
        let old = ZonedDateTime(instant("1984-12-31T12:00:00Z"), utc)
        let modern = ZonedDateTime(instant("2024-12-31T12:00:00Z"), utc)
        XCTAssertTrue(Astronomy.civilYearFraction(old) > 0.998)
        XCTAssertTrue(Astronomy.civilYearFraction(modern) > 0.998)
        XCTAssertEqual(LocalDate(1984, 12, 31),
                       LocalDate.of(Astronomy.instantAtYearFraction(1984, Astronomy.civilYearFraction(old), utc), utc))
    }
}
