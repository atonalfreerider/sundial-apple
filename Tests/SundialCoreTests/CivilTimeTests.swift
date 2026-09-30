import Foundation
import XCTest
@testable import SundialCore

/// CivilTime.swift against java.time: the expected values were computed with java.time
/// (JDK 21, jshell), and the Android reference data exercises the same code far more widely.
final class CivilTimeTests: XCTestCase {
    private func zone(_ id: String) -> TimeZone { TimeZone(identifier: id)! }
    private func instant(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    // MARK: LocalDate

    func testEpochDaysOfKnownDates() {
        // LocalDate.toEpochDay().
        XCTAssertEqual(LocalDate(1970, 1, 1).epochDay, 0)
        XCTAssertEqual(LocalDate(2000, 1, 1).epochDay, 10_957)
        XCTAssertEqual(LocalDate(1, 1, 1).epochDay, -719_162)
        XCTAssertEqual(LocalDate(9999, 12, 31).epochDay, 2_932_896)
        XCTAssertEqual(LocalDate(0, 2, 29).epochDay, -719_469)
        XCTAssertEqual(LocalDate(-1, 12, 31).epochDay, -719_529)
        XCTAssertEqual(LocalDate(epochDay: -1), LocalDate(1969, 12, 31))
        XCTAssertEqual(LocalDate(epochDay: 19_782), LocalDate(2024, 2, 29))
    }

    func testEpochDayRoundTripsDayByDay() {
        // Every day from 1 BC (year 0) to 2400, and each one follows the last.
        var previous = LocalDate(epochDay: LocalDate(0, 1, 1).epochDay - 1)
        XCTAssertEqual(previous, LocalDate(-1, 12, 31))
        var failures: [String] = []
        for day in LocalDate(0, 1, 1).epochDay...LocalDate(2400, 12, 31).epochDay {
            let date = LocalDate(epochDay: day)
            let follows: Bool
            if date.day == 1 {
                follows = date.month == 1
                    ? previous.year == date.year - 1 && previous.month == 12 && previous.day == 31
                    : previous.year == date.year && previous.month == date.month - 1 && previous.day == previous.lengthOfMonth
            } else {
                follows = previous.year == date.year && previous.month == date.month && previous.day == date.day - 1
            }
            if date.epochDay != day || !follows { failures.append("\(day): \(date) after \(previous)") }
            previous = date
        }
        XCTAssertEqual(failures.prefix(5), [])
    }

    func testEpochDayRoundTripsFarFromTheEpoch() {
        for day in stride(from: -3_652_059, through: 3_652_059, by: 997) {
            XCTAssertEqual(LocalDate(epochDay: day).epochDay, day)
        }
    }

    func testDayOfWeek() {
        // DayOfWeek.getValue(): Monday 1 … Sunday 7.
        XCTAssertEqual(LocalDate(1970, 1, 1).dayOfWeek, 4) // THURSDAY
        XCTAssertEqual(LocalDate(1969, 12, 28).dayOfWeek, 7) // SUNDAY
        XCTAssertEqual(LocalDate(1, 1, 1).dayOfWeek, 1) // MONDAY
        XCTAssertEqual(LocalDate(-1, 12, 31).dayOfWeek, 5) // FRIDAY
        XCTAssertEqual(LocalDate(1582, 10, 15).dayOfWeek, 5) // FRIDAY
        XCTAssertEqual(LocalDate(2026, 9, 26).dayOfWeek, 6) // SATURDAY
        XCTAssertEqual(LocalDate(2026, 9, 26).weekdayAbbreviation, "SAT")
        XCTAssertEqual(LocalDate(2026, 9, 26).monthAbbreviation, "SEP")
        for day in -800...800 {
            let date = LocalDate(epochDay: day)
            XCTAssertEqual(date.plusDays(1).dayOfWeek, date.dayOfWeek % 7 + 1)
        }
    }

    func testLeapYearsAndYearArithmetic() {
        XCTAssertTrue(LocalDate.isLeapYear(2000))
        XCTAssertFalse(LocalDate.isLeapYear(1900))
        XCTAssertTrue(LocalDate.isLeapYear(2024))
        XCTAssertTrue(LocalDate.isLeapYear(0))
        XCTAssertTrue(LocalDate.isLeapYear(-4))
        XCTAssertFalse(LocalDate.isLeapYear(-1))
        XCTAssertEqual(LocalDate(2024, 12, 31).dayOfYear, 366)
        XCTAssertEqual(LocalDate(2024, 3, 1).dayOfYear, 61)
        XCTAssertEqual(LocalDate.ofYearDay(2024, 60), LocalDate(2024, 2, 29))
        XCTAssertEqual(LocalDate(2024, 2, 29).plusYears(1), LocalDate(2025, 2, 28))
        XCTAssertEqual(LocalDate(2024, 2, 29).plusYears(4), LocalDate(2028, 2, 29))
        XCTAssertEqual(LocalDate(2024, 7, 4).withDayOfYear(1), LocalDate(2024, 1, 1))
    }

    func testIsoTextRoundTrips() {
        XCTAssertEqual(LocalDate(2024, 2, 29).description, "2024-02-29")
        XCTAssertEqual(LocalDate(76, 7, 4).description, "0076-07-04")
        XCTAssertEqual(LocalDate.parse("2024-02-29"), LocalDate(2024, 2, 29))
        XCTAssertNil(LocalDate.parse("2023-02-29"))
        XCTAssertNil(LocalDate.parse("2024-2-29"))
        // Years outside 0...9999 as java.time writes and reads them.
        XCTAssertEqual(LocalDate(-1, 7, 4).description, "-0001-07-04")
        XCTAssertEqual(LocalDate(-1500, 1, 1).description, "-1500-01-01")
        XCTAssertEqual(LocalDate(0, 1, 1).description, "0000-01-01")
        XCTAssertEqual(LocalDate(10_000, 1, 1).description, "+10000-01-01")
        XCTAssertEqual(LocalDate.parse("-0001-07-04"), LocalDate(-1, 7, 4))
        XCTAssertEqual(LocalDate.parse("+10000-01-01"), LocalDate(10_000, 1, 1))
        XCTAssertEqual(LocalDate.parse("0000-01-01"), LocalDate(0, 1, 1))
        XCTAssertNil(LocalDate.parse("+2024-02-29"))
        XCTAssertNil(LocalDate.parse("-0000-01-01"))
        XCTAssertNil(LocalDate.parse("10000-01-01"))
        XCTAssertNil(LocalDate.parse("2024-+2-29"))
        for date in [LocalDate(-1, 7, 4), LocalDate(-44, 3, 15), LocalDate(0, 2, 29), LocalDate(12_345, 6, 7)] {
            XCTAssertEqual(LocalDate.parse(date.description), date)
        }
        XCTAssertEqual(LocalTime(7, 5).description, "07:05")
        XCTAssertEqual(LocalTime(23, 59, 30).description, "23:59:30")
        XCTAssertEqual(LocalTime.parse("07:05"), LocalTime(7, 5))
        XCTAssertEqual(LocalTime.parse("23:59:30"), LocalTime(23, 59, 30))
        XCTAssertNil(LocalTime.parse("24:00"))
    }

    // MARK: ZonedDateTime

    func testZonedFields() {
        let kolkata = ZonedDateTime(instant("2024-12-31T18:45:30Z"), zone("Asia/Kolkata"))
        XCTAssertEqual(kolkata.offsetSeconds, 19_800)
        XCTAssertEqual(kolkata.date, LocalDate(2025, 1, 1))
        XCTAssertEqual([kolkata.hour, kolkata.minute, kolkata.second], [0, 15, 30])
        let beforeEpoch = ZonedDateTime(Date(timeIntervalSince1970: -0.5), zone("UTC"))
        XCTAssertEqual(beforeEpoch.date, LocalDate(1969, 12, 31))
        XCTAssertEqual([beforeEpoch.hour, beforeEpoch.minute, beforeEpoch.second], [23, 59, 59])
        XCTAssertEqual(beforeEpoch.nano, 500_000_000)
        XCTAssertEqual(kolkata.withZone(zone("America/Los_Angeles")).date, LocalDate(2024, 12, 31))
    }

    func testLocalTimeInAGapMovesLaterByTheGap() {
        // LocalDateTime.atZone: a time that does not exist is shifted by the length of the gap.
        XCTAssertEqual(ZonedDateTime.instant(LocalDate(2024, 3, 10), LocalTime(2, 30), zone("America/Los_Angeles")),
                       instant("2024-03-10T10:30:00Z"))
        XCTAssertEqual(ZonedDateTime.instant(LocalDate(2024, 3, 31), LocalTime(1, 30), zone("Europe/London")),
                       instant("2024-03-31T01:30:00Z"))
        // Lord Howe springs forward by half an hour.
        XCTAssertEqual(ZonedDateTime.instant(LocalDate(2024, 10, 6), LocalTime(2, 15), zone("Australia/Lord_Howe")),
                       instant("2024-10-05T15:45:00Z"))
        XCTAssertEqual(ZonedDateTime.instant(LocalDate(2024, 9, 29), LocalTime(3, 0), zone("Pacific/Chatham")),
                       instant("2024-09-28T14:15:00Z"))
    }

    func testLocalTimeInAnOverlapTakesTheEarlierOffset() {
        XCTAssertEqual(ZonedDateTime.instant(LocalDate(2024, 11, 3), LocalTime(1, 30), zone("America/Los_Angeles")),
                       instant("2024-11-03T08:30:00Z"))
        XCTAssertEqual(ZonedDateTime.instant(LocalDate(2024, 10, 27), LocalTime(1, 30), zone("Europe/London")),
                       instant("2024-10-27T00:30:00Z"))
        XCTAssertEqual(ZonedDateTime.instant(LocalDate(2024, 4, 7), LocalTime(1, 45), zone("Australia/Lord_Howe")),
                       instant("2024-04-06T14:45:00Z"))
        XCTAssertEqual(ZonedDateTime.instant(LocalDate(2024, 4, 7), LocalTime(3, 15), zone("Pacific/Chatham")),
                       instant("2024-04-06T13:30:00Z"))
    }

    func testStartOfDayWhenMidnightIsSkippedOrRepeated() {
        let santiago = zone("America/Santiago")
        // Clocks jump from 00:00 to 01:00 on 8 September 2024: the day starts at 01:00 (-03).
        XCTAssertEqual(LocalDate(2024, 9, 8).atStartOfDay(santiago), instant("2024-09-08T04:00:00Z"))
        // On 6/7 April 2024 midnight falls back to 23:00 of the 6th.
        XCTAssertEqual(LocalDate(2024, 4, 6).atStartOfDay(santiago), instant("2024-04-06T03:00:00Z"))
        XCTAssertEqual(LocalDate(2024, 4, 7).atStartOfDay(santiago), instant("2024-04-07T04:00:00Z"))
        XCTAssertEqual(LocalDate(2024, 4, 8).atStartOfDay(santiago), instant("2024-04-08T04:00:00Z"))
    }

    func testEarlyDatesUseLocalMeanTime() {
        // Before standard time, tzdb gives Los Angeles its local mean time, -7:52:58.
        let start = LocalDate(1, 1, 1).atStartOfDay(zone("America/Los_Angeles"))
        XCTAssertEqual(start.timeIntervalSince1970, -62_135_596_800 + 28_378)
    }

    func testFixedOffsets() {
        XCTAssertEqual(TimeZone.offset(seconds: 45_900).secondsFromGMT(for: Date()), 45_900)
        let local = ZonedDateTime(instant("2024-06-01T12:30:30Z"), .offset(seconds: -18 * 3_600))
        XCTAssertEqual(local.date, LocalDate(2024, 5, 31))
        XCTAssertEqual([local.hour, local.minute, local.second], [18, 30, 30])
    }

    func testCivilFormat() {
        let moment = instant("2026-09-26T19:05:00Z")
        XCTAssertEqual(CivilFormat.format(moment, "EEEE, MMMM d, yyyy, h:mm a", zone("America/Los_Angeles")),
                       "Saturday, September 26, 2026, 12:05 PM")
        XCTAssertEqual(CivilFormat.format(LocalDate(2024, 2, 29), "MMM d"), "Feb 29")
    }

    func testCivilFormatIsProlepticGregorian() {
        // java.time's ISO chronology never turns Julian, as Foundation's Gregorian calendar does
        // before 1582-10-15.
        XCTAssertEqual(CivilFormat.format(LocalDate(1000, 6, 15), "EEEE, MMMM d, yyyy"), "Sunday, June 15, 1000")
        XCTAssertEqual(CivilFormat.format(LocalDate(1500, 3, 1), "MMM d  yyyy"), "Mar 1  1500")
        XCTAssertEqual(CivilFormat.format(LocalDate(1582, 10, 10), "MMM d  yyyy"), "Oct 10  1582")
        XCTAssertEqual(CivilFormat.format(LocalDate(1, 1, 1), "MMMM d, yyyy"), "January 1, 0001")
        let noon = LocalDate(1000, 1, 1).atStartOfDay(CivilFormat.utc).addingTimeInterval(12 * 3_600)
        XCTAssertEqual(CivilFormat.format(noon, "EEEE, MMMM d, yyyy, h:mm a", CivilFormat.utc),
                       "Wednesday, January 1, 1000, 12:00 PM")
        XCTAssertEqual(CivilFormat.format(noon, "dd/MM/yy   HH : mm : ss", CivilFormat.utc), "01/01/00   12 : 00 : 00")
        // Local 1 January of year 1 east of UTC is still before 0001-01-01T00:00Z.
        let tokyo = zone("Asia/Tokyo")
        XCTAssertEqual(CivilFormat.format(LocalDate(1, 1, 1).atStartOfDay(tokyo), "MMM d  yyyy", tokyo), "Jan 1  0001")
    }

    func testFiveDigitYearsAreSignedAsJavaTimeSignsThem() {
        // 'yyyy' is SignStyle.EXCEEDS_PAD in java.time: a year past 9999 gets a '+'.
        XCTAssertEqual(CivilFormat.format(LocalDate(10_000, 1, 1), "MMM d  yyyy"), "Jan 1  +10000")
        XCTAssertEqual(CivilFormat.format(LocalDate(10_000, 1, 1), "EEEE, MMMM d, yyyy, h:mm a"),
                       "Saturday, January 1, +10000, 12:00 AM")
        XCTAssertEqual(CivilFormat.format(LocalDate(9_999, 12, 31), "MMM d  yyyy"), "Dec 31  9999")
        // Quoted letters are text, and a shorter field is never signed.
        XCTAssertEqual(CivilFormat.format(LocalDate(12_345, 6, 7), "'yyyy' yyy"), "yyyy 12345")
        XCTAssertEqual(CivilFormat.format(LocalDate(12_345, 6, 7), "yyyyy"), "12345")
        XCTAssertEqual(CivilFormat.signedYearPattern("'it''s' yyyy", 10_000), "'it''s' +yyyy")
    }

    func testParseRejectsYearsBeyondJavaTimeRange() {
        XCTAssertEqual(LocalDate.parse("+999999999-12-31"), LocalDate(999_999_999, 12, 31))
        XCTAssertEqual(LocalDate.parse("-999999999-01-01"), LocalDate(-999_999_999, 1, 1))
        XCTAssertNil(LocalDate.parse("+1000000000-01-01"))
        XCTAssertNil(LocalDate.parse("-1000000000-01-01"))
        XCTAssertNil(LocalDate.parse("+9999999999-01-01"))
    }

    func testStartOfDayInAGapThatCrossesMidnightIsTheTransition() {
        // Toronto, 1919-03-31: clocks went from 23:30 (-05:00) to 00:30 (-04:00), so local
        // midnight never happened; java.time starts the day at the transition.
        XCTAssertEqual(LocalDate(1919, 3, 31).atStartOfDay(zone("America/Toronto")), instant("1919-03-31T04:30:00Z"))
        XCTAssertEqual(LocalDate(1919, 4, 1).atStartOfDay(zone("America/Toronto")), instant("1919-04-01T04:00:00Z"))
    }

    func testEpochMillisRoundTripsWholeMilliseconds() {
        XCTAssertEqual(Date(epochMilli: 1_920_964_085_647).epochMillis, 1_920_964_085_647)
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<20_000 {
            let millis = Int64.random(in: -62_135_596_800_000...253_402_300_799_999, using: &generator)
            XCTAssertEqual(Date(epochMilli: millis).epochMillis, millis)
        }
        // Between two milliseconds it is the floor, as toEpochMilli is.
        XCTAssertEqual(Date(timeIntervalSince1970: 1.0007).epochMillis, 1_000)
        XCTAssertEqual(Date(timeIntervalSince1970: -1.0003).epochMillis, -1_001)
    }

    func testLocalTimeParseIsIsoLocalTime() {
        XCTAssertEqual(LocalTime.parse("07:05"), LocalTime(7, 5))
        XCTAssertEqual(LocalTime.parse("23:59:59"), LocalTime(23, 59, 59))
        // A fraction of up to nine digits is accepted (and dropped here); so is a bare point.
        XCTAssertEqual(LocalTime.parse("12:30:45.5"), LocalTime(12, 30, 45))
        XCTAssertEqual(LocalTime.parse("12:30:45.123456789"), LocalTime(12, 30, 45))
        XCTAssertEqual(LocalTime.parse("12:30:45."), LocalTime(12, 30, 45))
        for text in ["+1:30", "-0:30", "1:30", "12:3", "24:00", "12:60", "12:30:60", "12:30.5", "12:30:45.1234567890",
                     "12:30:45.x", "１２:３０", "12:30:", "", "12"] {
            XCTAssertNil(LocalTime.parse(text), text)
        }
    }
}
