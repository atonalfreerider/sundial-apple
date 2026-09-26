import Foundation

/// Deterministic astronomical state. All calculations receive an Instant; none read the system clock.
public enum Astronomy {
    public static let julianDateUnixEpoch = 2_440_587.5
    public static let julianDateJ2000 = 2_451_545.0
    public static let synodicMonthDays = 29.530588853

    public enum Body: Int, CaseIterable, Sendable {
        case mercury, venus, earth, mars

        public var ordinal: Int { rawValue }
    }

    public struct Vector3: Hashable, Sendable {
        public let x: Double
        public let y: Double
        public let z: Double

        public init(_ x: Double, _ y: Double, _ z: Double) {
            self.x = x
            self.y = y
            self.z = z
        }

        public var radius: Double { sqrt(x * x + y * y + z * z) }
        public var longitudeDegrees: Double { Astronomy.normalizeDegrees(Math.toDegrees(atan2(y, x))) }
    }

    private struct Elements {
        let a0: Double, aRate: Double
        let e0: Double, eRate: Double
        let i0: Double, iRate: Double
        let l0: Double, lRate: Double
        let peri0: Double, periRate: Double
        let node0: Double, nodeRate: Double

        init(_ a0: Double, _ aRate: Double,
             _ e0: Double, _ eRate: Double,
             _ i0: Double, _ iRate: Double,
             _ l0: Double, _ lRate: Double,
             _ peri0: Double, _ periRate: Double,
             _ node0: Double, _ nodeRate: Double) {
            self.a0 = a0; self.aRate = aRate
            self.e0 = e0; self.eRate = eRate
            self.i0 = i0; self.iRate = iRate
            self.l0 = l0; self.lRate = lRate
            self.peri0 = peri0; self.periRate = periRate
            self.node0 = node0; self.nodeRate = nodeRate
        }
    }

    // JPL SSD Table 2a, J2000 ecliptic/equinox, valid 3000 BC through 3000 AD.
    private static let elements: [Body: Elements] = [
        .mercury: Elements(0.38709843, 0.0, 0.20563661, 0.00002123, 7.00559432, -0.00590158,
            252.25166724, 149472.67486623, 77.45771895, 0.15940013, 48.33961819, -0.12214182),
        .venus: Elements(0.72332102, -0.00000026, 0.00676399, -0.00005107, 3.39777545, 0.00043494,
            181.97970850, 58517.81560260, 131.76755713, 0.05679648, 76.67261496, -0.27274174),
        .earth: Elements(1.00000018, -0.00000003, 0.01673163, -0.00003661, -0.00054346, -0.01337178,
            100.46691572, 35999.37306329, 102.93005885, 0.31795260, -5.11260389, -0.24123856),
        .mars: Elements(1.52371243, 0.00000097, 0.09336511, 0.00009149, 1.85181869, -0.00724757,
            -4.56813164, 19140.29934243, -23.91744784, 0.45223625, 49.71320984, -0.26852431),
    ]

    public static func julianDate(_ instant: Date) -> Double {
        julianDateUnixEpoch + Double(instant.epochSecond) / 86_400.0 + instant.nano / 86_400_000_000_000.0
    }

    public static func heliocentricPosition(_ body: Body, _ instant: Date) -> Vector3 {
        let t = (julianDate(instant) - julianDateJ2000) / 36_525.0
        let p = elements[body]!
        let a = p.a0 + p.aRate * t
        let e = p.e0 + p.eRate * t
        let inclination = radians(p.i0 + p.iRate * t)
        let meanLongitude = p.l0 + p.lRate * t
        let longitudePerihelion = p.peri0 + p.periRate * t
        let node = radians(p.node0 + p.nodeRate * t)
        let omega = radians(longitudePerihelion - (p.node0 + p.nodeRate * t))
        let meanAnomaly = normalizeSignedDegrees(meanLongitude - longitudePerihelion)
        let eccentricAnomaly = solveKepler(radians(meanAnomaly), e)

        let xp = a * (cos(eccentricAnomaly) - e)
        let yp = a * sqrt(1.0 - e * e) * sin(eccentricAnomaly)
        let cosW = cos(omega)
        let sinW = sin(omega)
        let cosO = cos(node)
        let sinO = sin(node)
        let cosI = cos(inclination)
        let sinI = sin(inclination)

        return Vector3(
            (cosW * cosO - sinW * sinO * cosI) * xp + (-sinW * cosO - cosW * sinO * cosI) * yp,
            (cosW * sinO + sinW * cosO * cosI) * xp + (-sinW * sinO + cosW * cosO * cosI) * yp,
            sinW * sinI * xp + cosW * sinI * yp
        )
    }

    /// Greenwich mean sidereal angle in degrees. Suitable for orienting the rendered Earth texture.
    public static func greenwichMeanSiderealDegrees(_ instant: Date) -> Double {
        let d = julianDate(instant) - julianDateJ2000
        let t = d / 36_525.0
        return normalizeDegrees(
            280.46061837 + 360.98564736629 * d + 0.000387933 * t * t - t * t * t / 38_710_000.0
        )
    }

