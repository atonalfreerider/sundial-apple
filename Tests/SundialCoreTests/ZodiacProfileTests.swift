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
        XCTAssertEqual(Zodiac.Sign.scorpio, profile.resolvedSign())
        XCTAssertTrue(profile.isComplete)
    }

    func testModeOnlyUpdatesCannotEraseStoredBirthDateAndTime() {
        let stored = ZodiacProfile(
            enabled: true,
            birthDate: LocalDate(1984, 2, 29),
            birthTime: LocalTime(23, 7)
        )

        let result = ZodiacPreferences.preserveNatalData(ZodiacProfile(enabled: false), stored)

        XCTAssertFalse(result.enabled)
        XCTAssertEqual(stored.birthDate, result.birthDate)
        XCTAssertEqual(stored.birthTime, result.birthTime)
    }
}
