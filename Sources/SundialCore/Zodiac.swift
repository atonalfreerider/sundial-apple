import Foundation

/// The common Western tropical zodiac and geocentric sign calculations.
public enum Zodiac {
    public enum Sign: Int, CaseIterable, Sendable {
        case aries, taurus, gemini, cancer, leo, virgo, libra, scorpio, sagittarius, capricorn, aquarius, pisces

        public var ordinal: Int { rawValue }
        /// The Kotlin constant name ("SAGITTARIUS", Enum.name): how a sign is stored and signed.
        public var name: String { String(describing: self).uppercased() }

        public var displayName: String { properties.displayName }
        public var symbol: String { properties.symbol }
        public var element: Element { properties.element }
        public var startMonth: Int { properties.startMonth }
        public var startDay: Int { properties.startDay }

        private var properties: (displayName: String, symbol: String, element: Element, startMonth: Int, startDay: Int) {
            switch self {
            case .aries: return ("Aries", "♈︎", .fire, 3, 21)
            case .taurus: return ("Taurus", "♉︎", .earth, 4, 20)
            case .gemini: return ("Gemini", "♊︎", .air, 5, 21)
            case .cancer: return ("Cancer", "♋︎", .water, 6, 21)
            case .leo: return ("Leo", "♌︎", .fire, 7, 23)
            case .virgo: return ("Virgo", "♍︎", .earth, 8, 23)
            case .libra: return ("Libra", "♎︎", .air, 9, 23)
            case .scorpio: return ("Scorpio", "♏︎", .water, 10, 23)
            case .sagittarius: return ("Sagittarius", "♐︎", .fire, 11, 22)
            case .capricorn: return ("Capricorn", "♑︎", .earth, 12, 22)
            case .aquarius: return ("Aquarius", "♒︎", .air, 1, 20)
            case .pisces: return ("Pisces", "♓︎", .water, 2, 19)
            }
        }
    }

    public enum Element: Int, CaseIterable, Sendable {
        case fire, earth, air, water

        public var ordinal: Int { rawValue }
    }

    public enum Season: Int, CaseIterable, Sendable {
        case spring, summer, fall, winter

        public var ordinal: Int { rawValue }
    }

    public struct Placement: Hashable, Sendable {
        public let label: String
        public let symbol: String
        public let longitudeDegrees: Double
        public let sign: Sign

        public init(_ label: String, _ symbol: String, _ longitudeDegrees: Double, _ sign: Sign) {
            self.label = label
            self.symbol = symbol
            self.longitudeDegrees = longitudeDegrees
            self.sign = sign
        }
    }

    /// Common civil-date Sun sign, intentionally distinct from a sidereal constellation calendar.
    public static func signFor(_ date: LocalDate) -> Sign {
        let monthDay = date.month * 100 + date.day
        return Sign.allCases
            .sorted { $0.startMonth * 100 + $0.startDay < $1.startMonth * 100 + $1.startDay }
            .last { monthDay >= $0.startMonth * 100 + $0.startDay }
            ?? .capricorn
    }

    public static func signForLongitude(_ longitudeDegrees: Double) -> Sign {
        Sign.allCases[min(max(Int(Astronomy.normalizeDegrees(longitudeDegrees) / 30.0), 0), 11)]
    }

    public static func seasonFor(_ date: LocalDate, _ northernHemisphere: Bool) -> Season {
        let northern: Season
        switch signFor(date) {
        case .aries, .taurus, .gemini: northern = .spring
        case .cancer, .leo, .virgo: northern = .summer
        case .libra, .scorpio, .sagittarius: northern = .fall
        case .capricorn, .aquarius, .pisces: northern = .winter
        }
        if northernHemisphere { return northern }
        switch northern {
        case .spring: return .fall
        case .summer: return .winter
        case .fall: return .spring
        case .winter: return .summer
        }
    }

    /// Geocentric tropical longitude for the instrument hands. Planet vectors are J2000 ecliptic;
    /// general precession moves them into the equinox of date before assigning a tropical sign.
    public static func geocentricLongitude(_ body: Astronomy.Body, _ instant: Date) -> Double {
        precondition(body != .earth)
        let earth = Astronomy.heliocentricPosition(.earth, instant)
        let planet = Astronomy.heliocentricPosition(body, instant)
        let j2000Longitude = Math.toDegrees(atan2(planet.y - earth.y, planet.x - earth.x))
        return Astronomy.normalizeDegrees(j2000Longitude + Astronomy.precessionDegrees(instant))
    }

    public static func sunLongitude(_ instant: Date) -> Double { Astronomy.sunLongitudeOfDate(instant) }

    public static func placements(_ instant: Date) -> [Placement] {
        [
            Placement("SUN", "☉", sunLongitude(instant), signForLongitude(sunLongitude(instant))),
            Placement("MOON", "☾︎", Astronomy.moonLongitudeDegrees(instant), signForLongitude(Astronomy.moonLongitudeDegrees(instant))),
            Placement("MERCURY", "☿", geocentricLongitude(.mercury, instant), signForLongitude(geocentricLongitude(.mercury, instant))),
            Placement("VENUS", "♀", geocentricLongitude(.venus, instant), signForLongitude(geocentricLongitude(.venus, instant))),
            Placement("MARS", "♂", geocentricLongitude(.mars, instant), signForLongitude(geocentricLongitude(.mars, instant))),
        ]
    }
}
