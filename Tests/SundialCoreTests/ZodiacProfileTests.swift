import Foundation
import XCTest
@testable import SundialCore

final class ZodiacProfileTests: XCTestCase {
    func testZodiacAndHoroscopeFeaturesAreOptIn() {
        XCTAssertFalse(ZodiacProfile().enabled)
        XCTAssertFalse(ZodiacProfile().isComplete)
    }

    func testBirthdayResolvesCommonSunSignAndCompleteProfile() {
        let profile = ZodiacProfile(
            enabled: true,
            birthDate: LocalDate(1990, 10, 23),
            birthTime: LocalTime(8, 45)
        )
        // 08:45 in Los Angeles is before the Sun enters Scorpio on this cusp date.
        XCTAssertEqual(Zodiac.Sign.libra, profile.resolvedSign())
        XCTAssertTrue(profile.isComplete)
    }

    func testModeOnlyUpdatesCannotEraseStoredBirthDateAndTime() {
        let stored = ZodiacProfile(
            enabled: true,
            birthDate: LocalDate(1984, 2, 29),
            birthTime: LocalTime(23, 7),
            birthZoneId: "America/Los_Angeles"
        )

        let result = ZodiacPreferences.preserveNatalData(ZodiacProfile(enabled: false), stored)

        XCTAssertFalse(result.enabled)
        XCTAssertEqual(stored.birthDate, result.birthDate)
        XCTAssertEqual(stored.birthTime, result.birthTime)
        XCTAssertEqual(stored.birthZoneId, result.birthZoneId)
    }

    func testBirthZoneSettlesTheSolarCusp() {
        let before = ZodiacProfile(enabled: true, birthDate: LocalDate(1990, 10, 23),
                                   birthTime: LocalTime(8, 45), birthZoneId: "America/Los_Angeles")
        let after = ZodiacProfile(enabled: true, birthDate: LocalDate(1990, 10, 23),
                                  birthTime: LocalTime(23, 0), birthZoneId: "America/Los_Angeles")
        XCTAssertEqual(before.natalSign, .libra)
        XCTAssertEqual(after.natalSign, .scorpio)
    }
}
