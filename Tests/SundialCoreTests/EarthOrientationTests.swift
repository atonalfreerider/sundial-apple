import Foundation
import XCTest
@testable import SundialCore

final class EarthOrientationTests: XCTestCase {
    private let tilt = sin(Math.toRadians(23.43928))

    func testNorthPoleLeansTowardTheSunInJuneAndAwayInDecember() {
        let june = EarthOrientation.projectedGeographicPole(true, 90.0)
        XCTAssertEqual(0.0, june.0, accuracy: 1e-12)
        XCTAssertEqual(tilt, june.1, accuracy: 1e-12)

        let december = EarthOrientation.projectedGeographicPole(true, 270.0)
        XCTAssertEqual(0.0, december.0, accuracy: 1e-12)
        XCTAssertEqual(-tilt, december.1, accuracy: 1e-12)
    }

    func testPoleLeansSidewaysAtTheEquinoxesAndMirrorsInTheSouthView() {
        let march = EarthOrientation.projectedGeographicPole(true, 0.0)
        XCTAssertEqual(-tilt, march.0, accuracy: 1e-12)
        XCTAssertEqual(0.0, march.1, accuracy: 1e-12)
        let september = EarthOrientation.projectedGeographicPole(true, 180.0)
        XCTAssertEqual(tilt, september.0, accuracy: 1e-12)

        let southJune = EarthOrientation.projectedGeographicPole(false, 90.0)
        XCTAssertEqual(-tilt, southJune.1, accuracy: 1e-12)
    }

    func testSunFacingLimbIsTheSubsolarPoint() {
        // June solstice: the Sun's declination equals the obliquity.
        let june = EarthOrientation.screenToEquatorial(0.0, 1.0, 0.0, 90.0, true)
        XCTAssertEqual(23.43928, Math.toDegrees(asin(june.z)), accuracy: 1e-9)
        // March equinox: the Sun sits on the equator at right ascension 0.
        let march = EarthOrientation.screenToEquatorial(0.0, 1.0, 0.0, 0.0, false)
        XCTAssertEqual(1.0, march.x, accuracy: 1e-12)
        XCTAssertEqual(0.0, march.z, accuracy: 1e-12)
        // The view axis is the ecliptic pole in both hemispheres.
        let north = EarthOrientation.screenToEquatorial(0.0, 0.0, 1.0, 45.0, true)
        XCTAssertEqual(90.0 - 23.43928, Math.toDegrees(asin(north.z)), accuracy: 1e-9)
        let south = EarthOrientation.screenToEquatorial(0.0, 0.0, 1.0, 45.0, false)
        XCTAssertEqual(-(90.0 - 23.43928), Math.toDegrees(asin(south.z)), accuracy: 1e-9)
    }
}
