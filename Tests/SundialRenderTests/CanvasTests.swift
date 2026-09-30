import XCTest
@testable import SundialRender

final class CanvasTests: XCTestCase {
    // MARK: Gradients interpolate premultiplied, as Android's do

    /// Straight interpolation between the rewritten stops, as SVG and Core Graphics draw them.
    private func straight(_ stops: (colors: [ARGB], positions: [Double]), at t: Double) -> (Double, Double, Double, Double) {
        func parts(_ c: ARGB) -> (Double, Double, Double, Double) {
            (Double(Colors.alpha(c)), Double(Colors.red(c)), Double(Colors.green(c)), Double(Colors.blue(c)))
        }
        let p = stops.positions, c = stops.colors
        if t <= p[0] { return parts(c[0]) }
        // The last stop at or before t, so a hard stop takes its later colour.
        var i = 0
        while i + 1 < p.count && p[i + 1] <= t { i += 1 }
        if i == p.count - 1 { return parts(c[i]) }
        let f = (t - p[i]) / (p[i + 1] - p[i])
        let a = parts(c[i]), b = parts(c[i + 1])
        return (a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f, a.2 + (b.2 - a.2) * f, a.3 + (b.3 - a.3) * f)
    }

    func testFadeToTransparentKeepsItsHue() {
        // A planet's aura: colour at 125 and 45 alpha fading to Color.TRANSPARENT (black, alpha 0).
        let color: ARGB = 0x00FF_DA93
        let stops = GradientStops.premultiplied([color | 125 << 24, color | 45 << 24, Colors.transparent], [0, 0.38, 1])
        XCTAssertEqual(stops.colors.last, color, "the transparent end takes the colour of its neighbour")
        let mid = straight(stops, at: 0.69)
        XCTAssertEqual(mid.0, 22.5, accuracy: 0.01)
        XCTAssertEqual(mid.1, 255)
        XCTAssertEqual(mid.2, 218)
        XCTAssertEqual(mid.3, 147)
    }

    func testTransparentStopBetweenColoursIsSplit() {
        let stops = GradientStops.premultiplied([0xFFFF_0000, 0x0000_0000, 0xFF00_00FF], nil)
        XCTAssertEqual(stops.positions, [0, 0.5, 0.5, 1])
        XCTAssertEqual(stops.colors, [0xFFFF_0000, 0x00FF_0000, 0x0000_00FF, 0xFF00_00FF])
    }

    func testChangingAlphaAndColourMatchesPremultipliedMix() {
        let start: ARGB = 0xFFFF_0000, end: ARGB = 0x4000_00FF
        let stops = GradientStops.premultiplied([start, end], nil)
        for step in 0...20 {
            let t = Double(step) / 20
            let expected = GradientStops.mix(start, end, t)
            let got = straight(stops, at: t)
            // What shows is the premultiplied colour: within about one 8-bit step of Android's.
            let alpha = Double(Colors.alpha(expected))
            XCTAssertEqual(got.0, alpha, accuracy: 1, "alpha at \(t)")
            XCTAssertEqual(got.1 * got.0 / 255, Double(Colors.red(expected)) * alpha / 255, accuracy: 1, "red at \(t)")
            XCTAssertEqual(got.3 * got.0 / 255, Double(Colors.blue(expected)) * alpha / 255, accuracy: 1, "blue at \(t)")
        }
    }

    func testPlainGradientsAreUnchanged() {
        let colors: [ARGB] = [0xFF10_2030, 0xFF40_5060, 0x8040_5060]
        let stops = GradientStops.premultiplied(colors, [0, 0.3, 1])
        XCTAssertEqual(stops.colors, colors)
        XCTAssertEqual(stops.positions, [0, 0.3, 1])
    }

    func testSweepFadeToTransparentKeepsItsHue() {
        // Half way round a sweep from opaque red to transparent black: red at half alpha.
        let image = SweepGradientImages.image(innerRadius: 0, outerRadius: 50, colors: [0xFFFF_0000, 0x0000_0000],
                                              positions: nil, scale: 1)
        // Straight left of the centre is 180°, half way through the sweep.
        let y = image.height / 2, x = image.width / 2 - 20
        let pixel = image.pixels[y * image.width + x]
        XCTAssertEqual(Colors.red(pixel), 255)
        XCTAssertEqual(Colors.alpha(pixel), 127, accuracy: 2)
    }