    /// Approximate geocentric lunar ecliptic longitude (degrees), including the largest periodic terms.
    public static func moonLongitudeDegrees(_ instant: Date) -> Double {
        let d = julianDate(instant) - julianDateJ2000
        let l = normalizeDegrees(218.3164477 + 13.17639648 * d)
        let elongation = normalizeDegrees(297.8501921 + 12.19074912 * d)
        let sunAnomaly = normalizeDegrees(357.5291092 + 0.98560028 * d)
        let moonAnomaly = normalizeDegrees(134.9633964 + 13.06499295 * d)
        let argumentLatitude = normalizeDegrees(93.2720950 + 13.22935024 * d)
        func s(_ degrees: Double) -> Double { sin(radians(degrees)) }
        let longitude: Double = l + 6.289 * s(moonAnomaly)
            + 1.274 * s(2 * elongation - moonAnomaly)
            + 0.658 * s(2 * elongation)
            + 0.214 * s(2 * moonAnomaly)
            - 0.186 * s(sunAnomaly)
            - 0.059 * s(2 * elongation - 2 * moonAnomaly)
            - 0.057 * s(2 * elongation - sunAnomaly - moonAnomaly)
            + 0.053 * s(2 * elongation + moonAnomaly)
            + 0.046 * s(2 * elongation - sunAnomaly)
            + 0.041 * s(sunAnomaly - moonAnomaly)
            - 0.035 * s(elongation)
            - 0.031 * s(sunAnomaly + moonAnomaly)
            - 0.015 * s(2 * argumentLatitude - 2 * elongation)
            + 0.011 * s(moonAnomaly - 4 * elongation)
        return normalizeDegrees(longitude)
    }

    /// Moon–Sun elongation in degrees. The lunar series is referred to the equinox of date, so the
    /// J2000 solar longitude is precessed into the same frame before the two are compared.
    public static func moonPhaseDegrees(_ instant: Date) -> Double {
        normalizeDegrees(moonLongitudeDegrees(instant) - sunLongitudeOfDate(instant))
    }

    /// Geocentric solar longitude referred to the mean equinox of date.
    public static func sunLongitudeOfDate(_ instant: Date) -> Double {
        normalizeDegrees(heliocentricPosition(.earth, instant).longitudeDegrees + 180.0 + precessionDegrees(instant))
    }

    /// General precession in longitude from J2000 to the equinox of date.
    public static func precessionDegrees(_ instant: Date) -> Double {
        let centuries = (julianDate(instant) - julianDateJ2000) / 36_525.0
        return 1.396_971_3 * centuries + 0.000_308_6 * centuries * centuries
    }

    public static func daysInYear(_ year: Int) -> Int { LocalDate(year, 1, 1).isLeapYear ? 366 : 365 }

    /// Fraction of the local civil year, preserving leap day and sub-day precision.
    public static func civilYearFraction(_ dateTime: ZonedDateTime) -> Double {
        let start = dateTime.date.withDayOfYear(1).atStartOfDay(dateTime.zone)
        let end = dateTime.date.withDayOfYear(1).plusYears(1).atStartOfDay(dateTime.zone)
        let totalNanos = Double(end.epochSecond - start.epochSecond) * 1_000_000_000.0 + end.nano - start.nano
        // dateTime.nano in Kotlin; read from the instant so it matches the instant's epochSecond.
        let elapsedNanos = Double(dateTime.instant.epochSecond - start.epochSecond) * 1_000_000_000.0
            + dateTime.instant.nano - start.nano
        return min(max(elapsedNanos / totalNanos, 0.0), 1.0)
    }

    public static func instantAtYearFraction(_ year: Int, _ fraction: Double, _ zoneId: TimeZone) -> Date {
        let start = LocalDate(year, 1, 1).atStartOfDay(zoneId)
        let end = LocalDate(year + 1, 1, 1).atStartOfDay(zoneId)
        // toLong(): a NaN fraction survives coerceIn and becomes 0 nanos, the start of the year.
        let nanos = (Double(end.epochSecond - start.epochSecond) * min(max(fraction, 0.0), 0.999999999) * 1e9).toLong()
        return start.addingTimeInterval(Double(nanos) / 1_000_000_000)
    }

    private static func solveKepler(_ meanAnomalyRadians: Double, _ eccentricity: Double) -> Double {
        var eccentricAnomaly = meanAnomalyRadians + eccentricity * sin(meanAnomalyRadians)
        for _ in 0..<20 {
            let delta = (meanAnomalyRadians - (eccentricAnomaly - eccentricity * sin(eccentricAnomaly))) /
                (1.0 - eccentricity * cos(eccentricAnomaly))
            eccentricAnomaly += delta
            if abs(delta) < 1e-12 { return eccentricAnomaly }
        }
        return eccentricAnomaly
    }

    public static func normalizeDegrees(_ value: Double) -> Double {
        (value.truncatingRemainder(dividingBy: 360.0) + 360.0).truncatingRemainder(dividingBy: 360.0)
    }

    public static func normalizeSignedDegrees(_ value: Double) -> Double { normalizeDegrees(value + 180.0) - 180.0 }

    private static func radians(_ degrees: Double) -> Double { degrees * Double.pi / 180.0 }
}
