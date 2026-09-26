import Foundation

public struct DaySegment: Hashable, Sendable {
    public let startMinute: Double
    public let endMinuteExclusive: Double

    public init(_ startMinute: Double, _ endMinuteExclusive: Double) {
        self.startMinute = startMinute
        self.endMinuteExclusive = endMinuteExclusive
    }
}

public struct YearSegment: Hashable, Sendable {
    public let startFraction: Double
    public let sweepFraction: Double

    public init(_ startFraction: Double, _ sweepFraction: Double) {
        self.startFraction = startFraction
        self.sweepFraction = sweepFraction
    }
}

public enum CalendarIntervals {
    public static func inDay(_ event: CalendarOccurrence, _ day: LocalDate, _ zone: TimeZone) -> DaySegment? {
        let dayStart = day.atStartOfDay(zone)
        let dayEnd = day.plusDays(1).atStartOfDay(zone)
        // maxOf / minOf on ZonedDateTime order by instant first, and only the instants are used.
        let start = max(event.start.instant, dayStart)
        let end = min(event.endExclusive.instant, dayEnd)
        if !(end > start) { return nil }
        return DaySegment(
            Double(durationMillis(dayStart, start)) / 60_000.0,
            Double(durationMillis(dayStart, end)) / 60_000.0
        )
    }

    public static func inYear(_ event: CalendarOccurrence, _ year: Int, _ zone: TimeZone) -> YearSegment? {
        let yearStart = LocalDate(year, 1, 1).atStartOfDay(zone)
        let yearEnd = LocalDate(year + 1, 1, 1).atStartOfDay(zone)
        let start = max(event.start.instant, yearStart)
        let end = min(event.endExclusive.instant, yearEnd)
        if !(end > start) { return nil }
        let yearMillis = Double(durationMillis(yearStart, yearEnd))
        return YearSegment(
            Double(durationMillis(yearStart, start)) / yearMillis,
            Double(durationMillis(start, end)) / yearMillis
        )
    }
}
