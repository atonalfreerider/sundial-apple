import XCTest
@testable import SundialCore

final class HolidayIconsTests: XCTestCase {
    func testHolidayCalendarRecognition() {
        XCTAssertTrue(HolidayIcons.isHolidayCalendar("Holidays in United States"))
        XCTAssertTrue(HolidayIcons.isHolidayCalendar("x", "en.usa#holiday@group.v.calendar.google.com"))
        XCTAssertFalse(HolidayIcons.isHolidayCalendar("Work"))
    }

    func testSpecificIconsPrecedeGeneralRules() {
        XCTAssertEqual(HolidayIcons.icon(for: "New Year's Eve"), "🥂")
        XCTAssertEqual(HolidayIcons.icon(for: "New Year's Day"), "🎉")
        XCTAssertEqual(HolidayIcons.icon(for: "Christmas Eve"), "🌟")
        XCTAssertEqual(HolidayIcons.icon(for: "Christmas Day"), "🎄")
        XCTAssertEqual(HolidayIcons.icon(for: "Day after Thanksgiving"), "🛍️")
        XCTAssertEqual(HolidayIcons.icon(for: "Thanksgiving Day"), "🦃")
        XCTAssertEqual(HolidayIcons.icon(for: "Independence Day"), "🎆")
    }
}
