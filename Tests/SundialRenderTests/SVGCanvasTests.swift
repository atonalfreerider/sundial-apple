import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import SundialRender
@testable import SundialSVG
import XCTest

final class SVGCanvasTests: XCTestCase {
    /// The repository's Assets folder, found from this file (through any symlink).
    private var assets: URL {
        URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Assets")
    }

    // MARK: PNG

    func testPNGRoundTripKeepsEveryPixel() throws {
        var pixels: [ARGB] = []
        for y in 0..<13 {
            for x in 0..<17 {
                // Opaque, translucent and fully transparent pixels, and gradients the filters like.
                let alpha = [255, 128, 0, 1][(x + y) % 4]
                pixels.append(Colors.argb(alpha, x * 15, y * 19, (x * y) % 256))
            }
        }
        let image = PixelImage(width: 17, height: 13, pixels: pixels)
        let data = PNG.encode(image)
        XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let decoded = try PNG.decode(data)
        XCTAssertEqual(decoded.width, 17)
        XCTAssertEqual(decoded.height, 13)
        XCTAssertEqual(decoded.pixels, pixels)
    }

    func testDecodesTheAssets() throws {
        let earth = try PNG.decode(contentsOf: assets.appendingPathComponent("earth_texture.png"))
        XCTAssertEqual(earth.width, 2048)
        XCTAssertEqual(earth.height, 1024)
        XCTAssertTrue(earth.pixels.allSatisfy { Colors.alpha($0) == 255 }, "an RGB image is opaque")
        let icon = try PNG.decode(contentsOf: assets.appendingPathComponent("AppIcon-1024.png"))
        XCTAssertEqual(icon.width, 1024)
        XCTAssertEqual(icon.height, 1024)
    }

    func testRejectsWhatIsNotPNG() {
        XCTAssertThrowsError(try PNG.decode(Data("not a png".utf8)))
    }

    // MARK: Fonts

    func testSundialCondensedMetricsMatchTheFont() throws {
        let condensed = try TrueTypeFont(contentsOf: assets.appendingPathComponent("sundial_condensed.ttf"),
                                         family: SVGFonts.condensedFamily)
        XCTAssertEqual(condensed.unitsPerEm, 1000)
        // hhea: ascender 878, descender −210, no line gap.
        let metrics = condensed.metrics(size: 1000)
        XCTAssertEqual(metrics.ascent, -878, accuracy: 1e-9)
        XCTAssertEqual(metrics.descent, 210, accuracy: 1e-9)
        XCTAssertEqual(metrics.leading, 0)
        XCTAssertEqual(metrics.fontSpacing, 1088, accuracy: 1e-9)
        XCTAssertNotNil(condensed.glyph("A"))
        XCTAssertGreaterThan(condensed.advanceWidth(condensed.glyph("M")!), condensed.advanceWidth(condensed.glyph("i")!))
    }

    func testGPOSPairKerning() throws {
        let condensed = try TrueTypeFont(contentsOf: assets.appendingPathComponent("sundial_condensed.ttf"),
                                         family: SVGFonts.condensedFamily)
        func kerning(_ pair: String) -> Int {
            let glyphs = pair.unicodeScalars.map { condensed.glyph($0)! }
            return condensed.kerning(glyphs[0], glyphs[1])
        }
        // Values from fontTools: "L?" and "A/" are listed pairs (PairPos format 1), which win
        // over the class pairs (format 2) of "AV", "VA" and "To".
        XCTAssertEqual(kerning("L?"), -37)
        XCTAssertEqual(kerning("A/"), 24)
        XCTAssertEqual(kerning("AV"), -30)
        XCTAssertEqual(kerning("VA"), -30)
        XCTAssertEqual(kerning("To"), -67)
        XCTAssertEqual(kerning("oo"), 0)
    }

