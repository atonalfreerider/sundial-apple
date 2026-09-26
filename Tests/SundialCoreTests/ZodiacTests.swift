import Foundation
import XCTest
@testable import SundialCore

final class ZodiacTests: XCTestCase {
    func testCommonTropicalZodiacBoundariesAreCurrentAndLeapSafe() {
        XCTAssertEqual(Zodiac.Sign.capricorn, Zodiac.signFor(LocalDate(2024, 1, 19)))
        XCTAssertEqual(Zodiac.Sign.aquarius, Zodiac.signFor(LocalDate(2024, 1, 20)))
        XCTAssertEqual(Zodiac.Sign.aquarius, Zodiac.signFor(LocalDate(2024, 2, 18)))
        XCTAssertEqual(Zodiac.Sign.pisces, Zodiac.signFor(LocalDate(2024, 2, 19)))
        XCTAssertEqual(Zodiac.Sign.pisces, Zodiac.signFor(LocalDate(2024, 2, 29)))
        XCTAssertEqual(Zodiac.Sign.aries, Zodiac.signFor(LocalDate(2024, 3, 21)))
        XCTAssertEqual(Zodiac.Sign.virgo, Zodiac.signFor(LocalDate(2026, 9, 22)))
        XCTAssertEqual(Zodiac.Sign.libra, Zodiac.signFor(LocalDate(2026, 9, 23)))
        XCTAssertEqual(Zodiac.Sign.capricorn, Zodiac.signFor(LocalDate(2026, 12, 31)))
        for sign in Zodiac.Sign.allCases {
            let boundary = LocalDate(2026, sign.startMonth, sign.startDay)
            XCTAssertEqual(sign, Zodiac.signFor(boundary), "\(sign.displayName) start")
            let previous = Zodiac.Sign.allCases[(sign.ordinal + 11) % 12]
            XCTAssertEqual(previous, Zodiac.signFor(boundary.minusDays(1)), "day before \(sign.displayName)")
        }
    }

    func testLongitudeBoundariesMapToCanonicalSigns() {
        XCTAssertEqual(Zodiac.Sign.aries, Zodiac.signForLongitude(0.0))
        XCTAssertEqual(Zodiac.Sign.aries, Zodiac.signForLongitude(29.999))
        XCTAssertEqual(Zodiac.Sign.taurus, Zodiac.signForLongitude(30.0))
        XCTAssertEqual(Zodiac.Sign.pisces, Zodiac.signForLongitude(359.999))
        XCTAssertEqual(Zodiac.Sign.pisces, Zodiac.signForLongitude(-0.001))
    }

    func testGeocentricPlacementsAreFiniteAndExcludeEarth() {
        let placements = Zodiac.placements(ISO8601DateFormatter().date(from: "2026-09-22T12:00:00Z")!)
        XCTAssertEqual(["SUN", "MOON", "MERCURY", "VENUS", "MARS"], placements.map { $0.label })
        XCTAssertTrue(placements.allSatisfy { (0.0..<360.0).contains($0.longitudeDegrees) })
    }

    func testSeasonsReverseBetweenHemispheres() {
        let date = LocalDate(2026, 7, 15)
        XCTAssertEqual(Zodiac.Season.summer, Zodiac.seasonFor(date, true))
        XCTAssertEqual(Zodiac.Season.winter, Zodiac.seasonFor(date, false))
    }
}
