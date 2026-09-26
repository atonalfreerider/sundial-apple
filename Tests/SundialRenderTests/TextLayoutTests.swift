import XCTest
@testable import SundialRender

/// A Canvas whose characters are all [unit] wide, which records the text it draws.
private final class FixedWidthCanvas: Canvas {
    struct Drawn: Equatable {
        let text: String
        let x: Double
        let y: Double
        let shadow: Bool
    }

    var unit: Double
    var metrics = FontMetrics(ascent: -8.4, descent: 2.3)
    var scale = 1.0
    var drawn: [Drawn] = []
    var shadows: [Drawn] = []
    private var depth = 1

    init(unit: Double = 10) { self.unit = unit }

    let width = 400.0
    let height = 400.0
    var pixelScale: Double { scale }
    var saveCount: Int { depth }
    func save() -> Int { depth += 1; return depth - 1 }
    func saveLayer(alpha: Double) -> Int { save() }
    func restore() { depth -= 1 }
    func restore(toCount: Int) { depth = toCount }
    func translate(_ dx: Double, _ dy: Double) {}
    func rotate(_ degrees: Double) {}
    func scale(_ sx: Double, _ sy: Double) {}
    func concat(_ transform: SundialRender.AffineTransform) {}
    func clip(_ path: Path) {}
    func drawPath(_ path: Path, _ paint: Paint) {}
    func drawText(_ text: String, _ x: Double, _ y: Double, _ paint: Paint) {
        drawn.append(Drawn(text: text, x: x, y: y, shadow: paint.shadow != nil))
    }
    func drawTextShadow(_ text: String, _ x: Double, _ y: Double, _ paint: Paint) {
        shadows.append(Drawn(text: text, x: x, y: y, shadow: true))
    }
    func drawImage(_ image: PixelImage, _ rect: Rect, alpha: Double) {}
    func drawColor(_ color: ARGB) {}
    func textAdvance(_ text: String, _ paint: Paint) -> Double { Double(text.count) * unit }
    /// Paint.measureText rounds up.
    func measureText(_ text: String, _ paint: Paint) -> Double { textAdvance(text, paint).rounded(.up) }
    func fontMetrics(_ paint: Paint) -> FontMetrics { metrics }
}

final class TextLayoutTests: XCTestCase {
    private func lines(_ text: String, _ width: Double, maxLines: Int = .max) -> [String] {
        FixedWidthCanvas().layoutText(text, Paint(), width: width, maxLines: maxLines).lines
    }

    // MARK: Line breaking

    func testBreaksOnEitherSideOfAnEmDash() {
        XCTAssertEqual(lines("today—take a breath", 80), ["today—", "take a", "breath"])
        XCTAssertEqual(lines("your path—bright and steady—opens", 120), ["your path—", "bright and", "steady—opens"])
    }

    func testClosingPunctuationStaysWithTheDash() {
        XCTAssertEqual(lines("Stop—\u{201D} she", 50), ["Stop", "—\u{201D}", "she"])
        XCTAssertEqual(lines("a——b", 20), ["a", "——", "b"])
    }

    func testIdeographsBreakBetweenThemselves() {
        XCTAssertEqual(lines("abc 日本語日本語", 80), ["abc 日本語日", "本語"])
        // No line starts with a small kana or closing mark.
        XCTAssertEqual(lines("日本ゃ。語", 30), ["日", "本ゃ。", "語"])
    }

    func testOtherBreakingSpacesHang() {
        XCTAssertEqual(lines("hello\u{3000}world", 80), ["hello", "world"])
        XCTAssertEqual(lines("hello\u{2003}world", 80), ["hello", "world"])
        // A no-break space glues.
        XCTAssertEqual(lines("ab\u{00A0}cd ef", 40), ["ab\u{00A0}c", "d ef"])
    }

