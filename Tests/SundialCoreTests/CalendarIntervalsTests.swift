import Foundation
import XCTest
@testable import SundialCore

final class CalendarIntervalsTests: XCTestCase {
    private let zone = TimeZone(identifier: "America/Los_Angeles")!

    func testEventCrossingMidnightIsClippedIntoBothCivilDays() throws {
        let event = occurrence("2024-05-02T06:30:00Z", "2024-05-02T08:30:00Z") // 23:30–01:30 PDT
        let first = try XCTUnwrap(CalendarIntervals.inDay(event, LocalDate(2024, 5, 1), zone))
        let second = try XCTUnwrap(CalendarIntervals.inDay(event, LocalDate(2024, 5, 2), zone))
        XCTAssertEqual(1410.0, first.startMinute, accuracy: 0.001)
        XCTAssertEqual(1440.0, first.endMinuteExclusive, accuracy: 0.001)
        XCTAssertEqual(0.0, second.startMinute, accuracy: 0.001)
        XCTAssertEqual(90.0, second.endMinuteExclusive, accuracy: 0.001)
    }

    func testEventOutsideDayIsExcluded() {
        let event = occurrence("2024-05-02T06:30:00Z", "2024-05-02T08:30:00Z")
        XCTAssertNil(CalendarIntervals.inDay(event, LocalDate(2024, 5, 3), zone))
    }

    func testYearClippingHonorsLeapYearDurationAndExclusiveEnd() throws {
        let event = occurrence("2023-12-31T08:00:00Z", "2025-01-02T08:00:00Z")
        let segment = try XCTUnwrap(CalendarIntervals.inYear(event, 2024, zone))
        XCTAssertEqual(0.0, segment.startFraction, accuracy: 1e-12)
        XCTAssertEqual(1.0, segment.sweepFraction, accuracy: 1e-12)
    }

    private func occurrence(_ start: String, _ end: String) -> CalendarOccurrence {
        let startZoned = ZonedDateTime(ISO8601DateFormatter().date(from: start)!, zone)
        let endZoned = ZonedDateTime(ISO8601DateFormatter().date(from: end)!, zone)
        return CalendarOccurrence(1, 2, "Test", startZoned, endZoned, nil, nil, 0xFFCC_CC00)
    }
}