    func testSubstitutionsAndLigaturesMatchHarfBuzz() throws {
        let fonts = SVGFonts(condensed: try TrueTypeFont(contentsOf: assets.appendingPathComponent("sundial_condensed.ttf"),
                                                         family: SVGFonts.condensedFamily))
        // hb_shape totals with the default features ('rvrn' turns "$" into its bracket form, and
        // 'liga' makes ff, ffi, ffl, fi and fl), in font units: at 1000 px, the font's units per
        // em, the hinted advances are the font's own.
        let harfBuzz: [(String, Double)] = [("office fifty waffle", 5864), ("Office Coffee", 4763),
                                            ("Staff offsite", 4108), ("AVA $5 To", 3619), ("Wafflé fl", 2922),
                                            ("fjord ff", 2281)]
        for (text, total) in harfBuzz {
            XCTAssertEqual(fonts.advance(text, .sundialCondensed, size: 1000, letterSpacing: 0), total, text)
        }
        // Minikin turns the ligatures off under letter spacing: HarfBuzz with -liga gives 5899,
        // and each of the 19 characters then adds 100.
        XCTAssertEqual(fonts.advance("office fifty waffle", .sundialCondensed, size: 1000, letterSpacing: 0.1), 5899 + 1900)
        // The ligature's characters share its origin; its whole advance (685) is the first's.
        XCTAssertEqual(fonts.origins("office", .sundialCondensed, size: 1000, letterSpacing: 0), [0, 463, 463, 463, 1148, 1579])
        // The SVG keeps a ligature's characters in one <tspan>, so the renderer draws the ligature
        // (at 10 px the hinted advances are whole pixels: o 5, ffi 7).
        let canvas = SVGCanvas(width: 100, height: 100, fonts: fonts)
        var paint = Paint()
        paint.font = .sundialCondensed
        paint.textSize = 10
        canvas.drawText("office", 0, 50, paint)
        XCTAssertTrue(canvas.svgString().contains("<tspan x=\"5\">ffi</tspan><tspan x=\"12\">c</tspan>"),
                      canvas.svgString())
    }

    func testMeasureTextAddsLetterSpacingAndRoundsUp() throws {
        let fonts = SVGFonts(condensed: try TrueTypeFont(contentsOf: assets.appendingPathComponent("sundial_condensed.ttf"),
                                                         family: SVGFonts.condensedFamily))
        let canvas = SVGCanvas(width: 100, height: 100, fonts: fonts)
        var paint = Paint()
        paint.font = .sundialCondensed
        paint.textSize = 30
        let plain = canvas.measureText("SUNDIAL", paint)
        XCTAssertGreaterThan(plain, 0)
        XCTAssertEqual(plain, plain.rounded(.up), "Paint.measureText rounds up")
        paint.letterSpacing = 0.1
        // Three whole pixels (0.1 × 30) per letter.
        XCTAssertEqual(canvas.measureText("SUNDIAL", paint), plain + 21, accuracy: 1)
        XCTAssertEqual(canvas.measureText("", paint), 0)
        XCTAssertEqual(canvas.fontMetrics(paint).ascent, -30 * 0.878, accuracy: 1e-9)
    }

    func testTextIsPlacedAtMinikinsPositions() throws {
        let fonts = SVGFonts(condensed: try TrueTypeFont(contentsOf: assets.appendingPathComponent("sundial_condensed.ttf"),
                                                         family: SVGFonts.condensedFamily))
        let canvas = SVGCanvas(width: 200, height: 100, fonts: fonts)
        var paint = Paint()
        paint.font = .sundialCondensed
        paint.textSize = 30
        paint.letterSpacing = 0.1
        paint.textAlign = .center
        canvas.drawText("AVA", 100, 50, paint)
        let advance = fonts.advance("AVA", .sundialCondensed, size: 30, letterSpacing: 0.1)
        XCTAssertEqual(canvas.textAdvance("AVA", paint), advance)
        XCTAssertEqual(canvas.measureText("AVA", paint), advance.rounded(.up))
        let origins = fonts.origins("AVA", .sundialCondensed, size: 30, letterSpacing: 0.1)
        // Half the three-pixel spacing, rounded down, before the first letter.
        XCTAssertEqual(origins[0], 1)
        let xs = origins.map { SVGCanvas.number(100 - advance / 2 + $0) }.joined(separator: " ")
        let svg = canvas.svgString()
        XCTAssertTrue(svg.contains("x=\"\(xs)\""), svg)
        XCTAssertFalse(svg.contains("text-anchor"))
        XCTAssertFalse(svg.contains("letter-spacing"))
        // A character of several scalars (a sign with its text-style selector) gets a <tspan>
        // of its own rather than splitting.
        canvas.drawText("\u{2648}\u{FE0E} A", 10, 80, paint)
        XCTAssertTrue(canvas.svgString().contains(">\u{2648}\u{FE0E}</tspan><tspan x="))
    }

