import XCTest
@testable import SundialRender

/// A Canvas that only records what it is asked to draw.
private final class RecordingCanvas: Canvas {
    enum Call {
        case path(Path, Paint)
        case text(String, Paint)
        case shadow(String, Paint)
        case image(PixelImage, Rect, Double)
        case color(ARGB)
    }

    var calls: [Call] = []
    var transforms: [String] = []
    private var depth = 1

    let width = 400.0
    let height = 800.0
    var pixelScale: Double { 2 }
    var saveCount: Int { depth }

    func save() -> Int { depth += 1; return depth - 1 }
    func saveLayer(alpha: Double) -> Int { transforms.append("layer \(alpha)"); return save() }
    func restore() { depth -= 1 }
    func restore(toCount: Int) { depth = toCount }
    func translate(_ dx: Double, _ dy: Double) { transforms.append("translate \(dx) \(dy)") }
    func rotate(_ degrees: Double) { transforms.append("rotate \(degrees)") }
    func scale(_ sx: Double, _ sy: Double) { transforms.append("scale \(sx) \(sy)") }
    func concat(_ transform: SundialRender.AffineTransform) { transforms.append("concat") }
    func clip(_ path: Path) { transforms.append("clip") }
    func drawPath(_ path: Path, _ paint: Paint) { calls.append(.path(path, paint)) }
    func drawText(_ text: String, _ x: Double, _ y: Double, _ paint: Paint) { calls.append(.text(text, paint)) }
    func drawImage(_ image: PixelImage, _ rect: Rect, alpha: Double) { calls.append(.image(image, rect, alpha)) }
    func drawColor(_ color: ARGB) { calls.append(.color(color)) }
    func drawTextShadow(_ text: String, _ x: Double, _ y: Double, _ paint: Paint) { calls.append(.shadow(text, paint)) }
    func measureText(_ text: String, _ paint: Paint) -> Double { Double(text.count) * paint.textSize / 2 }
    func textAdvance(_ text: String, _ paint: Paint) -> Double { Double(text.count) * paint.textSize / 2 }
    func fontMetrics(_ paint: Paint) -> FontMetrics { FontMetrics(ascent: -paint.textSize, descent: paint.textSize / 4) }

    var paints: [Paint] {
        calls.compactMap {
            switch $0 {
            case .path(_, let paint), .text(_, let paint): return paint
            default: return nil
            }
        }
    }
}

