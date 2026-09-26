import Foundation

/// Pure circular hit-testing shared by the annual and daily calendar rings.
public enum CalendarHitTesting {
    public static func containsYearFraction(
        _ touchFraction: Double,
        _ startFraction: Double,
        _ sweepFraction: Double,
        _ paddingFraction: Double
    ) -> Bool {
        containsCircular(
            touchFraction,
            startFraction,
            sweepFraction,
            paddingFraction,
            1.0 // period
        )
    }

    public static func containsMinute(
        _ touchMinute: Double,
        _ startMinute: Double,
        _ endMinuteExclusive: Double,
        _ paddingMinutes: Double
    ) -> Bool {
        containsCircular(
            touchMinute,
            startMinute,
            max(endMinuteExclusive - startMinute, 0.0),
            paddingMinutes,
            1_440.0 // period
        )
    }

    private static func containsCircular(
        _ touch: Double,
        _ start: Double,
        _ sweep: Double,
        _ padding: Double,
        _ period: Double
    ) -> Bool {
        let safePadding = max(padding, 0.0)
        let span = min(sweep + safePadding * 2.0, period)
        let paddedStart = normalize(start - safePadding, period)
        let forward = normalize(touch - paddedStart, period)
        return forward <= span
    }

    private static func normalize(_ value: Double, _ period: Double) -> Double {
        var normalized = value.truncatingRemainder(dividingBy: period)
        if normalized < 0.0 { normalized += period }
        return normalized
    }
}
