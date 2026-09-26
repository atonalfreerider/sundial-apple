import Foundation

public struct DeviceCalendar: Hashable, Sendable {
    public let id: Int64
    public let displayName: String
    public let accountName: String
    public let accountType: String
    public let color: ARGB
    public let selected: Bool

    public init(_ id: Int64, _ displayName: String, _ accountName: String, _ accountType: String, _ color: ARGB,
                selected: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.accountName = accountName
        self.accountType = accountType
        self.color = color
        self.selected = selected
    }

    /// accountType.equals("com.google", ignoreCase = true). Only ASCII letters case-fold onto
    /// "com.google" in Java's char-by-char comparison, and lowercasing agrees on those.
    public var isGoogle: Bool { accountType.lowercased() == "com.google" }
}

public struct RawCalendarInstance: Hashable, Sendable {
    public let eventId: Int64
    public let calendarId: Int64
    public let title: String
    public let beginMillis: Int64
    public let endMillis: Int64
    public let allDay: Bool
    public let eventTimeZone: String?
    public let color: ARGB

    public init(_ eventId: Int64, _ calendarId: Int64, _ title: String, _ beginMillis: Int64, _ endMillis: Int64,
                _ allDay: Bool, _ eventTimeZone: String?, _ color: ARGB) {
        self.eventId = eventId
        self.calendarId = calendarId
        self.title = title
        self.beginMillis = beginMillis
        self.endMillis = endMillis
        self.allDay = allDay
        self.eventTimeZone = eventTimeZone
        self.color = color
    }
}

/// A normalized occurrence. End is exclusive, matching CalendarContract.
public struct CalendarOccurrence: Equatable, Sendable {
    public let eventId: Int64
    public let calendarId: Int64
    public let title: String
    public let start: ZonedDateTime
    public let endExclusive: ZonedDateTime
    public let allDayStart: LocalDate?
    public let allDayEndExclusive: LocalDate?
    public let color: ARGB

    public init(_ eventId: Int64, _ calendarId: Int64, _ title: String, _ start: ZonedDateTime,
                _ endExclusive: ZonedDateTime, _ allDayStart: LocalDate?, _ allDayEndExclusive: LocalDate?,
                _ color: ARGB) {
        self.eventId = eventId
        self.calendarId = calendarId
        self.title = title
        self.start = start
        self.endExclusive = endExclusive
        self.allDayStart = allDayStart
        self.allDayEndExclusive = allDayEndExclusive
        self.color = color
    }

    public var isAllDay: Bool { allDayStart != nil }
    public var isYearRingEvent: Bool {
        isAllDay || durationMillis(start.instant, endExclusive.instant) / 3_600_000 >= 24
    }

    /// The data class's equals. ZonedDateTime (CivilTime.swift) is not Equatable; java.time's
    /// ZonedDateTime.equals comes down to the same instant in the same zone.
    public static func == (lhs: CalendarOccurrence, rhs: CalendarOccurrence) -> Bool {
        lhs.eventId == rhs.eventId && lhs.calendarId == rhs.calendarId && lhs.title == rhs.title &&
            lhs.start.instant == rhs.start.instant && lhs.start.zone == rhs.start.zone &&
            lhs.endExclusive.instant == rhs.endExclusive.instant && lhs.endExclusive.zone == rhs.endExclusive.zone &&
            lhs.allDayStart == rhs.allDayStart && lhs.allDayEndExclusive == rhs.allDayEndExclusive &&
            lhs.color == rhs.color
    }
}

public enum CalendarNormalizer {
    /// Android stores all-day event millis at UTC midnight. Those millis represent date labels, not instants
    /// to shift into the device zone. Timed events are real instants and use full ZoneId/DST rules.
    public static func normalize(_ raw: RawCalendarInstance, _ displayZone: TimeZone) -> CalendarOccurrence {
        let beginInstant = Date(epochMilli: raw.beginMillis)
        let endInstant = Date(epochMilli: max(raw.endMillis, raw.beginMillis + 1))
        if raw.allDay {
            let startDate = ZonedDateTime(beginInstant, utc).date
            let endDate = ZonedDateTime(endInstant, utc).date
            return CalendarOccurrence(
                raw.eventId, raw.calendarId, raw.title,
                ZonedDateTime(startDate.atStartOfDay(displayZone), displayZone),
                ZonedDateTime(endDate.atStartOfDay(displayZone), displayZone),
                startDate, endDate, raw.color
            )
        } else {
            return CalendarOccurrence(
                raw.eventId, raw.calendarId, raw.title,
                ZonedDateTime(beginInstant, displayZone), ZonedDateTime(endInstant, displayZone),
                nil, nil, raw.color
            )
        }
    }

    /// ZoneId.of("UTC").
    private static let utc = TimeZone(identifier: "UTC")!
}
