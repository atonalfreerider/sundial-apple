import Foundation

/// Civil-time positions and human labels for the 24 timezone spokes.
public enum TimeZoneDial {
    public struct Spoke: Hashable, Sendable {
        public let offsetHours: Int
        public let angleDegrees: Double
        public let localDate: LocalDate
        public let label: String

        public init(_ offsetHours: Int, _ angleDegrees: Double, _ localDate: LocalDate, _ label: String) {
            self.offsetHours = offsetHours
            self.angleDegrees = angleDegrees
            self.localDate = localDate
            self.label = label
        }
    }

    /// Spokes sit on Unity's solar 24-hour ring: each zone points at its local time, so the zone
    /// at noon faces the Sun (screen top) and midnight faces away.
    public static func spokes(_ instant: Date, north: Bool = true) -> [Spoke] {
        (-12...11).map { offset in
            let local = ZonedDateTime(instant, .offset(seconds: offset * 3_600))
            return Spoke(
                offset, // offsetHours
                DialGeometry.hourAngle( // angleDegrees
                    (Double(local.hour) * 60.0 + Double(local.minute) + Double(local.second) / 60.0) / 60.0, north
                ),
                local.date, // localDate
                commonName(offset) // label
            )
        }
    }

    /// Hour-ring position of the international date line: the local time of day just west of it
    /// (UTC+12). Zones from local midnight round to this point already have the new date.
    public static func datelineHours(_ instant: Date) -> Double {
        let local = ZonedDateTime(instant, .offset(seconds: 12 * 3_600))
        return Double(local.hour) + Double(local.minute) / 60.0 + Double(local.second) / 3_600.0
    }

    public static func localOffsetMinutes(_ instant: Date, _ zoneId: TimeZone) -> Int {
        zoneId.secondsFromGMT(for: instant) / 60
    }

    public static func angleForOffsetMinutes(_ instant: Date, _ offsetMinutes: Int, north: Bool = true) -> Double {
        let local = ZonedDateTime(instant, .offset(seconds: offsetMinutes * 60))
        let localMinutes = Double(local.hour) * 60.0 + Double(local.minute) + Double(local.second) / 60.0
            + Double(local.nano) / 60_000_000_000.0
        return DialGeometry.hourAngle(localMinutes / 60.0, north)
    }

    public static func localName(_ zoneId: TimeZone, _ instant: Date) -> String {
        let id = zoneId.identifier
        if id.contains("Los_Angeles") || id.contains("Vancouver") { return "Pacific Time" }
        if id.contains("Denver") || id.contains("Phoenix") || id.contains("Edmonton") { return "Mountain Time" }
        if id.contains("Chicago") || id.contains("Winnipeg") { return "Central Time" }
        if id.contains("New_York") || id.contains("Toronto") { return "Eastern Time" }
        if id.contains("Anchorage") { return "Alaska Time" }
        if id.contains("Honolulu") { return "Hawaii Time" }
        if id.contains("London") { return "UK Time" }
        if id.contains("Paris") || id.contains("Berlin") || id.contains("Rome") { return "Central European Time" }
        if id.contains("Tokyo") { return "Japan Time" }
        if id.contains("Sydney") || id.contains("Melbourne") { return "Eastern Australia Time" }
        return commonName(Math.floorDiv(localOffsetMinutes(instant, zoneId), 60))
    }

    public static func commonName(_ offsetHours: Int) -> String {
        switch offsetHours {
        case -12: return "Date Line West"
        case -11: return "Samoa Time"
        case -10: return "Hawaii Time"
        case -9: return "Alaska Time"
        case -8: return "Pacific Time"
        case -7: return "Mountain Time"
        case -6: return "Central Time"
        case -5: return "Eastern Time"
        case -4: return "Atlantic Time"
        case -3: return "Argentina Time"
        case -2: return "South Georgia Time"
        case -1: return "Azores Time"
        case 0: return "UK / Greenwich Time"
        case 1: return "Central European Time"
        case 2: return "Eastern European Time"
        case 3: return "Moscow Time"
        case 4: return "Gulf Time"
        case 5: return "Pakistan Time"
        case 6: return "Bangladesh Time"
        case 7: return "Indochina Time"
        case 8: return "China / Singapore Time"
        case 9: return "Japan / Korea Time"
        case 10: return "Eastern Australia Time"
        case 11: return "Solomon Islands Time"
        default: return "UTC\(offsetHours >= 0 ? "+" : "")\(offsetHours)"
        }
    }

    /// The spoke nearest [angleDegrees]; on a tie the first, as Kotlin's minBy keeps it.
    public static func nearestSpoke(_ spokes: [Spoke], _ angleDegrees: Double) -> Spoke {
        spokes.min { abs(normalizeSigned($0.angleDegrees - angleDegrees)) < abs(normalizeSigned($1.angleDegrees - angleDegrees)) }!
    }

    private static func normalizeSigned(_ value: Double) -> Double {
        (value + 540.0).truncatingRemainder(dividingBy: 360.0) - 180.0
    }
}
