import Foundation

// The Android instrument works in java.time: Instant, LocalDate and ZonedDateTime. These are the
// same ideas in Swift, so ported code reads line for line: an instant is a Foundation Date, a
// zone is a TimeZone, and LocalDate / ZonedDateTime behave as java.time's do, including how a
// local time in a daylight-saving gap or overlap resolves to an instant.

/// A date without a time or zone, in the proleptic Gregorian calendar (java.time.LocalDate).
public struct LocalDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(_ year: Int, _ month: Int, _ day: Int) {
        precondition((1...12).contains(month), "month \(month)")
        precondition(day >= 1 && day <= LocalDate.lengthOfMonth(year, month), "day \(day) of \(year)-\(month)")
        self.year = year
        self.month = month
        self.day = day
    }

    /// Days since 1970-01-01 (java.time's epoch day).
    public init(epochDay: Int) {
        // Howard Hinnant's civil_from_days.
        let z = epochDay + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        self.init(yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)
    }

    public var epochDay: Int {
        // Howard Hinnant's days_from_civil.
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = month > 2 ? month - 3 : month + 9
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    public static func ofYearDay(_ year: Int, _ dayOfYear: Int) -> LocalDate {
        LocalDate(epochDay: LocalDate(year, 1, 1).epochDay + dayOfYear - 1)
    }

    public static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    public static func lengthOfMonth(_ year: Int, _ month: Int) -> Int {
        switch month {
        case 2: return isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    public var isLeapYear: Bool { LocalDate.isLeapYear(year) }
    public var lengthOfYear: Int { isLeapYear ? 366 : 365 }
    public var lengthOfMonth: Int { LocalDate.lengthOfMonth(year, month) }
    public var dayOfYear: Int { epochDay - LocalDate(year, 1, 1).epochDay + 1 }

    /// ISO day of week, as java.time.DayOfWeek.getValue(): Monday is 1, Sunday is 7.
    public var dayOfWeek: Int {
        // 1970-01-01 was a Thursday (4).
        let offset = (epochDay + 3) % 7
        return (offset < 0 ? offset + 7 : offset) + 1
    }

    public func plusDays(_ days: Int) -> LocalDate { LocalDate(epochDay: epochDay + days) }
    public func minusDays(_ days: Int) -> LocalDate { plusDays(-days) }

    /// Adds whole years, clamping 29 February to the 28th in a common year (java.time).
    public func plusYears(_ years: Int) -> LocalDate {
        let target = year + years
        return LocalDate(target, month, min(day, LocalDate.lengthOfMonth(target, month)))
    }

    public func withDayOfYear(_ dayOfYear: Int) -> LocalDate { LocalDate.ofYearDay(year, dayOfYear) }
    public func withDayOfMonth(_ day: Int) -> LocalDate { LocalDate(year, month, day) }

    /// The first instant of this date in [zone] (java.time's atStartOfDay).
    public func atStartOfDay(_ zone: TimeZone) -> Date {
        ZonedDateTime.instant(localSeconds: Double(epochDay) * 86_400, zone: zone)
    }

    /// The date of [instant] in [zone].
    public static func of(_ instant: Date, _ zone: TimeZone) -> LocalDate {
        ZonedDateTime(instant, zone).date
    }

    /// Three-letter English month name in capitals, as java.time's Month.name.take(3).
    public var monthAbbreviation: String { LocalDate.monthAbbreviations[month - 1] }
    /// Three-letter English weekday in capitals, as java.time's DayOfWeek.name.take(3).
    public var weekdayAbbreviation: String { LocalDate.weekdayAbbreviations[dayOfWeek - 1] }

    public static let monthAbbreviations = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
    public static let weekdayAbbreviations = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool { lhs.epochDay < rhs.epochDay }

    /// ISO format, as java.time's LocalDate.toString(): 2026-09-25.
    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Parses ISO yyyy-MM-dd (LocalDate.parse); nil for anything else or an impossible date.
    public static func parse(_ text: String) -> LocalDate? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), d >= 1, d <= lengthOfMonth(y, m) else { return nil }
        return LocalDate(y, m, d)
    }
}

/// A time of day (java.time.LocalTime), to the second.
public struct LocalTime: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let hour: Int
    public let minute: Int
    public let second: Int

    public init(_ hour: Int, _ minute: Int, _ second: Int = 0) {
        precondition((0...23).contains(hour) && (0...59).contains(minute) && (0...59).contains(second))
        self.hour = hour
        self.minute = minute
        self.second = second
    }

    public var secondOfDay: Int { hour * 3_600 + minute * 60 + second }

    public static func < (lhs: LocalTime, rhs: LocalTime) -> Bool { lhs.secondOfDay < rhs.secondOfDay }

    /// As java.time's LocalTime.toString(): 07:05, or 07:05:09 when there are seconds.
    public var description: String {
        second == 0 ? String(format: "%02d:%02d", hour, minute) : String(format: "%02d:%02d:%02d", hour, minute, second)
    }

    /// Parses HH:mm or HH:mm:ss (LocalTime.parse).
    public static func parse(_ text: String) -> LocalTime? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3, parts.allSatisfy({ $0.count == 2 }),
              let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        let s = parts.count == 3 ? Int(parts[2]) : 0
        guard let second = s, (0...59).contains(second) else { return nil }
        return LocalTime(h, m, second)
    }
}

