import Foundation
import XCTest
@testable import SundialCore

final class ReadingReporterTests: XCTestCase {
    func testFormFieldNamesMapReportFieldsOntoAGoogleForm() {
        XCTAssertEqual(
            ["reason": "entry.11", "reading": "entry.22", "version": "entry.44"],
            ReadingReporter.fieldNames(spec: " reason=entry.11, reading = entry.22 ,date=,version=entry.44,junk")
        )
        XCTAssertEqual([:], ReadingReporter.fieldNames(spec: ""))
    }
}
