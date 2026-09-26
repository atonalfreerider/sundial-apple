import Foundation
import XCTest
@testable import SundialCore

final class BirthTimeInputTests: XCTestCase {
    func testTwelveHourEntryMapsMidnightNoonAndEvening() throws {
        XCTAssertEqual(LocalTime(0, 5), try BirthTimeInput.parse("12", "05", false))
        XCTAssertEqual(LocalTime(12, 0), try BirthTimeInput.parse("12", "00", true))
        XCTAssertEqual(LocalTime(19, 42), try BirthTimeInput.parse("7", "42", true))
        XCTAssertEqual(LocalTime(9, 7), try BirthTimeInput.parse("09", "7", false))
    }

    func testOutOfRangeEntriesAreRejected() {
        for (hour, minute, pm) in [("13", "00", false), ("0", "00", false), ("6", "60", true), ("six", "00", true)] {
            XCTAssertThrowsError(try BirthTimeInput.parse(hour, minute, pm)) {
                XCTAssertTrue($0 is BirthInputError)
            }
        }
    }
}
