import Foundation

/// Renders the Moon as seen from solar north. Sunlight therefore travels in the screen plane:
/// the visible disk is divided by a central terminator whose bright side always faces the Sun.
public final class MoonSphereRenderer {
    private var cachedSize = 0
    private var cachedLightBucket = Int.min
    private var cached: PixelImage?
    private var retainedFrames: [PixelImage] = []

    public init() {}

    public func render(_ size: Int, _ lightDx: Double, _ lightDy: Double) -> PixelImage {
        let safeSize = min(max(size, 24), 180)
        let length = max(hypot(lightDx, lightDy), 0.001)
        let lx = lightDx / length
        let ly = lightDy / length
        // Math.toDegrees: radians × (180 / π), then toInt() truncates toward zero.
        let lightBucket = Int(atan2(ly, lx) * (180 / Double.pi))
        if let cached {
            if cachedSize == safeSize && cachedLightBucket == lightBucket { return cached }
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
                let illumination = (0.085 + diffuse * 0.915) * (0.72 + sz * 0.28)
                let edgeAlpha = Int((1.0 - min(max((rr - 0.93) / 0.07, 0.0), 1.0)) * 255)
                let red = min(max(Int(238 * surface * illumination), 0), 255)
                let green = min(max(Int(234 * surface * illumination), 0), 255)
                let blue = min(max(Int(215 * surface * illumination), 0), 255)
                pixels[py * safeSize + px] = Colors.argb(edgeAlpha, red, green, blue)
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
        return output
    }

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