    // MARK: SVG

    func testSmallSceneIsWellFormedSVG() throws {
        let canvas = SVGCanvas(width: 200, height: 120)
        canvas.drawColor(0xFF10_1820)
        canvas.save()
        var clip = Path()
        clip.addCircle(60, 60, 50)
        canvas.clip(clip)
        var ring = Paint(color: 0xFFFF_D37A, style: .stroke, strokeWidth: 4)
        ring.dash = [6, 3]
        ring.shadow = Shadow(radius: 3, color: 0x8000_0000)
        canvas.drawCircle(60, 60, 40, ring)
        var face = Paint()
        face.shader = .radial(center: Point(60, 60), radius: 30, colors: [Colors.white, Colors.transparent], stops: nil)
        canvas.drawCircle(60, 60, 30, face)
        canvas.restore()
        canvas.saveLayer(alpha: 0.5)
        canvas.rotate(30, 150, 60)
        var text = Paint(color: Colors.white)
        text.textAlign = .center
        text.textSize = 14
        text.letterSpacing = 0.2
        canvas.drawText("<Tom & \"Jerry\">", 150, 60, text)
        canvas.drawImage(PixelImage(width: 2, height: 2, pixels: [Colors.white, Colors.black, Colors.black, Colors.white]),
                         Rect(130, 80, 170, 110), alpha: 0.75)
        canvas.restore()
        canvas.fillSweep(center: Point(170, 20), innerRadius: 5, outerRadius: 15, colors: [0xFFFF_0000, 0xFF00_00FF])
        XCTAssertEqual(canvas.saveCount, 1)

        let svg = canvas.svgString()
        let parser = XMLParser(data: Data(svg.utf8))
        let collector = ElementCollector()
        parser.delegate = collector
        XCTAssertTrue(parser.parse(), "parse error: \(String(describing: parser.parserError))")
        XCTAssertEqual(collector.elements.first, "svg")
        for name in ["clipPath", "radialGradient", "filter", "feGaussianBlur", "text", "image", "use"] {
            XCTAssertTrue(collector.elements.contains(name), "no <\(name)>")
        }
        XCTAssertTrue(svg.contains("&lt;Tom &amp; &quot;Jerry&quot;&gt;"))
        XCTAssertTrue(svg.contains("opacity=\"0.5\""))
        XCTAssertTrue(svg.contains("stroke-dasharray=\"6,3\""))
    }

    func testUnbalancedSavesStillCloseEveryGroup() throws {
        let canvas = SVGCanvas(width: 10, height: 10)
        canvas.saveLayer(alpha: 0.5)
        var clip = Path()
        clip.addRect(Rect(0, 0, 5, 5))
        canvas.clip(clip)
        canvas.drawRect(0, 0, 10, 10, Paint(color: Colors.white))
        canvas.restore(toCount: 5) // nothing to restore to that deep
        canvas.restore()
        canvas.restore() // underflow is ignored
        canvas.saveLayer(alpha: 0.25)
        let parser = XMLParser(data: Data(canvas.svgString().utf8))
        XCTAssertTrue(parser.parse())
    }
}

private final class ElementCollector: NSObject, XMLParserDelegate {
    var elements: [String] = []
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        elements.append(elementName)
    }
}
