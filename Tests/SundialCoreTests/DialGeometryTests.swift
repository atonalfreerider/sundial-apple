import Foundation
import XCTest
@testable import SundialCore

final class DialGeometryTests: XCTestCase {
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!

    /// ZonedDateTime.parse of an ISO instant with its zone, e.g. 2026-09-22T12:00:00-07:00[America/Los_Angeles].
    private func zoned(_ iso: String, _ zone: TimeZone) -> ZonedDateTime {
        ZonedDateTime(ISO8601DateFormatter().date(from: iso)!, zone)
    }

    func testSeptemberCivilDateMapsToSeptemberSectorRatherThanJanuary() {
        let date = zoned("2026-09-22T12:00:00-07:00", losAngeles)
        let fraction = Astronomy.civilYearFraction(date)
        XCTAssertTrue((0.72...0.74).contains(fraction))
        let angle = DialGeometry.annualAngle(fraction, true)
        XCTAssertEqual(fraction, DialGeometry.yearFractionFromAngle(angle, true), accuracy: 1e-12)
    }

    func testAnnualDialRoundTripsInBothHemispheres() {
        for north in [true, false] {
            for fraction in [0.0, 0.1, 0.5, 0.75, 0.999] {
                XCTAssertEqual(fraction, DialGeometry.yearFractionFromAngle(
                    DialGeometry.annualAngle(fraction, north), north), accuracy: 1e-12)
            }
        }
    }

    func testSolsticesAndEquinoxesSitOnUnitysSeasonCross() {
        func angleOf(_ iso: String) -> Double {
            let zoned = zoned(iso, losAngeles)
            return Astronomy.normalizeDegrees(DialGeometry.annualAngle(Astronomy.civilYearFraction(zoned), true))
        }
        // Canvas angles: 90 is straight below the Sun, 270 above, 180 left, 0 right.
        XCTAssertEqual(90.0, angleOf("2026-12-21T12:00:00-08:00"), accuracy: 1.5)
        XCTAssertEqual(270.0, angleOf("2026-06-21T12:00:00-07:00"), accuracy: 1.5)
        XCTAssertEqual(180.0, angleOf("2026-09-22T12:00:00-07:00"), accuracy: 1.5)
        XCTAssertEqual(0.0, Astronomy.normalizeSignedDegrees(angleOf("2026-03-20T12:00:00-07:00")), accuracy: 3.0)
    }

    func testPlanetLongitudesShareTheAnnualDialFrame() {
        for iso in ["2026-01-01T00:00:00Z", "2026-04-15T00:00:00Z", "2026-09-22T12:00:00Z"] {
            let instant = ISO8601DateFormatter().date(from: iso)!
            let civil = DialGeometry.annualAngle(
                Astronomy.civilYearFraction(ZonedDateTime(instant, .offset(seconds: 0))), true)
            let physical = DialGeometry.eclipticAngle(
                Astronomy.heliocentricPosition(.earth, instant).longitudeDegrees, true)
            XCTAssertEqual(0.0, Astronomy.normalizeSignedDegrees(civil - physical), accuracy: 2.5)
        }
    }

    func testEarthViewKeepsNoonTowardTheSunAndTheMoonMovingCounterClockwise() {
        XCTAssertEqual(-90.0, DialGeometry.hourAngle(12.0, true), accuracy: 1e-9)
        XCTAssertEqual(90.0, DialGeometry.hourAngle(0.0, true), accuracy: 1e-9)
        XCTAssertEqual(0.0, DialGeometry.hourAngle(6.0, true), accuracy: 1e-9)
        XCTAssertEqual(180.0, DialGeometry.hourAngle(6.0, false), accuracy: 1e-9)
        for north in [true, false] {
            for minute in [0.0, 90.0, 721.5, 1_439.0] {
                XCTAssertEqual(minute, DialGeometry.minuteFromHourAngle(
                    DialGeometry.hourAngle(minute / 60.0, north), north), accuracy: 1e-9)
            }
            for phase in [0.0, 45.0, 180.0, 359.0] {
                XCTAssertEqual(phase, DialGeometry.phaseFromMoonAngle(DialGeometry.moonAngle(phase, north), north), accuracy: 1e-9)
            }
        }
        // First quarter Moon is 90° east of the Sun: left of the Earth in the north view.
        XCTAssertEqual(-180.0, DialGeometry.moonAngle(90.0, true), accuracy: 1e-9)
    }

