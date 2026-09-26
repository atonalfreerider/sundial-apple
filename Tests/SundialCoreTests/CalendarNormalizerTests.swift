import Foundation
import XCTest
@testable import SundialCore

final class CalendarNormalizerTests: XCTestCase {
    func testAllDayEventStaysOnItsUtcDateWestOfGreenwich() {
        let raw = allDay("2024-03-10T00:00:00Z", "2024-03-11T00:00:00Z")
        let event = CalendarNormalizer.normalize(raw, TimeZone(identifier: "America/Los_Angeles")!)
        XCTAssertEqual(LocalDate(2024, 3, 10), event.allDayStart)
        XCTAssertEqual(LocalDate(2024, 3, 11), event.allDayEndExclusive)
        XCTAssertEqual(LocalDate(2024, 3, 10), event.start.date)
    }

    func testAllDayEventStaysOnItsUtcDateEastOfGreenwich() {
        let raw = allDay("2024-03-10T00:00:00Z", "2024-03-11T00:00:00Z")
        let event = CalendarNormalizer.normalize(raw, TimeZone(identifier: "Asia/Kathmandu")!)
        XCTAssertEqual(LocalDate(2024, 3, 10), event.start.date)
    }

    func testTimedEventUsesDstTransitionRulesRatherThanAFixedOffset() {
        let raw = timed("2024-03-10T09:30:00Z", "2024-03-10T10:30:00Z")
        let event = CalendarNormalizer.normalize(raw, TimeZone(identifier: "America/Los_Angeles")!)
        XCTAssertEqual(1, event.start.hour)
        XCTAssertEqual(3, event.endExclusive.hour)
        XCTAssertEqual(60, Int64(event.endExclusive.instant.timeIntervalSince(event.start.instant)) / 60)
    }

    func testNonHourTimezoneOffsetsAreRetained() {
        let event = CalendarNormalizer.normalize(
            timed("2024-04-01T00:00:00Z", "2024-04-01T01:00:00Z"),
            TimeZone(identifier: "Asia/Kathmandu")!
        )
        XCTAssertEqual(5, event.start.hour)
        XCTAssertEqual(45, event.start.minute)
    }

    func testLeapDayAllDaySpanUsesExclusiveEnd() {
        let event = CalendarNormalizer.normalize(
            allDay("2024-02-28T00:00:00Z", "2024-03-01T00:00:00Z"),
            TimeZone(identifier: "UTC")!
        )
        XCTAssertEqual(2, Int64(event.endExclusive.instant.timeIntervalSince(event.start.instant)) / 86_400)
        XCTAssertTrue(event.isYearRingEvent)
    }

    func testShortTimedEventRemainsADayRingEvent() {
        let event = CalendarNormalizer.normalize(
            timed("2040-01-01T20:00:00Z", "2040-01-01T20:30:00Z"),
            TimeZone(identifier: "UTC")!
        )
        XCTAssertFalse(event.isYearRingEvent)
        XCTAssertEqual(instant("2040-01-01T20:00:00Z"), event.start.instant)
    }

    private func instant(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }
    private func allDay(_ start: String, _ end: String) -> RawCalendarInstance { raw(start, end, true) }
    private func timed(_ start: String, _ end: String) -> RawCalendarInstance { raw(start, end, false) }
    private func raw(_ start: String, _ end: String, _ allDay: Bool) -> RawCalendarInstance {
        RawCalendarInstance(
            1, // eventId
            2, // calendarId
            "Test", // title
            Int64(instant(start).timeIntervalSince1970 * 1_000), // beginMillis
            Int64(instant(end).timeIntervalSince1970 * 1_000), // endMillis
            allDay,
            allDay ? "UTC" : "America/Los_Angeles", // eventTimeZone
            0xFFCC_CC00 // color
        )
    }
}
