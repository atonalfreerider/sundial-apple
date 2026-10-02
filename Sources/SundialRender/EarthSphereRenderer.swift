import Foundation

/// Small native software 3D renderer. Rays intersect a sphere, normals are lit by the Sun at the top
/// of the frame, and the equirectangular map is sampled after inverse axial/diurnal rotation.
///
/// The globe is always rendered at one fixed resolution and drawn scaled (with mipmaps), so the
/// tiny planet in the solar view, the full Earth view and every frame of the flight between them
/// share a single cached frame instead of re-rendering whenever the on-screen size changes.
///
/// The colour arithmetic stays in Float where the Kotlin uses Float, so the pixels match Android's.
public final class EarthSphereRenderer {
    private struct FrameKey: Equatable {
        let timeBucket: Int64
        let north: Bool
        let highlightOffsetMinutes: Int?
        let brass: Bool
    }

    private let source: PixelImage
    public let size: Int

    public init(source: PixelImage, size: Int = EarthSphereRenderer.defaultSize) {
        self.source = source
        self.size = size
    }

    /// The planet glyph (no zone strip) and the Earth view's globe (with it) are both on screen
    /// during the camera flight, so the cache holds a few variants rather than alternating between
    /// two full renders every frame.
    ///
    /// Least recently used first (an access-ordered LinkedHashMap that keeps three entries).
    private var frames: [(key: FrameKey, frame: PixelImage)] = []

    private lazy var texturePixels: [ARGB] = source.pixels

    /// Everything that depends only on the pixel position, not on time: the view ray, sunlight,
    /// atmospheric rim and antialiased edge.
    private final class SphereSamples {
        let index: [Int]
        let sx: [Double]
        let sy: [Double]
        let sz: [Double]
        let illumination: [Float]
        let atmosphere: [Float]
        let alpha: [Int]

        init(_ size: Int) {
            let center = Double(size - 1) / 2.0
            let radius = Double(size) * 0.485
            var indices: [Int] = []
            for py in 0..<size {
                for px in 0..<size {
                    let x = (Double(px) - center) / radius
                    let y = -(Double(py) - center) / radius
                    if x * x + y * y <= 1.0 { indices.append(py * size + px) }
                }
            }
            index = indices
            var sx = [Double](repeating: 0, count: index.count)
            var sy = [Double](repeating: 0, count: index.count)
            var sz = [Double](repeating: 0, count: index.count)
            var illumination = [Float](repeating: 0, count: index.count)
            var atmosphere = [Float](repeating: 0, count: index.count)
            var alpha = [Int](repeating: 0, count: index.count)
            for (i, pixel) in index.enumerated() {
                let x = (Double(pixel % size) - center) / radius
                let y = -(Double(pixel / size) - center) / radius
                let rr = x * x + y * y
                let z = sqrt(1.0 - rr)
                sx[i] = x
                sy[i] = y
                sz[i] = z
                // From the ecliptic pole, sunlight is in the screen plane. This produces the
                // required half-lit globe and a terminator through its center.
                illumination[i] = Float(EarthSphereRenderer.nightLight + min(max(y, 0.0), 1.0) *
                    (1.0 - EarthSphereRenderer.nightLight))
                atmosphere[i] = Float(Int(pow(1.0 - z, 2.6) * 72))
                alpha[i] = Int((1.0 - min(max((rr - 0.94) / 0.06, 0.0), 1.0)) * 255)
            }
            self.sx = sx
            self.sy = sy
            self.sz = sz
            self.illumination = illumination
            self.atmosphere = atmosphere
            self.alpha = alpha
        }
    }

    private lazy var samples = SphereSamples(size)

    /// The satellite texture has near-black oceans. Lift its photographic floor before lighting so
    /// every longitude still reads as Earth, while the terminator remains.
    private let lift: [Float] = (0..<256).map { Float(255.0 * pow(Double($0) / 255.0, 0.46)) }

    private lazy var land: [Bool] = texturePixels.map { pixel in
        let red = Int((pixel >> 16) & 0xFF), green = Int((pixel >> 8) & 0xFF), blue = Int(pixel & 0xFF)
        return !(blue - max(red, green) > 12 && red < 48)
    }

    private lazy var coast: [Bool] = {
        let w = source.width, h = source.height, reach = max(1, source.width / 1024), mask = land
        return mask.indices.map { i in
            let x = i % w, y = i / w, here = mask[i]
            return (y >= reach && mask[i - reach * w] != here) ||
                (y < h - reach && mask[i + reach * w] != here) ||
                mask[y * w + (x + reach) % w] != here ||
                mask[y * w + (x - reach + w) % w] != here
        }
    }()

