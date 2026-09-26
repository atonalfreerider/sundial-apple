import Foundation
import XCTest
@testable import SundialCore

final class SeasonBandsTests: XCTestCase {
    private let starts = SeasonBands.starts(2026)
    private func fraction(_ dayOfYear: Int) -> Double { Double(dayOfYear - 1) / 365.0 }

    func testMidSeasonDatesAreASingleSeason() {
        XCTAssertEqual(SeasonBands.Mix(.winter, .winter, 0.0), SeasonBands.mixAt(fraction(20), starts, 365))
        XCTAssertEqual(Zodiac.Season.summer, SeasonBands.mixAt(fraction(200), starts, 365).to)
        XCTAssertEqual(0.0, SeasonBands.mixAt(fraction(200), starts, 365).amount, accuracy: 0.0)
    }

    func testSeasonsFadeIntoEachOtherAcrossEachSolsticeAndEquinox() {
        let equinox = LocalDate(2026, 3, 21).dayOfYear
        let before = SeasonBands.mixAt(fraction(equinox - 6), starts, 365)
        let at = SeasonBands.mixAt(fraction(equinox), starts, 365)
        let after = SeasonBands.mixAt(fraction(equinox + 6), starts, 365)
        for mix in [before, at, after] {
            XCTAssertEqual(Zodiac.Season.winter, mix.from)
            XCTAssertEqual(Zodiac.Season.spring, mix.to)
        }
        XCTAssertTrue(before.amount < at.amount && at.amount < after.amount)
        XCTAssertEqual(0.5, at.amount, accuracy: 0.03)
    }

    func testWinterBlendsIntoItselfAcrossNewYearWithoutASeam() {
        XCTAssertEqual(Zodiac.Season.winter, SeasonBands.mixAt(0.0, starts, 365).to)
        XCTAssertEqual(Zodiac.Season.winter, SeasonBands.mixAt(0.9999, starts, 365).to)
    }
}