    func testNoBreakAfterAHyphenWithoutHyphenation() {
        XCTAssertEqual(lines("Team-building day", 80), ["Team-bui", "lding", "day"])
        XCTAssertEqual(lines("and/or so", 50), ["and/", "or so"])
    }

    func testTrailingNewlineForcesNoEllipsis() {
        XCTAssertEqual(lines("Hello\n", 80, maxLines: 1), ["Hello"])
        XCTAssertEqual(lines("Hello\n\n", 80, maxLines: 1), ["Hello\u{2026}"])
        XCTAssertEqual(lines("Hello\nWorld", 80, maxLines: 1), ["Hello\u{2026}"])
    }

    // MARK: Fitting

    func testFitsOnTheUnroundedAdvance() {
        // Ten characters 10.03 wide: 100.3 fits in 100.5, though measureText says 101.
        let canvas = FixedWidthCanvas(unit: 10.03)
        XCTAssertEqual(canvas.ellipsize("abcdefghij", Paint(), 100.5), "abcdefghij")
        XCTAssertEqual(canvas.ellipsize("abcdefghij", Paint(), 100.2), "abcdefgh\u{2026}")
        XCTAssertEqual(canvas.layoutText("abcdefghij", Paint(), width: 100.5).lines, ["abcdefghij"])
    }

    // MARK: Metrics and drawing

    func testLinesAreWholePixelsApart() {
        let canvas = FixedWidthCanvas()
        canvas.metrics = FontMetrics(ascent: -72.17, descent: 17.11, leading: 3)
        let block = canvas.layoutText("one two three", Paint(), width: 50, lineSpacingExtra: 5.25)
        XCTAssertEqual(block.lines, ["one", "two", "three"])
        // round(17.11) − round(−72.17) + (int) (5.25 + .5): leading is not part of a line.
        XCTAssertEqual(block.lineHeight, 17 + 72 + 5)
        XCTAssertEqual(block.baseline, 72)
        XCTAssertEqual(block.height, 3 * (17 + 72) + 2 * 5)
        canvas.drawTextBlock(block, 100, 10)
        XCTAssertEqual(canvas.drawn.map(\.y), [82, 176, 270])
        // Centred in whole pixels: (50 − (30 & ~1)) >> 1 and (50 − (50 & ~1)) >> 1.
        XCTAssertEqual(canvas.drawn.map(\.x), [110, 110, 100])
    }

    func testLayoutRoundsInDevicePixels() {
        let canvas = FixedWidthCanvas(unit: 5)
        canvas.scale = 3
        canvas.metrics = FontMetrics(ascent: -10.1, descent: 2.9)
        let block = canvas.layoutText("ab cd", Paint(), width: 11, lineSpacingExtra: 2)
        XCTAssertEqual(block.lines, ["ab", "cd"])
        XCTAssertEqual(block.lineHeight * 3, (9 + 30 + 6), accuracy: 1e-9)
        canvas.drawTextBlock(block, 0, 0)
        // (33 − (30 & ~1)) >> 1 = 1 pixel: a third of a unit.
        XCTAssertEqual(canvas.drawn[0].x, 1.0 / 3, accuracy: 1e-12)
    }

    func testArcLabelCastsOneShadowPassThenDrawsEachGlyphOnce() {
        let canvas = FixedWidthCanvas()
        var paint = Paint()
        paint.shadow = Shadow(radius: 2.5, color: 0xD000_0000)
        canvas.drawTextOnArc("ab c", cx: 0, cy: 0, radius: 100, startAngle: 0, clockwise: true, vOffset: 3, paint)
        XCTAssertEqual(canvas.shadows.map(\.text), ["a", "b", "c"])
        XCTAssertEqual(canvas.drawn.map(\.text), ["a", "b", "c"])
        XCTAssertFalse(canvas.drawn.contains { $0.shadow })
        XCTAssertEqual(canvas.drawn[0], FixedWidthCanvas.Drawn(text: "a", x: -5, y: 3, shadow: false))
    }
}