final class RenderersTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_010)  // on a 30-second boundary

    /// A uniform grey map, so only the lighting varies across the globe.
    private func uniformTexture() -> PixelImage {
        PixelImage(width: 64, height: 32, pixels: Array(repeating: 0xFF80_8080, count: 64 * 32))
    }

    private func pixel(_ image: PixelImage, _ x: Int, _ y: Int) -> ARGB { image.pixels[y * image.width + x] }

    private func brightness(_ color: ARGB) -> Int { Colors.red(color) + Colors.green(color) + Colors.blue(color) }

    // MARK: EarthSphereRenderer

    func testEarthFrameIsSquareWithTransparentCornersAndOpaqueCentre() {
        let renderer = EarthSphereRenderer(source: uniformTexture(), size: 128)
        let frame = renderer.render(t0, true, nil)
        XCTAssertEqual(frame.width, 128)
        XCTAssertEqual(frame.height, 128)
        XCTAssertEqual(frame.pixels.count, 128 * 128)
        for (x, y) in [(0, 0), (127, 0), (0, 127), (127, 127)] {
            XCTAssertEqual(pixel(frame, x, y), 0, "corner \(x),\(y)")
        }
        XCTAssertEqual(Colors.alpha(pixel(frame, 64, 64)), 255)
        XCTAssertEqual(EarthSphereRenderer.defaultSize, 512)
        XCTAssertEqual(EarthSphereRenderer(source: uniformTexture()).size, 512)
    }

    func testEarthIsLitFromTheTop() {
        let renderer = EarthSphereRenderer(source: uniformTexture(), size: 128)
        let frame = renderer.render(t0, true, nil)
        // The Sun is at the top of the frame: the day side is above the centre, night below.
        XCTAssertGreaterThan(brightness(pixel(frame, 64, 24)), brightness(pixel(frame, 64, 104)) + 150)
        // Without sunlight the uniform map is symmetric top to bottom.
        let surface = renderer.renderSurface(123.0)
        XCTAssertEqual(pixel(surface, 64, 24), pixel(surface, 64, 103))
    }

    func testEarthFramesAreCachedPerThirtySecondsInThreeEntries() {
        let renderer = EarthSphereRenderer(source: uniformTexture(), size: 64)
        let first = renderer.render(t0, true, nil)
        XCTAssertTrue(first === renderer.render(t0.addingTimeInterval(29), true, nil))
        XCTAssertTrue(first === renderer.render(t0, true, highlightOffsetMinutes: nil))
        XCTAssertTrue(first === renderer.render(t0, true))
        XCTAssertFalse(first === renderer.render(t0.addingTimeInterval(30), true, nil))
        // Three more variants push the first out of the cache.
        _ = renderer.render(t0, false, nil)
        _ = renderer.render(t0, true, 60)
        XCTAssertFalse(first === renderer.render(t0, true, nil))
    }

    func testTimeZoneHighlightPaintsRed() {
        let renderer = EarthSphereRenderer(source: uniformTexture(), size: 96)
        let plain = renderer.render(t0, true, nil)
        let reddest = (-12...14).map { hour -> Int in
            let frame = renderer.render(t0, true, hour * 60)
            return zip(frame.pixels, plain.pixels).filter { Colors.red($0) > Colors.red($1) + 40 }.count
        }
        XCTAssertTrue(reddest.allSatisfy { $0 > 0 })
    }

    func testNightShadeIsBlackAndDarkensTheBottom() {
        let renderer = EarthSphereRenderer(source: uniformTexture(), size: 128)
        let shade = renderer.renderNightShade()
        XCTAssertEqual(shade.width, 128)
        XCTAssertEqual(pixel(shade, 0, 0), 0)
        XCTAssertTrue(shade.pixels.allSatisfy { $0 & 0x00FF_FFFF == 0 })
        // (1 − 0.32) × 255 below the brighter night-side floor, nearly clear at the sub-solar point.
        XCTAssertEqual(Colors.alpha(pixel(shade, 64, 100)), 173)
        XCTAssertLessThan(Colors.alpha(pixel(shade, 64, 5)), 20)
    }

    // MARK: MoonSphereRenderer

    func testMoonSizeIsClampedWithTransparentCorners() {
        let renderer = MoonSphereRenderer()
        XCTAssertEqual(renderer.render(10, 1, 0).width, 24)
        XCTAssertEqual(renderer.render(400, 1, 0).height, 180)
        let moon = renderer.render(60, 1, 0)
        XCTAssertEqual(moon.width, 60)
        for (x, y) in [(0, 0), (59, 0), (0, 59), (59, 59)] {
            XCTAssertEqual(pixel(moon, x, y), 0)
        }
        XCTAssertEqual(Colors.alpha(pixel(moon, 30, 30)), 255)
    }

    func testMoonLitSideFacesTheLight() {
        let renderer = MoonSphereRenderer()
        let right = renderer.render(80, 5, 0)
        XCTAssertGreaterThan(brightness(pixel(right, 70, 40)), brightness(pixel(right, 10, 40)) + 200)
        // Light from above the screen (negative y).
        let up = renderer.render(80, 0, -5)
        XCTAssertGreaterThan(brightness(pixel(up, 40, 10)), brightness(pixel(up, 40, 70)) + 200)
    }

    func testMoonCachesTheLastFrameByDegree() {
        let renderer = MoonSphereRenderer()
        let a = renderer.render(64, 1, 0.001)
        XCTAssertTrue(a === renderer.render(64, 2, 0.002))
        XCTAssertFalse(a === renderer.render(64, 0, 1))
        XCTAssertFalse(a === renderer.render(64, 1, 0.001))
    }

    // MARK: PlanetSymbols

    func testSymbolsAreStrokedOnACopyOfThePaint() {
        let symbols = PlanetSymbols()
        let canvas = RecordingCanvas()
        let paint = Paint(color: 0xFFD3_DEE6)
        let counts: [(Astronomy.Body, Int)] = [(.mercury, 4), (.venus, 3), (.earth, 3), (.mars, 3)]
        for (body, count) in counts {
            canvas.calls.removeAll()
            symbols.draw(canvas, body, 50, 50, 10, paint)
            XCTAssertEqual(canvas.calls.count, count, "\(body)")
            for drawn in canvas.paints {
                XCTAssertEqual(drawn.style, .stroke)
                XCTAssertEqual(drawn.strokeCap, .round)
                XCTAssertEqual(drawn.strokeWidth, 1.1, accuracy: 1e-12)
                XCTAssertEqual(drawn.color, 0xFFD3_DEE6)
            }
        }
        XCTAssertEqual(paint.style, .fill)
        XCTAssertEqual(paint.strokeWidth, 0)
    }

    func testCrescentIsAnEvenOddFill() {
        let symbols = PlanetSymbols()
        let canvas = RecordingCanvas()
        symbols.drawCrescent(canvas, 20, 20, 8, 0, Paint(color: 0xFFFF_EAB5, style: .stroke))
        guard case .path(let path, let paint)? = canvas.calls.first else { return XCTFail("no path") }
        XCTAssertEqual(canvas.calls.count, 1)
        XCTAssertEqual(path.fillRule, .evenOdd)
        XCTAssertEqual(paint.style, .fill)
        // Two circles: the second, cut out, is shifted away from the Sun (to the left).
        guard case .move(let outer)? = path.elements.first,
              let second = path.elements.dropFirst().first(where: { if case .move = $0 { return true } else { return false } }),
              case .move(let inner) = second else { return XCTFail("two contours expected") }
        XCTAssertEqual(outer.x, 24, accuracy: 1e-9)
        XCTAssertEqual(inner.x, 20 - 8 * 0.24 + 8 * 0.42, accuracy: 1e-9)
    }

    // MARK: ColorFilter and ColorFilterCanvas

    func testAmbientGreyMatchesAndroidsColorMatrix() {
        let grey = ColorFilter.ambientGrey
        XCTAssertEqual(grey.apply(0xFFFF_FFFF), 0xFF8C_8C8C)  // .55 × 255 = 140.25
        XCTAssertEqual(grey.apply(0xFFFF_0000), 0xFF1E_1E1E)  // .55 × .213 × 255 = 29.87
        XCTAssertEqual(grey.apply(0xFF00_FF00), 0xFF64_6464)  // .55 × .715 × 255 = 100.28
        XCTAssertEqual(grey.apply(0xFF00_00FF), 0xFF0A_0A0A)  // .55 × .072 × 255 = 10.10
        XCTAssertEqual(grey.apply(0x80FF_FFFF), 0x808C_8C8C)  // alpha unchanged
        XCTAssertEqual(grey.apply(0x0000_0000), 0x0000_0000)
        XCTAssertEqual(grey.apply(0xFF80_4020), 0xFF29_2929)  // .55 × (27.264 + 45.76 + 2.304) = 41.43
        XCTAssertEqual(grey.matrix[18], 1)
        XCTAssertEqual(grey.matrix[0], Float(0.55) * Float(0.213))
    }

    func testColorFilterCanvasFiltersEveryColourAndForwardsTheRest() {
        let base = RecordingCanvas()
        let canvas = ColorFilterCanvas(base, filter: .ambientGrey)
        XCTAssertEqual(canvas.width, 400)
        XCTAssertEqual(canvas.height, 800)
        XCTAssertEqual(canvas.pixelScale, 2)

        let count = canvas.save()
        canvas.translate(3, 4)
        canvas.rotate(90, 10, 10)
        canvas.saveLayer(alpha: 0.5)
        XCTAssertEqual(canvas.saveCount, base.saveCount)
        canvas.restore(toCount: count)
        XCTAssertEqual(base.saveCount, 1)
        XCTAssertEqual(base.transforms, ["translate 3.0 4.0", "translate 10.0 10.0", "rotate 90.0",
                                         "translate -10.0 -10.0", "layer 0.5"])

        canvas.drawColor(0xFFFF_FFFF)
        var paint = Paint(color: 0xFFFF_0000)
        paint.shader = .radial(center: Point(0, 0), radius: 5, colors: [0xFF00_FF00, 0x0000_00FF], stops: nil)
        paint.shadow = Shadow(radius: 2, color: 0xFF00_00FF)
        canvas.drawCircle(1, 2, 3, paint)
        canvas.drawText("Sun", 0, 0, Paint(color: 0xFFFF_FFFF))
        XCTAssertEqual(canvas.measureText("Sun", Paint()), base.measureText("Sun", Paint()))

        guard base.calls.count == 3, case .color(let color) = base.calls[0],
              case .path(_, let drawn) = base.calls[1], case .text(_, let text) = base.calls[2] else {
            return XCTFail("unexpected calls \(base.calls)")
        }
        XCTAssertEqual(color, 0xFF8C_8C8C)
        XCTAssertEqual(drawn.color, 0xFF1E_1E1E)
        XCTAssertEqual(drawn.shader, .radial(center: Point(0, 0), radius: 5, colors: [0xFF64_6464, 0x000A_0A0A], stops: nil))
        XCTAssertEqual(drawn.shadow?.color, 0xFF0A_0A0A)
        XCTAssertEqual(drawn.shadow?.radius, 2)
        XCTAssertEqual(text.color, 0xFF8C_8C8C)
    }

    func testColorFilterCanvasFiltersImagesOncePerSource() {
        let base = RecordingCanvas()
        let source = PixelImage(width: 2, height: 1, pixels: [0xFFFF_FFFF, 0x0000_0000])
        ColorFilterCanvas(base, filter: .ambientGrey).drawImage(source, Rect(0, 0, 2, 1), alpha: 0.5)
        ColorFilterCanvas(base, filter: .ambientGrey).drawImage(source, Rect(0, 0, 2, 1), alpha: 1)
        guard case .image(let first, _, let alpha) = base.calls[0], case .image(let second, _, _) = base.calls[1] else {
            return XCTFail("no images")
        }
        XCTAssertEqual(first.pixels, [0xFF8C_8C8C, 0x0000_0000])
        XCTAssertEqual(alpha, 0.5)
        XCTAssertTrue(first === second)
        XCTAssertEqual(source.pixels, [0xFFFF_FFFF, 0x0000_0000])
        // A changed source is filtered again.
        source.pixels[1] = 0xFFFF_0000
        ColorFilterCanvas(base, filter: .ambientGrey).drawImage(source, Rect(0, 0, 2, 1), alpha: 1)
        guard case .image(let third, _, _) = base.calls[2] else { return XCTFail("no image") }
        XCTAssertEqual(third.pixels, [0xFF8C_8C8C, 0xFF1E_1E1E])
    }
}
