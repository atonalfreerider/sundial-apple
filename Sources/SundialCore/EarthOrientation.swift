import Foundation

/// Earth seen from the ecliptic pole with the Sun at the top of the screen, as in Unity's Earth
/// camera. The rotation axis is fixed in space (tilted toward ecliptic longitude 90°), so relative to
/// the Sun it swings around with the seasons: toward the Sun at the June solstice, away in December.
public enum EarthOrientation {
    public static let obliquityDegrees = 23.43928

    /// Screen position (x right, y up, in globe radii) of the visible geographic pole: the north pole
    /// from the north ecliptic view, the south pole from the mirrored southern view.
    public static func projectedGeographicPole(_ north: Bool, _ sunLongitudeDegrees: Double) -> (Double, Double) {
        let tilt = sin(Math.toRadians(obliquityDegrees))
        let lambda = Math.toRadians(sunLongitudeDegrees)
        let x = -tilt * cos(lambda)
        let y = tilt * sin(lambda)
        return (x, north ? y : -y)
    }

    /// Maps a unit vector in screen space (x right, y up toward the Sun, z toward the viewer) to the
    /// equatorial frame of date. Returns (x, y, z) with z toward the north celestial pole.
    public static func screenToEquatorial(
        _ sx: Double,
        _ sy: Double,
        _ sz: Double,
        _ sunLongitudeDegrees: Double,
        _ north: Bool
    ) -> (x: Double, y: Double, z: Double) {
        let lambda = Math.toRadians(sunLongitudeDegrees)
        let sinL = sin(lambda)
        let cosL = cos(lambda)
        // Screen right is 90° clockwise of the Sun (north view); the southern view is its mirror
        // image seen from below the ecliptic.
        let right = north ? sx : -sx
        let toward = north ? sz : -sz
        let eclX = right * sinL + sy * cosL
        let eclY = -right * cosL + sy * sinL
        let eclZ = toward
        let obliquity = Math.toRadians(obliquityDegrees)
        return (
            eclX,
            eclY * cos(obliquity) - eclZ * sin(obliquity),
            eclY * sin(obliquity) + eclZ * cos(obliquity)
        )
    }
}
