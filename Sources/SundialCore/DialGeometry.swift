import Foundation

/// Ratios reconstructed from the original Unity instrument's 150-unit annual dial.
public enum DialGeometry {
    public static let mercuryOrbit = 0.1935
    public static let venusOrbit = 0.3615
    public static let earthOrbit = 0.5000
    public static let marsOrbit = 0.7615

    /// The astrology mode's zodiac ring, and where its hands meet it.
    public static let zodiacOuter = 0.875
    public static let zodiacInner = 0.705
    public static let zodiacHandEnd = 0.692

    // The native viewport radius is the lunar dial, rather than Unity's annual dial.
    public static let moonDial = 0.965
    /// One Unity world unit on the Earth instrument, whose lunar dial is 67.5 units.
    private static let earthUnit = moonDial / 67.5
    public static let hourDial = 60 * earthUnit
    public static let earthRadius = 37.5 * earthUnit

    /// Unity's local wheel: a thin ring hugging the globe with 24 outward hour teeth. The tooth at
    /// the selected zone's local time is long, with a shorter red tooth inscribed in it.
    public static let localWheel = 42 * earthUnit
    public static let localWheelSmallTooth = 3 * earthUnit
    public static let localWheelBigTooth = 15 * earthUnit
    public static let localWheelRedTooth = 10.5 * earthUnit
    public static let localWheelRedHalfBase = 1.125 * earthUnit
    /// Half-width of each tooth's base, Unity's 0.04 rad.
    public static let localWheelToothHalfAngle = 2.2918
    /// The translucent band inside the wheel that spans the zones already on the new date.
    public static let dateStripOuter = 41 * earthUnit
    public static let dateStripInner = 38.5 * earthUnit

    /// Matches Unity's portrait earthOrthoSize = solOrthoSize * .45 camera move.
    public static let earthCameraZoom = 1 / 0.45

    /// The solar view's Earth subdial is the Earth view drawn at this scale (deliberately enlarged, not
    /// to scale), so the camera flight starts from exactly what the subdial shows.
    public static let earthSubdialScale = 0.115
    public static let heliocentricEarthRadius = earthRadius * earthSubdialScale
    public static let subdialGear = hourDial * earthSubdialScale
    /// The enlarged lunar track, just outside the subdial's gear teeth.
    public static let subdialMoonTrack = 0.135

    public struct EventBand: Hashable, Sendable {
        public let centerRadius: Double
        public let thickness: Double

        public init(_ centerRadius: Double, _ thickness: Double) {
            self.centerRadius = centerRadius
            self.thickness = thickness
        }
    }

    /// Unity's sidereal year and "January 1st is 10 days past the winter solstice" dial offset.
    public static let unityYearDays = 365.256363004
    /// Canvas angle of January 1st (clockwise from +x). Unity rotates the sun sprocket by
    /// -10 * 360 / YEAR - 180, putting the December solstice straight below the Sun and the
    /// equinoxes on the horizontal season-cross axis.
    public static let januaryFirstAngle = 90.0 - 10.0 * 360.0 / unityYearDays

    /// Annual dial angle. North is Unity's view from the north ecliptic pole (time runs
    /// counter-clockwise); south is its mirror image.
    public static func annualAngle(_ fraction: Double, _ north: Bool) -> Double {
        let northAngle = januaryFirstAngle - fraction * 360.0
        return north ? northAngle : 180.0 - northAngle
    }

    public static func yearFractionFromAngle(_ angleDegrees: Double, _ north: Bool) -> Double {
        let northAngle = north ? angleDegrees : 180.0 - angleDegrees
        var fraction = (januaryFirstAngle - northAngle) / 360.0
        fraction -= floor(fraction)
        return fraction
    }

    /// Canvas angle of an ecliptic longitude in the same frame as [annualAngle]: longitude 0 (the
    /// direction of Earth at the September equinox) is on the left in the north view, and Earth's
    /// true heliocentric longitude lands on its civil date on the annual dial.
    public static func eclipticAngle(_ longitudeDegrees: Double, _ north: Bool) -> Double {
        north ? 180.0 - longitudeDegrees : longitudeDegrees
    }

