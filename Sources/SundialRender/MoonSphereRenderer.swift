import Foundation

/// Renders the Moon as seen from solar north. Sunlight therefore travels in the screen plane:
/// the visible disk is divided by a central terminator whose bright side always faces the Sun.
public final class MoonSphereRenderer {
    private var cachedSize = 0
    private var cachedLightBucket = Int.min
    private var cachedBrass = false
    private var cached: PixelImage?
    private var retainedFrames: [PixelImage] = []

    public init() {}

    public func render(_ size: Int, _ lightDx: Double, _ lightDy: Double, brass: Bool = false) -> PixelImage {
        let safeSize = min(max(size, 24), 180)
        let length = max(hypot(lightDx, lightDy), 0.001)
        let lx = lightDx / length
        let ly = lightDy / length
        // Math.toDegrees: radians × (180 / π), then toInt() truncates toward zero.
        let lightBucket = Int(atan2(ly, lx) * (180 / Double.pi))
        if let cached {
            if cachedSize == safeSize && cachedLightBucket == lightBucket && cachedBrass == brass { return cached }
        }

        let bucketAngle = Double(lightBucket) * (Double.pi / 180)
        let bucketLx = cos(bucketAngle)
        let bucketLy = sin(bucketAngle)
        var pixels = [ARGB](repeating: 0, count: safeSize * safeSize)
        let center = Double(safeSize - 1) / 2.0
        let radius = Double(safeSize) * 0.485

        for py in 0..<safeSize {
            let sy = (Double(py) - center) / radius
            for px in 0..<safeSize {
                let sx = (Double(px) - center) / radius
                let rr = sx * sx + sy * sy
                if rr > 1.0 { continue }
                let sz = sqrt(1.0 - rr)
                let diffuse = max(0.0, sx * bucketLx + sy * bucketLy)
                let maria = lunarMaria(sx, sy)
                let surface = min(max(1.0 - maria * 0.25, 0.68), 1.0)
                let illumination = (Self.nightLight + diffuse * (1 - Self.nightLight)) * (0.78 + sz * 0.22)
                let edgeAlpha = Int((1.0 - min(max((rr - 0.93) / 0.07, 0.0), 1.0)) * 255)
                if brass {
                    pixels[py * safeSize + px] = brassPixel(sx, sy, sz, maria, illumination, safeSize, edgeAlpha)
                } else {
                    let red = min(max(Int(252 * surface * illumination), 0), 255)
                    let green = min(max(Int(248 * surface * illumination), 0), 255)
                    let blue = min(max(Int(230 * surface * illumination), 0), 255)
                    pixels[py * safeSize + px] = Colors.argb(edgeAlpha, red, green, blue)
                }
            }
        }
        let output = PixelImage(width: safeSize, height: safeSize, pixels: pixels)
        if let cached {
            retainedFrames.append(cached)
            while retainedFrames.count > 8 { retainedFrames.removeFirst() }
        }
        cached = output
        cachedSize = safeSize
        cachedLightBucket = lightBucket
        cachedBrass = brass
        return output
    }

    private func brassPixel(_ x: Double, _ y: Double, _ z: Double, _ maria: Double,
                            _ light: Double, _ size: Int, _ alpha: Int) -> ARGB {
        let latitude = asin(-y) * 180 / .pi
        let longitude = atan2(x, z) * 180 / .pi
        let width = 1.6 * 57.3 / (Double(size) * 0.485) / max(z, 0.25)
        func nearLine(_ angle: Double) -> Bool { abs(angle - 30 * round(angle / 30)) < width }
        let phase = (x + y) * Double(size) * 0.22
        let hatched = maria > 0.25 && phase - floor(phase) < 0.42
        let etched = nearLine(latitude) || (abs(latitude) < 80 && nearLine(longitude)) || hatched
        let sheen = pow(max(0, -y * 0.5 + z * 0.6 - x * 0.2), 16) * 92
        let daylight = min(max((light - Self.nightLight) / (1 - Self.nightLight), 0), 1)
        let metalLight = 0.56 + daylight * 0.44
        let shade = metalLight * (0.86 + z * 0.14)
        var red = 244 * shade + sheen, green = 207 * shade + sheen * 0.9, blue = 121 * shade + sheen * 0.6
        if etched {
            red = red * 0.24 + 69 * 0.76 * metalLight
            green = green * 0.24 + 44 * 0.76 * metalLight
            blue = blue * 0.24 + 14 * 0.76 * metalLight
        }
        return Colors.argb(alpha, min(max(Int(red), 0), 255), min(max(Int(green), 0), 255),
                           min(max(Int(blue), 0), 255))
    }

    private static let nightLight = 0.26

    private func lunarMaria(_ x: Double, _ y: Double) -> Double {
        func crater(_ cx: Double, _ cy: Double, _ radius: Double) -> Double {
            let distanceSquared = pow(x - cx, 2) + pow(y - cy, 2)
            return min(max(1.0 - distanceSquared / (radius * radius), 0.0), 1.0)
        }
        return max(
            crater(-0.28, -0.18, 0.22),
            crater(0.24, 0.22, 0.16),
            crater(0.04, -0.41, 0.11),
            crater(0.39, -0.18, 0.09)
        )
    }
}
