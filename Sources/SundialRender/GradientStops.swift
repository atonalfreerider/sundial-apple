import Foundation

/// Android interpolates gradient colours premultiplied (its Shader passes Skia
/// kInterpolateColorsInPremul_Flag), so a fade to Color.TRANSPARENT keeps its hue as it thins
/// out. SVG renderers and Core Graphics interpolate straight colour, which darkens that fade
/// toward black: a planet's aura comes out dimmer and smaller. These stops give Android's result
/// under straight interpolation, for backends that cannot interpolate premultiplied.
public enum GradientStops {
    /// Sub-stops per segment whose alpha and colour both change: exact at the stops, and within
    /// about one 8-bit step of the premultiplied colour between them.
    static let steps = 16

    /// [colors] at [positions] (evenly spread when nil, as on Android), rewritten so that straight
    /// interpolation between the returned stops matches premultiplied interpolation between the
    /// given ones: a transparent stop takes its neighbour's colour (split in two at the same
    /// offset when its neighbours differ), and a segment that changes both alpha and colour gains
    /// intermediate stops.
    public static func premultiplied(_ colors: [ARGB], _ positions: [Double]?) -> (colors: [ARGB], positions: [Double]) {
        let count = colors.count
        let even: (Int) -> Double = { count > 1 ? Double($0) / Double(count - 1) : 0 }
        let offsets = colors.indices.map { index in
            positions.flatMap { index < $0.count ? $0[index] : nil } ?? even(index)
        }
        guard count >= 2 else { return (colors, offsets) }
        var outColors: [ARGB] = []
        var outPositions: [Double] = []
        func append(_ color: ARGB, _ position: Double) {
            if outColors.last == color && outPositions.last == position { return }
            outColors.append(color)
            outPositions.append(position)
        }
        for index in 0..<(count - 1) {
            var start = colors[index], end = colors[index + 1]
            let from = offsets[index], to = offsets[index + 1]
            let startAlpha = Colors.alpha(start), endAlpha = Colors.alpha(end)
            if startAlpha == 0 && endAlpha != 0 { start = end & 0x00FF_FFFF }
            if endAlpha == 0 && startAlpha != 0 { end = start & 0x00FF_FFFF }
            append(start, from)
            if startAlpha != endAlpha && startAlpha != 0 && endAlpha != 0 && start & 0x00FF_FFFF != end & 0x00FF_FFFF {
                for step in 1..<steps {
                    let t = Double(step) / Double(steps)
                    append(mix(start, end, t), from + (to - from) * t)
                }
            }
            append(end, to)
        }
        return (outColors, outPositions)
    }

    /// [start] to [end] at [t], interpolated premultiplied and returned straight.
    public static func mix(_ start: ARGB, _ end: ARGB, _ t: Double) -> ARGB {
        let a0 = Double(Colors.alpha(start)), a1 = Double(Colors.alpha(end))
        let alpha = a0 + (a1 - a0) * t
        guard alpha > 0 else { return 0 }
        func channel(_ c0: Int, _ c1: Int) -> Int {
            Int(((Double(c0) * a0 * (1 - t) + Double(c1) * a1 * t) / alpha).rounded())
        }
        return Colors.argb(Int(alpha.rounded()), channel(Colors.red(start), Colors.red(end)),
                           channel(Colors.green(start), Colors.green(end)), channel(Colors.blue(start), Colors.blue(end)))
    }
}