    /// Renders the globe as Unity's Earth camera saw it: from the ecliptic pole with the Sun at the
    /// top. Solar noon faces the Sun, the axis keeps its fixed tilt in space (so it leans toward the
    /// Sun in June and away in December), and the surface turns with sidereal time.
    ///
    /// [highlightOffsetMinutes] paints Unity's red time-zone strip along that zone's meridian band.
    public func render(_ instant: Date, _ north: Bool, _ highlightOffsetMinutes: Int?, brass: Bool = false) -> PixelImage {
        let key = FrameKey(timeBucket: instant.epochSecond / 30, north: north,
                           highlightOffsetMinutes: highlightOffsetMinutes, brass: brass)
        if let hit = frames.firstIndex(where: { $0.key == key }) {
            let entry = frames.remove(at: hit)
            frames.append(entry)
            return entry.frame
        }
        let output = renderFrame(
            Astronomy.greenwichMeanSiderealDegrees(instant), Zodiac.sunLongitude(instant), north,
            highlightOffsetMinutes, true, brass
        )
        frames.append((key: key, frame: output))
        if frames.count > 3 { frames.removeFirst() }
        return output
    }

    /// Kotlin's `highlightOffsetMinutes: Int? = null` default, for calls that omit or label it.
    public func render(_ instant: Date, _ north: Bool, highlightOffsetMinutes: Int? = nil,
                       brass: Bool = false) -> PixelImage {
        render(instant, north, highlightOffsetMinutes, brass: brass)
    }

    /// The globe's surface without sunlight, turned [siderealDegrees] and oriented like the solar
    /// view's dial (ecliptic longitude L at canvas angle 180° − L). The watch face turns the Earth
    /// by choosing one of these frames and lays [renderNightShade] over it toward the Sun.
    public func renderSurface(_ siderealDegrees: Double) -> PixelImage {
        // With the Sun at longitude 270° the Sun-up frame is already the dial's orientation.
        renderFrame(siderealDegrees, 270.0, true, nil, false)
    }

    /// The night side as a black veil in Sun-up coordinates: [render]'s lighting, apart from the surface.
    public func renderNightShade() -> PixelImage {
        let s = samples
        var pixels = [ARGB](repeating: 0, count: size * size)
        for i in s.index.indices {
            pixels[s.index[i]] = ARGB(min(max(Int((1 - s.illumination[i]) * Float(s.alpha[i])), 0), 255)) << 24
        }
        return PixelImage(width: size, height: size, pixels: pixels)
    }

