import Foundation
import XCTest
@testable import SundialCore

final class BirthDateInputTests: XCTestCase {
    private let today = LocalDate(2026, 9, 22)

    func testDirectFourDigitBirthYearAcceptsGregorianLeapDay() throws {
        XCTAssertEqual(LocalDate(2000, 2, 29), try BirthDateInput.parse("02", "29", "2000", today: today))
    }

    func testCenturyYearThatIsNotDivisibleBy400IsRejected() {
        XCTAssertThrowsError(try BirthDateInput.parse("2", "29", "1900", today: today)) {
            XCTAssertTrue($0 is BirthInputError)
        }
    }

    func testShortAndFutureBirthYearsAreRejected() {
        XCTAssertThrowsError(try BirthDateInput.parse("9", "22", "86", today: today)) {
            XCTAssertTrue($0 is BirthInputError)
        }
        XCTAssertThrowsError(try BirthDateInput.parse("9", "23", "2026", today: today)) {
            XCTAssertTrue($0 is BirthInputError)
        }
    }
}
