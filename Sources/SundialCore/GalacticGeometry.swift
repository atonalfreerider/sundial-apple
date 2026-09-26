import Foundation

/// Unity's galactic view: the Sun carries the planets along an axis perpendicular to their orbits,
/// so each orbit is drawn out into a helix. As in Unity, the Sun stays put and an endless ribbon of
/// years slides beneath it; later years lie further along the direction of travel.
///
/// Screen vectors use Android canvas axes (x right, y down).
public enum GalacticGeometry {
    /// Direction of travel on screen: up and to the left.
    private static let travelRadians = Math.toRadians(-122.0)
    public static let travelX = cos(travelRadians)
    public static let travelY = sin(travelRadians)

    /// Perpendicular to travel, pointing to its right, so orbits run counter-clockwise from above.
    public static let sideX = -travelY
    public static let sideY = travelX

    /// Distance the Sun travels in one year, in dial radii.
    public static let yearPitch = 0.62

    /// Foreshortening of each orbit's depth, seen obliquely from the direction of travel.
    public static let orbitDepth = 0.24

    public static let minYear = 1
    public static let maxYear = 9_999

    /// Local civil date as a continuous year: 2026.5 is the middle of 2026.
    public static func continuousYear(_ instant: Date, _ zone: TimeZone) -> Double {
        let local = ZonedDateTime(instant, zone)
        return Double(local.year) + Astronomy.civilYearFraction(local)
    }

    /// Inverse of [continuousYear], clamped to the years a civil calendar label can show.
    public static func instantAt(_ continuousYear: Double, _ zone: TimeZone) -> Date {
        let clamped = min(max(continuousYear, Double(minYear)), Double(maxYear) + 0.999_999)
        // Kotlin's coerceIn passes NaN through and NaN.toInt() is 0, so NaN lands on the start of
        // year 0 (instantAtYearFraction's toLong() makes the NaN fraction 0 nanos).
        let year = floor(clamped).toInt()
        return Astronomy.instantAtYearFraction(year, clamped - Double(year), zone)
    }

    /// Continuous year at which a month begins, for the ribbon's month ticks.
    public static func monthStart(_ year: Int, _ month: Int) -> Double {
        let date = LocalDate(year, month, 1)
        return Double(year) + Double(date.dayOfYear - 1) / Double(Astronomy.daysInYear(year))
    }

    /// A body's offset from the Sun as (along travel, to the side), in the same units as
    /// [orbitRadius]. The far side of an orbit leans toward the direction of travel.
    public static func orbitOffset(_ longitudeDegrees: Double, _ orbitRadius: Double) -> (Double, Double) {
        let longitude = Math.toRadians(longitudeDegrees)
        return (sin(longitude) * orbitRadius * orbitDepth, cos(longitude) * orbitRadius)
    }
}
