import Foundation
import XCTest
@testable import SundialCore

final class CalendarHitTestingTests: XCTestCase {
    func testAnnualEventHitTargetIncludesSmallTouchPaddingWithoutSelectingDistantDates() {
        XCTAssertTrue(CalendarHitTesting.containsYearFraction(0.250, 0.248, 0.003, 0.002))
        XCTAssertTrue(CalendarHitTesting.containsYearFraction(0.247, 0.248, 0.003, 0.002))
        XCTAssertFalse(CalendarHitTesting.containsYearFraction(0.300, 0.248, 0.003, 0.002))
    }

    func testAnnualHitTestingHandlesNewYearWraparoundPadding() {
        XCTAssertTrue(CalendarHitTesting.containsYearFraction(0.999, 0.0, 0.002, 0.003))
        XCTAssertTrue(CalendarHitTesting.containsYearFraction(0.003, 0.0, 0.002, 0.003))
    }

    func testDailyHitTestingAcceptsTheEventChordAndRejectsOtherHours() {
        XCTAssertTrue(CalendarHitTesting.containsMinute(9.0 * 60.0 + 15.0, 540.0, 570.0, 8.0))
        XCTAssertTrue(CalendarHitTesting.containsMinute(535.0, 540.0, 570.0, 8.0))
        XCTAssertFalse(CalendarHitTesting.containsMinute(600.0, 540.0, 570.0, 8.0))
    }
}