/// An instant seen in a zone (java.time.ZonedDateTime).
public struct ZonedDateTime: Sendable {
    public let instant: Date
    public let zone: TimeZone
    /// Seconds east of UTC at this instant, daylight saving included.
    public let offsetSeconds: Int
    public let date: LocalDate
    /// Seconds since local midnight, with the fraction.
    public let secondOfDay: Double

    public init(_ instant: Date, _ zone: TimeZone) {
        self.instant = instant
        self.zone = zone
        offsetSeconds = zone.secondsFromGMT(for: instant)
        let local = instant.timeIntervalSince1970 + Double(offsetSeconds)
        let day = (local / 86_400).rounded(.down)
        date = LocalDate(epochDay: Int(day))
        secondOfDay = local - day * 86_400
    }

    public var year: Int { date.year }
    public var month: Int { date.month }
    public var dayOfMonth: Int { date.day }
    public var dayOfYear: Int { date.dayOfYear }
    public var hour: Int { Int(secondOfDay) / 3_600 }
    public var minute: Int { (Int(secondOfDay) / 60) % 60 }
    public var second: Int { Int(secondOfDay) % 60 }
    /// Nanoseconds within the second, as java.time's getNano().
    public var nano: Int { Int(((secondOfDay - secondOfDay.rounded(.down)) * 1e9).rounded()) }

    /// The same instant in another zone (withZoneSameInstant).
    public func withZone(_ other: TimeZone) -> ZonedDateTime { ZonedDateTime(instant, other) }

    /// The instant at [localSeconds] (seconds since 1970-01-01T00:00 on the local clock) in
    /// [zone], resolved as java.time does: in an overlap the earlier offset wins, and a time in a
    /// gap moves later by the length of the gap.
    public static func instant(localSeconds: Double, zone: TimeZone) -> Date {
        func offset(_ utc: Double) -> Double { Double(zone.secondsFromGMT(for: Date(timeIntervalSince1970: utc))) }
        // Offsets in force within a day either side; a zone changes offset at most once in that span.
        let candidates = Set([offset(localSeconds - 86_400), offset(localSeconds + 86_400),
                              offset(localSeconds), offset(localSeconds - offset(localSeconds))])
        let valid = candidates.filter { offset(localSeconds - $0) == $0 }
        // Overlap: the larger offset gives the earlier instant. Gap: the offset before it.
        let chosen = valid.isEmpty ? candidates.min()! : valid.max()!
        return Date(timeIntervalSince1970: localSeconds - chosen)
    }

    /// The instant of [date] at [time] in [zone].
    public static func instant(_ date: LocalDate, _ time: LocalTime, _ zone: TimeZone) -> Date {
        instant(localSeconds: Double(date.epochDay) * 86_400 + Double(time.secondOfDay), zone: zone)
    }
}

/// Formats an instant in a zone with a java.time / ICU pattern, in English (as the Android app's
/// DateTimeFormatter.ofPattern on an English device).
public enum CivilFormat {
    private static var cache: [String: DateFormatter] = [:]
    private static let lock = NSLock()

    public static func format(_ instant: Date, _ pattern: String, _ zone: TimeZone) -> String {
        lock.lock()
        defer { lock.unlock() }
        let key = pattern + "|" + zone.identifier
        let formatter: DateFormatter
        if let cached = cache[key] {
            formatter = cached
        } else {
            formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = zone
            formatter.dateFormat = pattern
            cache[key] = formatter
        }
        return formatter.string(from: instant)
    }

    /// Formats a date without a zone (it is shown at its own midnight in UTC).
    public static func format(_ date: LocalDate, _ pattern: String) -> String {
        format(date.atStartOfDay(utc), pattern, utc)
    }

    public static let utc = TimeZone(identifier: "UTC")!
}

public extension Date {
    /// Adds whole and fractional seconds (Instant.plusSeconds / plusMillis / plusNanos).
    func plusSeconds(_ seconds: Double) -> Date { addingTimeInterval(seconds) }
    var epochSecond: Int64 { Int64((timeIntervalSince1970).rounded(.down)) }
    var epochMillis: Int64 { Int64((timeIntervalSince1970 * 1_000).rounded(.down)) }
}

public extension TimeZone {
    /// A fixed offset from UTC (ZoneOffset.ofTotalSeconds).
    static func offset(seconds: Int) -> TimeZone { TimeZone(secondsFromGMT: seconds)! }
}