    /// The sweep ring as it was rendered before the stop search and row spans: every pixel of
    /// the square, stops scanned from the first.
    private func referenceSweep(inner: Double, outer: Double, colors: [ARGB], positions: [Double]?,
                                scale: Double) -> [ARGB] {
        let stops = positions ?? colors.indices.map { Double($0) / Double(colors.count - 1) }
        func parts(_ c: ARGB) -> (Double, Double, Double, Double) {
            (Double(Colors.alpha(c)), Double(Colors.red(c)), Double(Colors.green(c)), Double(Colors.blue(c)))
        }
        func colorAt(_ t: Double) -> (Double, Double, Double, Double) {
            if t <= stops[0] { return parts(colors[0]) }
            for i in 1..<stops.count where t <= stops[i] {
                let span = stops[i] - stops[i - 1]
                let f = span > 0 ? (t - stops[i - 1]) / span : 0
                let a = parts(colors[i - 1]), b = parts(colors[i])
                let alpha = a.0 + (b.0 - a.0) * f
                guard alpha > 0 else { return (0, 0, 0, 0) }
                func channel(_ c0: Double, _ c1: Double) -> Double { (c0 * a.0 * (1 - f) + c1 * b.0 * f) / alpha }
                return (alpha, channel(a.1, b.1), channel(a.2, b.2), channel(a.3, b.3))
            }
            return parts(colors[colors.count - 1])
        }
        let half = outer + 1 / scale
        let size = max(2, Int((2 * half * scale).rounded(.up)))
        let unit = 2 * half / Double(size)
        var pixels = [ARGB](repeating: 0, count: size * size)
        for py in 0..<size {
            let y = (Double(py) + 0.5) * unit - half
            for px in 0..<size {
                let x = (Double(px) + 0.5) * unit - half
                let distance = (x * x + y * y).squareRoot()
                var coverage = min(1, max(0, (outer - distance) / unit + 0.5))
                if inner > 0 { coverage *= min(1, max(0, (distance - inner) / unit + 0.5)) }
                if coverage <= 0 { continue }
                var degrees = atan2(y, x) * 180 / .pi
                if degrees < 0 { degrees += 360 }
                let c = colorAt(degrees / 360)
                pixels[py * size + px] = Colors.argb(Int((c.0 * coverage).rounded()), Int(c.1.rounded()),
                                                     Int(c.2.rounded()), Int(c.3.rounded()))
            }
        }
        return pixels
    }

    func testFasterSweepRenderIsPixelIdentical() {
        // 121 stops with repeated positions (hard edges), as the season shaders have.
        var colors: [ARGB] = []
        var positions: [Double] = []
        for i in 0..<121 {
            colors.append(Colors.argb(40 + i % 200, (i * 37) % 256, (i * 91) % 256, (i * 13) % 256))
            positions.append(Double(i / 2 * 2) / 120)
        }
        for (inner, outer, scale) in [(0.0, 40.0, 1.0), (33.5, 41.25, 2.75), (10.0, 12.0, 0.25)] {
            let image = SweepGradientImages.image(innerRadius: inner, outerRadius: outer, colors: colors,
                                                  positions: positions, scale: scale)
            XCTAssertEqual(image.pixels, referenceSweep(inner: inner, outer: outer, colors: colors, positions: positions,
                                                        scale: scale), "\(inner) \(outer) \(scale)")
        }
        let even = SweepGradientImages.image(innerRadius: 5, outerRadius: 30, colors: [0xFFFF_0000, 0x0000_00FF, 0xFF00_FF00],
                                             positions: nil, scale: 1.5)
        XCTAssertEqual(even.pixels, referenceSweep(inner: 5, outer: 30, colors: [0xFFFF_0000, 0x0000_00FF, 0xFF00_FF00],
                                                   positions: nil, scale: 1.5))
    }

    func testMovingCameraReusesTheNearestCachedScale() {
        let colors: [ARGB] = [0xFF12_3456, 0xFF65_4321]
        let resting = SweepGradientImages.image(innerRadius: 7, outerRadius: 9, colors: colors, positions: nil, scale: 3)
        let moving = SweepGradientImages.image(innerRadius: 7, outerRadius: 9, colors: colors, positions: nil, scale: 4.25,
                                               reuseAnyScale: true)
        XCTAssertTrue(moving.image === resting)
        XCTAssertEqual(moving.scale, 3)
        let atRest = SweepGradientImages.image(innerRadius: 7, outerRadius: 9, colors: colors, positions: nil, scale: 4.25,
                                               reuseAnyScale: false)
        XCTAssertFalse(atRest.image === resting)
        XCTAssertEqual(atRest.scale, 4.25)
    }

    // MARK: Paths

    func testRoundRectRadiiScaleTogetherAsSkiaDoes() {
        // 100 × 20 with 15 × 15 corners: both radii become 10, a pill with round ends.
        var path = Path()
        path.addRoundRect(Rect(0, 0, 100, 20), 15, 15)
        guard case .move(let start)? = path.elements.first else { return XCTFail("no contour") }
        XCTAssertEqual(start.x, 10, accuracy: 1e-12)
        XCTAssertEqual(SVGBounds.of(path).bottom, 20, accuracy: 1e-9)
        // Radii that fit are kept; negative ones give a plain rectangle.
        var fits = Path()
        fits.addRoundRect(Rect(0, 0, 100, 40), 15, 5)
        guard case .move(let corner)? = fits.elements.first else { return XCTFail("no contour") }
        XCTAssertEqual(corner.x, 15)
        var square = Path()
        square.addRoundRect(Rect(0, 0, 10, 10), -3, -3)
        XCTAssertEqual(square.elements.count, 5)
    }