    func testEventBandsFollowUnityCalendarChannelsRatherThanEventOrder() {
        let year0 = DialGeometry.yearEventBand(1000, 0)
        let year1 = DialGeometry.yearEventBand(1000, 1)
        XCTAssertEqual(46.64, year0.thickness, accuracy: 0.01)
        XCTAssertEqual(year0.thickness, year0.centerRadius - year1.centerRadius, accuracy: 0.01)

        let day0 = DialGeometry.dayEventBand(600, 0)
        XCTAssertEqual(69.96, day0.thickness, accuracy: 0.01)
        XCTAssertTrue(day0.centerRadius < 600)
    }

    func testEarthFlightFollowsUnityCameraZoomWhileEarthSystemExpandsIndependently() {
        let start = DialGeometry.earthFlightFrame(0)
        let middle = DialGeometry.earthFlightFrame(0.5)
        let end = DialGeometry.earthFlightFrame(1)

        XCTAssertEqual(1, start.cameraScale, accuracy: 0.0001)
        XCTAssertEqual(DialGeometry.earthCameraZoom, end.cameraScale, accuracy: 0.0001)
        XCTAssertEqual(DialGeometry.heliocentricEarthRadius,
                       start.earthSystemScale * DialGeometry.earthRadius, accuracy: 0.0001)
        XCTAssertEqual(1, end.earthSystemScale, accuracy: 0.0001)
        XCTAssertTrue((start.cameraScale...end.cameraScale).contains(middle.cameraScale))
        XCTAssertTrue((start.earthSystemScale...end.earthSystemScale).contains(middle.earthSystemScale))
        // Geometric zoom: halfway through the flight is halfway in perceived depth.
        XCTAssertEqual(sqrt(start.cameraScale * end.cameraScale), middle.cameraScale, accuracy: 0.0001)
        XCTAssertEqual(sqrt(start.earthSystemScale * end.earthSystemScale), middle.earthSystemScale, accuracy: 0.0001)
        XCTAssertEqual(1, start.skyScale, accuracy: 0.0001)
        XCTAssertTrue((1...end.cameraScale).contains(end.skyScale))
    }

    func testLocalWheelHugsTheGlobeWithUnitysInscribedRedTooth() {
        XCTAssertTrue(DialGeometry.localWheel > DialGeometry.earthRadius)
        XCTAssertTrue(DialGeometry.dateStripInner > DialGeometry.earthRadius)
        XCTAssertTrue(DialGeometry.dateStripOuter < DialGeometry.localWheel)
        XCTAssertTrue(DialGeometry.localWheelRedTooth < DialGeometry.localWheelBigTooth)
        let bigToothHalfBase = DialGeometry.localWheel * Math.toRadians(DialGeometry.localWheelToothHalfAngle)
        XCTAssertTrue(DialGeometry.localWheelRedHalfBase < bigToothHalfBase)
        XCTAssertTrue(DialGeometry.localWheel + DialGeometry.localWheelBigTooth < DialGeometry.hourDial)
    }

    func testEventBandsGrowToFitLegibleLabels() {
        let unity = DialGeometry.yearEventBand(500, 0)
        let legible = DialGeometry.yearEventBand(500, 0, minThickness: 40)
        XCTAssertEqual(40, legible.thickness, accuracy: 0.001)
        XCTAssertTrue(legible.thickness > unity.thickness)
        XCTAssertEqual(legible.thickness, legible.centerRadius - DialGeometry.yearEventBand(500, 1, minThickness: 40).centerRadius,
                       accuracy: 0.001)
    }
}