    /// Earth-centred (geocentric) view with the Sun at the top. Unity's 24-hour ring puts solar noon
    /// toward the Sun and midnight away from it, with hours running counter-clockwise in the north.
    public static func hourAngle(_ hours: Double, _ north: Bool) -> Double {
        north ? 90.0 - hours * 15.0 : 90.0 + hours * 15.0
    }

    /// Inverse of [hourAngle], in minutes after midnight on the range [0, 1440).
    public static func minuteFromHourAngle(_ angleDegrees: Double, _ north: Bool) -> Double {
        let hours = north ? (90.0 - angleDegrees) / 15.0 : (angleDegrees - 90.0) / 15.0
        return ((hours * 60.0).truncatingRemainder(dividingBy: 1_440.0) + 1_440.0).truncatingRemainder(dividingBy: 1_440.0)
    }

    /// Moon hand angle in the geocentric view: new Moon toward the Sun, then counter-clockwise (north).
    public static func moonAngle(_ phaseDegrees: Double, _ north: Bool) -> Double {
        north ? -90.0 - phaseDegrees : -90.0 + phaseDegrees
    }

    /// Inverse of [moonAngle] on [0, 360).
    public static func phaseFromMoonAngle(_ angleDegrees: Double, _ north: Bool) -> Double {
        let phase = north ? -90.0 - angleDegrees : angleDegrees + 90.0
        return (phase.truncatingRemainder(dividingBy: 360.0) + 360.0).truncatingRemainder(dividingBy: 360.0)
    }

    /// The annual dial as seen from the Earth camera: the Earth sits Unity's .5 system radius from the Sun.
    public static let geocentricSunDistance = earthOrbit * earthCameraZoom

    /// [minThickness] lets a band grow past Unity's proportion so its label stays legible.
    public static func yearEventBand(_ annualRadius: Double, _ calendarIndex: Int, minThickness: Double = 0) -> EventBand {
        let earthDialRadius = annualRadius * 0.4
        let thickness = max(earthDialRadius * 0.1166, minThickness)
        let outer = annualRadius - earthDialRadius * 0.0166 - Double(max(calendarIndex, 0)) * thickness
        return EventBand(outer - thickness / 2, thickness)
    }

    public static func dayEventBand(_ hourRadius: Double, _ calendarIndex: Int, minThickness: Double = 0) -> EventBand {
        let thickness = max(hourRadius * 0.1166, minThickness)
        let outer = hourRadius - hourRadius * 0.0166 - Double(max(calendarIndex, 0)) * thickness
        return EventBand(outer - thickness / 2, thickness)
    }

    /// How much of the camera zoom the distant star field shows: a little parallax sells the flight.
    public static let skyParallax = 0.35

    public struct EarthFlightFrame: Hashable, Sendable {
        public let cameraScale: Double
        public let earthSystemScale: Double
        public let skyScale: Double

        public init(_ cameraScale: Double, _ earthSystemScale: Double, _ skyScale: Double) {
            self.cameraScale = cameraScale
            self.earthSystemScale = earthSystemScale
            self.skyScale = skyScale
        }
    }

    /// Camera for the flight from the Sun-centred dial to the Earth. Scales interpolate
    /// geometrically, so the zoom feels like constant forward motion and the Earth swells like an
    /// approaching body, the way a fly-in from space looks (deliberately not to scale).
    public static func earthFlightFrame(_ progress: Double) -> EarthFlightFrame {
        let p = min(max(progress, 0), 1)
        return EarthFlightFrame(
            pow(earthCameraZoom, p), // cameraScale
            pow(heliocentricEarthRadius / earthRadius, 1 - p), // earthSystemScale
            pow(earthCameraZoom, p * skyParallax) // skyScale
        )
    }
}