    func testDrawArcFollowsHWUIForFullTurnsAndEmptyOvals() {
        final class Recorder: Canvas {
            var paths: [Path] = []
            let width = 10.0, height = 10.0
            var pixelScale: Double { 1 }
            var saveCount: Int { 1 }
            func save() -> Int { 1 }
            func saveLayer(alpha: Double) -> Int { 1 }
            func restore() {}
            func restore(toCount: Int) {}
            func translate(_ dx: Double, _ dy: Double) {}
            func rotate(_ degrees: Double) {}
            func scale(_ sx: Double, _ sy: Double) {}
            func concat(_ transform: SundialRender.AffineTransform) {}
            func clip(_ path: Path) {}
            func drawPath(_ path: Path, _ paint: Paint) { paths.append(path) }
            func drawText(_ text: String, _ x: Double, _ y: Double, _ paint: Paint) {}
            func drawTextShadow(_ text: String, _ x: Double, _ y: Double, _ paint: Paint) {}
            func drawImage(_ image: PixelImage, _ rect: Rect, alpha: Double) {}
            func drawColor(_ color: ARGB) {}
            func measureText(_ text: String, _ paint: Paint) -> Double { 0 }
            func textAdvance(_ text: String, _ paint: Paint) -> Double { 0 }
            func fontMetrics(_ paint: Paint) -> FontMetrics { FontMetrics(ascent: 0, descent: 0) }
        }
        let canvas = Recorder()
        // Nothing for an empty or inverted oval, or a zero sweep.
        canvas.drawArc(Rect(0, 0, 0, 10), 0, 90, false, Paint())
        canvas.drawArc(Rect(10, 0, 0, 10), 0, 90, false, Paint())
        canvas.drawArc(Rect(0, 0, 10, 10), 30, 0, true, Paint())
        XCTAssertTrue(canvas.paths.isEmpty)
        // A full turn or more is the closed oval, without the centre, even from an inverted rect.
        canvas.drawArc(Rect(10, 10, 0, 0), 45, -400, true, Paint())
        var oval = Path()
        oval.addOval(Rect(0, 0, 10, 10))
        XCTAssertEqual(canvas.paths.count, 1)
        XCTAssertEqual(String(describing: canvas.paths[0].elements), String(describing: oval.elements))
    }

    func testRewindResetsTheFillRule() {
        var path = Path()
        path.fillRule = .evenOdd
        path.addCircle(0, 0, 5)
        path.rewind()
        XCTAssertTrue(path.isEmpty)
        XCTAssertEqual(path.fillRule, .winding)
    }

    // MARK: ColorFilterCanvas

    func testFilteredImagesDoNotOutliveTheirSources() {
        final class Sink: Canvas {
            var images: [PixelImage] = []
            let width = 10.0, height = 10.0
            var pixelScale: Double { 1 }
            var saveCount: Int { 1 }
            func save() -> Int { 1 }
            func saveLayer(alpha: Double) -> Int { 1 }
            func restore() {}
            func restore(toCount: Int) {}
            func translate(_ dx: Double, _ dy: Double) {}
            func rotate(_ degrees: Double) {}
            func scale(_ sx: Double, _ sy: Double) {}
            func concat(_ transform: SundialRender.AffineTransform) {}
            func clip(_ path: Path) {}
            func drawPath(_ path: Path, _ paint: Paint) {}
            func drawText(_ text: String, _ x: Double, _ y: Double, _ paint: Paint) {}
            func drawTextShadow(_ text: String, _ x: Double, _ y: Double, _ paint: Paint) {}
            func drawImage(_ image: PixelImage, _ rect: Rect, alpha: Double) { images.append(image) }
            func drawColor(_ color: ARGB) {}
            func measureText(_ text: String, _ paint: Paint) -> Double { 0 }
            func textAdvance(_ text: String, _ paint: Paint) -> Double { 0 }
            func fontMetrics(_ paint: Paint) -> FontMetrics { FontMetrics(ascent: 0, descent: 0) }
        }
        let sink = Sink()
        weak var filtered: PixelImage?
        do {
            let source = PixelImage(width: 1, height: 1, pixels: [0xFFFF_FFFF])
            ColorFilterCanvas(sink, filter: .ambientGrey).drawImage(source, Rect(0, 0, 1, 1), alpha: 1)
            filtered = sink.images.first
            sink.images.removeAll()
            XCTAssertNotNil(filtered)
        }
        // The source is gone: the next lookup prunes its filtered copy.
        ColorFilterCanvas(sink, filter: .ambientGrey).drawImage(PixelImage(width: 1, height: 1), Rect(0, 0, 1, 1), alpha: 1)
        sink.images.removeAll()
        XCTAssertNil(filtered)
        FilteredImages.removeAll()
    }
}

/// The bounding box of a path's points.
private enum SVGBounds {
    static func of(_ path: Path) -> Rect {
        var box = Rect(.infinity, .infinity, -.infinity, -.infinity)
        for element in path.elements {
            switch element {
            case .move(let p), .line(let p), .cubic(_, _, let p):
                box.left = min(box.left, p.x); box.top = min(box.top, p.y)
                box.right = max(box.right, p.x); box.bottom = max(box.bottom, p.y)
            case .close: break
            }
        }
        return box
    }
}