    private func renderFrame(
        _ siderealDegrees: Double,
        _ sunLongitudeDegrees: Double,
        _ north: Bool,
        _ highlightOffsetMinutes: Int?,
        _ lit: Bool,
        _ brass: Bool = false
    ) -> PixelImage {
        let s = samples
        var pixels = [ARGB](repeating: 0, count: size * size)
        let texture = texturePixels
        let textureWidth = source.width
        let textureHeight = source.height
        // Math.toRadians: degrees × (π / 180).
        let sidereal = siderealDegrees * (Double.pi / 180)
        let sunLongitude = sunLongitudeDegrees * (Double.pi / 180)
        let highlightCenter = highlightOffsetMinutes.map { Double($0) / 4.0 * (Double.pi / 180) }
        let highlightHalfWidth = 7.5 * (Double.pi / 180)
        // Inlined EarthOrientation.screenToEquatorial: the per-pixel path must not allocate.
        let sinSun = sin(sunLongitude)
        let cosSun = cos(sunLongitude)
        let sinObliquity = sin(EarthOrientation.obliquityDegrees * (Double.pi / 180))
        let cosObliquity = cos(EarthOrientation.obliquityDegrees * (Double.pi / 180))
        let mirror = north ? 1.0 : -1.0
        let twoPi = 2.0 * Double.pi
        let landMask = brass ? land : nil
        let coastMask = brass ? coast : nil
        let lineWidth = (1.5 * 57.3 / (Double(size) * 0.485)) * .pi / 180
        let step = 15.0 * .pi / 180

        for i in s.index.indices {
            let right = s.sx[i] * mirror
            let up = s.sy[i]
            let eclX = right * sinSun + up * cosSun
            let eclY = -right * cosSun + up * sinSun
            let eclZ = s.sz[i] * mirror
            let eqY = eclY * cosObliquity - eclZ * sinObliquity
            let eqZ = eclY * sinObliquity + eclZ * cosObliquity
            let longitude = atan2(eqY, eclX) - sidereal
            let latitude = asin(min(max(eqZ, -1.0), 1.0))
            let turns = longitude / twoPi
            let wrapped = turns - floor(turns + 0.5)
            let u = floorMod(Int((wrapped + 0.5) * Double(textureWidth)), textureWidth)
            let v = min(max(Int((0.5 - latitude / Double.pi) * Double(textureHeight - 1)), 0), textureHeight - 1)
            let sample = texture[v * textureWidth + u]

            let light: Float = lit ? s.illumination[i] : 1
            if let landMask, let coastMask {
                let texel = v * textureWidth + u
                func nearLine(_ angle: Double, _ width: Double) -> Bool {
                    abs(angle - step * floor(angle / step + 0.5)) < width
                }
                let width = lineWidth / max(s.sz[i], 0.25)
                let majorLatitude = abs(latitude) < width * 1.8
                let majorLongitude = abs(wrapped * twoPi) < width * 1.8
                let etched = coastMask[texel] || majorLatitude || majorLongitude || nearLine(latitude, width) ||
                    (abs(latitude) < 80 * .pi / 180 && nearLine(wrapped * twoPi, width / max(cos(latitude), 0.2)))
                pixels[s.index[i]] = ARGB(s.alpha[i]) << 24 |
                    brassPixel(landMask[texel], etched, light, s.sx[i] * mirror, s.sy[i], s.sz[i],
                               highlightCenter, longitude, highlightHalfWidth)
                continue
            }
            let glow = s.atmosphere[i]
            var red = lift[Int((sample >> 16) & 0xFF)] * light + 10 + glow * 0.32
            var green = lift[Int((sample >> 8) & 0xFF)] * light + 14 + glow * 0.52
            var blue = lift[Int(sample & 0xFF)] * light + 20 + glow
            if let highlightCenter {
                let delta = (longitude - highlightCenter) - twoPi * floor((longitude - highlightCenter) / twoPi + 0.5)
                if abs(delta) <= highlightHalfWidth {
                    let strength: Float = 0.62 * (0.45 + light * 0.55)
                    red = red * (1 - strength) + 235 * strength
                    green = green * (1 - strength) + 22 * strength
                    blue = blue * (1 - strength) + 30 * strength
                }
            }
            pixels[s.index[i]] = ARGB(s.alpha[i]) << 24 |
                ARGB(min(max(Int(red), 0), 255)) << 16 |
                ARGB(min(max(Int(green), 0), 255)) << 8 |
                ARGB(min(max(Int(blue), 0), 255))
        }

        // Never mutate a frame that may still be referenced by a recorded display list.
        // (Android also flags it for mipmaps; the Canvas backends filter scaled images themselves.)
        return PixelImage(width: size, height: size, pixels: pixels)
    }

    private func floorMod(_ value: Int, _ modulus: Int) -> Int { ((value % modulus) + modulus) % modulus }

    private func brassPixel(_ isLand: Bool, _ etched: Bool, _ light: Float, _ x: Double, _ y: Double,
                            _ z: Double, _ highlightCenter: Double?, _ longitude: Double,
                            _ highlightHalfWidth: Double) -> ARGB {
        var red: Float = isLand ? 207 : 244
        var green: Float = isLand ? 164 : 209
        var blue: Float = isLand ? 82 : 126
        let daylight = min(max((light - Float(Self.nightLight)) / Float(1 - Self.nightLight), 0), 1)
        let metalLight = 0.56 + daylight * 0.44
        let shade = metalLight * (0.86 + 0.14 * Float(z))
        let sheen = Float(pow(max(0, y * 0.55 + z * 0.55 - x * 0.2), 18) * 120)
        red = red * shade + sheen
        green = green * shade + sheen * 0.9
        blue = blue * shade + sheen * 0.6
        if let highlightCenter {
            let delta = (longitude - highlightCenter) - 2 * .pi * floor((longitude - highlightCenter) / (2 * .pi) + 0.5)
            if abs(delta) <= highlightHalfWidth {
                red = red * 0.45 + 200 * 0.55
                green = green * 0.45 + 30 * 0.55
                blue = blue * 0.45 + 28 * 0.55
            }
        }
        if etched {
            red = red * 0.24 + 69 * 0.76 * metalLight
            green = green * 0.24 + 44 * 0.76 * metalLight
            blue = blue * 0.24 + 14 * 0.76 * metalLight
        }
        return ARGB(min(max(Int(red), 0), 255)) << 16 |
            ARGB(min(max(Int(green), 0), 255)) << 8 |
            ARGB(min(max(Int(blue), 0), 255))
    }

    /// Enough for the Earth view's full-width globe on a phone.
    public static let defaultSize = 512
    private static let nightLight = 0.32
}
