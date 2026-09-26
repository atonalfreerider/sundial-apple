import Foundation

// Android's text helpers, rebuilt on the Canvas primitives (measureText, fontMetrics, drawText and
// the matrix) so every backend truncates, wraps and curves text the same way:
// TextUtils.ellipsize (END), StaticLayout and Canvas.drawTextOnPath along a circular arc.
//
// Text is handled a Character (grapheme cluster) at a time, where Android works in UTF-16 chars
// and gives a cluster's width to its first char: the cut points are the same.
//
// Fitting and aligning use textAdvance, the unrounded widths Minikin gives MeasuredParagraph and
// Layout; only the ellipsis is measured with measureText (Paint.measureText, rounded up), as
// TextUtils and StaticLayout measure it.

/// The ellipsis TextUtils.getEllipsisString(END) returns.
private let ellipsisString = "\u{2026}"

/// A laid-out StaticLayout: the text wrapped to [width], ready to draw with Canvas.drawTextBlock.
public struct TextBlock: Equatable, Sendable {
    /// Layout.Alignment: NORMAL, CENTER and OPPOSITE for left-to-right text.
    public enum Alignment: Equatable, Sendable { case left, center, right }

    /// The visible lines, without the spaces that hang at their ends; when the text ran past
    /// maxLines the last one ends in an ellipsis.
    public let lines: [String]
    public let paint: Paint
    /// The wrap width.
    public let width: Double
    /// Distance between baselines in whole layout pixels, as StaticLayout keeps it:
    /// round(descent) − round(ascent) + round(lineSpacingExtra) pixels (Paint.FontMetricsInt, no
    /// leading), in canvas units.
    public let lineHeight: Double
    /// StaticLayout's setLineSpacing(add, 1), rounded to whole pixels: added below every line but
    /// the last.
    public let lineSpacingExtra: Double
    public let alignment: Alignment
    /// From the top of a line to its baseline: round(−ascent) pixels, in canvas units.
    public let baseline: Double
    /// Device pixels per canvas unit when the block was laid out: the pixels StaticLayout rounds
    /// to (1 in the pixel-based reference renders).
    public let pixelScale: Double

    public init(lines: [String], paint: Paint, width: Double, lineHeight: Double, lineSpacingExtra: Double,
                alignment: Alignment, baseline: Double, pixelScale: Double = 1) {
        self.lines = lines
        self.paint = paint
        self.width = width
        self.lineHeight = lineHeight
        self.lineSpacingExtra = lineSpacingExtra
        self.alignment = alignment
        self.baseline = baseline
        self.pixelScale = pixelScale
    }

    /// Layout.getHeight() with includePad false: the last line carries no extra spacing.
    public var height: Double { Double(lines.count) * lineHeight - lineSpacingExtra }
}

public extension Canvas {
    /// TextUtils.ellipsize(text, paint, availableWidth, TruncateAt.END): the text if it fits,
    /// otherwise as many leading characters as fit beside "…" (without the spaces before the cut)
    /// followed by "…", or "" when not even one character fits.
    func ellipsize(_ text: String, _ paint: Paint, _ availableWidth: Double) -> String {
        // MeasuredParagraph.getWholeWidth(): unrounded.
        if textAdvance(text, paint) <= availableWidth { return text }
        let characters = Array(text)
        // paint.measureText(ellipsis): rounded up.
        let avail = availableWidth - measureText(ellipsisString, paint)
        // Everything goes when even the ellipsis does not fit.
        var left = avail < 0 ? 0 : fittingPrefixCount(self, characters, paint, avail)
        // MeasuredParagraph.breakText backs off over the spaces before the cut.
        while left > 0 && characters[left - 1] == " " { left -= 1 }
        // Nothing remains beside the ellipsis: TextUtils returns an empty string.
        if left == 0 { return "" }
        return String(characters[..<left]) + ellipsisString
    }

    /// StaticLayout.Builder.obtain(text, paint, width) with setAlignment, setIncludePad(false),
    /// setLineSpacing(lineSpacingExtra, 1), setMaxLines(maxLines) and setEllipsize(END): lines
    /// break greedily where the line breaker allows (BREAK_STRATEGY_SIMPLE, no hyphenation; see
    /// lineBreakOpportunities), a word wider than the line is broken between characters, and "\n"
    /// starts a new paragraph. When the text needs more than [maxLines] lines, the rest of the
    /// last visible line's paragraph is kept on that line and ellipsized, as StaticLayout does.
    /// Line metrics are whole layout pixels (the canvas's pixel scale), as StaticLayout's are.
    func layoutText(_ text: String, _ paint: Paint, width: Double, lineSpacingExtra: Double = 0,
                    maxLines: Int = .max, alignment: TextBlock.Alignment = .center) -> TextBlock {
        let paragraphs = text.split(separator: "\n", omittingEmptySubsequences: false).map { Array($0) }
        var wrapped: [(paragraph: Int, range: Range<Int>)] = []
        for (index, paragraph) in paragraphs.enumerated() {
            for range in wrapParagraph(self, paragraph, paint, width) { wrapped.append((index, range)) }
        }
        let visibleCount = max(maxLines, 1)
        var lines: [String] = []
        if wrapped.count <= visibleCount {
            lines = wrapped.map { visibleLine(paragraphs[$0.paragraph][$0.range]) }
        } else {
            lines = wrapped[..<(visibleCount - 1)].map { visibleLine(paragraphs[$0.paragraph][$0.range]) }
            let last = wrapped[visibleCount - 1]
            let paragraph = paragraphs[last.paragraph]
            // Characters remain after this paragraph (StaticLayout's moreChars, endPos < bufEnd):
            // StaticLayout forces an ellipsis even if this line fits. A trailing newline leaves
            // only an empty paragraph after it, which is no characters.
            let lastIndex = paragraphs.count - 1
            let moreParagraphs = last.paragraph < lastIndex
                && !(last.paragraph == lastIndex - 1 && paragraphs[lastIndex].isEmpty)
            lines.append(ellipsizedLastLine(self, Array(paragraph[last.range.lowerBound...]), paint, width,
                                            forceEllipsis: moreParagraphs))
        }
        // Paint.getFontMetricsInt (SkScalarRoundToInt: half up) and StaticLayout's
        // extra = (int) (add + 0.5), in layout pixels. Leading is not part of a line.
        let scale = pixelScale > 0 ? pixelScale : 1
        let metrics = fontMetrics(paint)
        let ascent = (metrics.ascent * scale + 0.5).rounded(.down)
        let descent = (metrics.descent * scale + 0.5).rounded(.down)
        let add = lineSpacingExtra * scale
        let extra = add >= 0 ? (add + 0.5).rounded(.down) : -(-add + 0.5).rounded(.down)
        return TextBlock(lines: lines, paint: paint, width: width, lineHeight: (descent - ascent + extra) / scale,
                         lineSpacingExtra: extra / scale, alignment: alignment, baseline: -ascent / scale,
                         pixelScale: scale)
    }

    /// Draws the block with its top-left at (x, y), as StaticLayout.draw after translate(x, y):
    /// Layout.drawText places each line in whole pixels, a centred one at
    /// (width − ((int) extent & ~1)) >> 1 and an opposite one at width − (int) extent.
    func drawTextBlock(_ block: TextBlock, _ x: Double, _ y: Double) {
        // Layout positions each line itself, so it draws with a left-aligned paint.
        var paint = block.paint
        paint.textAlign = .left
        let scale = block.pixelScale
        let width = Int((block.width * scale + 1e-6).rounded(.down))
        for (index, line) in block.lines.enumerated() where !line.isEmpty {
            // (int) getLineExtent: the unrounded width, truncated.
            let extent = Int(textAdvance(line, paint) * scale)
            let left: Int
            switch block.alignment {
            case .left: left = 0
            case .center: left = (width - (extent & ~1)) >> 1
            case .right: left = width - extent
            }
            // Line tops are lineHeight apart; each baseline sits [baseline] below its top.
            drawText(line, x + Double(left) / scale, y + Double(index) * block.lineHeight + block.baseline, paint)
        }
    }

    /// drawTextOnPath along a circle of [radius] about (cx, cy), starting at [startAngle] and
    /// running clockwise on screen when [clockwise] (the direction the Kotlin arc path was added
    /// in). Like Android, a positive [vOffset] moves the text to the right of the direction of
    /// travel (inward on a clockwise arc).
    ///
    /// The default, for backends that cannot shape a string themselves: as Skia does, each
    /// character keeps its shape and is turned to the tangent at its centre, hOffset + getX(i) +
    /// getCharAdvance(i) / 2, with its baseline along the direction of travel and its top on the
    /// left. Characters sit where the whole string puts them (letter spacing and kerning
    /// included) and the text is laid from [startAngle] whatever the paint's textAlign. It draws
    /// in logical order, one character at a time, so right-to-left and joining scripts are not
    /// shaped (Core Text's backend draws those itself). As Android draws a run, the shadow is
    /// cast once under every glyph (drawTextShadow) and then each glyph is drawn once; the
    /// shadow's offset stays in screen space rather than turning with the glyphs.
    func drawTextOnArc(_ text: String, cx: Double, cy: Double, radius: Double, startAngle: Double,
                       clockwise: Bool, vOffset: Double, _ paint: Paint) {
        guard !text.isEmpty, radius > 0 else { return }
        // Minikin puts half of each character's letter spacing before its glyph.
        let halfSpacing = paint.letterSpacing * paint.textSize / 2
        let direction = clockwise ? 1.0 : -1.0
        let characters = Array(text)
        // Where the whole string starts each character (Layout.getX, less the half spacing),
        // kerning with the one before included.
        var starts: [Double] = []
        var prefix = ""
        for character in characters {
            prefix.append(character)
            starts.append(textAdvance(prefix, paint) - textAdvance(String(character), paint))
        }
        let total = textAdvance(text, paint)
        var glyphs: [(text: String, x: Double, y: Double, rotation: Double, halfWidth: Double)] = []
        for (index, character) in characters.enumerated() where !character.isWhitespace {
            // getCharAdvance: to where the next character starts (kerning with it included).
            let advance = (index + 1 < characters.count ? starts[index + 1] : total) - starts[index]
            let halfWidth = advance / 2
            let centre = starts[index] + halfSpacing + halfWidth
            let angle = startAngle + direction * centre / radius * 180 / .pi
            let a = angle * .pi / 180
            glyphs.append((String(character), cx + cos(a) * radius, cy + sin(a) * radius, angle + direction * 90,
                           halfWidth))
        }
        var glyphPaint = paint
        glyphPaint.textAlign = .left
        glyphPaint.letterSpacing = 0
        if let shadow = paint.shadow {
            for glyph in glyphs {
                // Turn the offset back by the glyph's rotation so it lands as it would unrotated.
                let r = glyph.rotation * .pi / 180
                var turned = shadow
                turned.dx = shadow.dx * cos(r) + shadow.dy * sin(r)
                turned.dy = -shadow.dx * sin(r) + shadow.dy * cos(r)
                var shadowPaint = glyphPaint
                shadowPaint.shadow = turned
                save()
                translate(glyph.x, glyph.y)
                rotate(glyph.rotation)
                drawTextShadow(glyph.text, -glyph.halfWidth, vOffset, shadowPaint)
                restore()
            }
        }
        glyphPaint.shadow = nil
        for glyph in glyphs {
            save()
            translate(glyph.x, glyph.y)
            rotate(glyph.rotation)
            drawText(glyph.text, -glyph.halfWidth, vOffset, glyphPaint)
            restore()
        }
    }
}

// MARK: - StaticLayout internals

/// Minikin's line-end spaces (isLineEndSpace): a line may break after them, and they hang past
/// its end, neither drawn nor measured.
private func isLineEndSpace(_ character: Character) -> Bool {
    let scalars = character.unicodeScalars
    guard scalars.count == 1, let value = scalars.first?.value else { return false }
    switch value {
    case 0x0020, 0x1680, 0x2000...0x2006, 0x2008...0x200A, 0x205F, 0x3000: return true
    default: return false
    }
}

/// The line as Layout draws it: the spaces that hang past its end are not drawn or measured.
private func visibleLine(_ characters: ArraySlice<Character>) -> String {
    var end = characters.endIndex
    while end > characters.startIndex && isLineEndSpace(characters[end - 1]) { end -= 1 }
    return String(characters[characters.startIndex..<end])
}

/// The most leading characters whose width is within [limit] (0 when none fit). Android adds
/// unrounded widths until one overflows; widths only grow as characters are added, so a binary
/// search finds the same cut with far fewer measurements.
private func fittingPrefixCount(_ canvas: Canvas, _ characters: [Character], _ paint: Paint,
                                _ limit: Double) -> Int {
    guard limit >= 0 else { return 0 }
    var low = 0
    var high = characters.count
    while low < high {
        let mid = (low + high + 1) / 2
        if canvas.textAdvance(String(characters[..<mid]), paint) <= limit { low = mid } else { high = mid - 1 }
    }
    return low
}

/// How a character takes part in line breaking: the few Unicode line-break (UAX #14) classes
/// the rules below use, read from the character's first scalar.
private struct BreakClass {
    /// A line-end space (SP, and the spaces of class BA): break after, never before.
    var space = false
    /// ZW: a break is allowed after it.
    var zeroWidthSpace = false
    /// B2, the em dash and its doubles: break before and after, but not between two.
    var dash = false
    /// OP: no break after it, even across spaces.
    var open = false
    /// No break before: CL, CP, EX, IS, SY, QU, NS, CJ, BA, HY, GL, IN and ZW.
    var noBreakBefore = false
    /// No break after: OP, QU, GL, and the hyphens Minikin keeps whole without hyphenation.
    var noBreakAfter = false
    /// SY "/", IN "…", EX "?" "!" and the figure dash: break after when a letter follows.
    var breakBeforeLetter = false
    /// Han, kana, Hangul syllables and pictographs (ID): a break is allowed on either side.
    var ideograph = false
    var letter = false

    init(_ character: Character) {
        guard let scalar = character.unicodeScalars.first else { return }
        let v = scalar.value
        let category = scalar.properties.generalCategory
        space = isLineEndSpace(character)
        zeroWidthSpace = v == 0x200B
        dash = v == 0x2014 || v == 0x2E3A || v == 0x2E3B
        let quote = v == 0x22 || v == 0x27 || category == .initialPunctuation || category == .finalPunctuation
        open = category == .openPunctuation || v == 0xA1 || v == 0xBF
        let close = category == .closePunctuation || [0x3001, 0x3002, 0xFF0C, 0xFF0E, 0xFF61, 0xFF64].contains(v)
        let exclamation = [0x21, 0x3F, 0xFF01, 0xFF1F].contains(v)
        let infix = [0x2C, 0x2E, 0x3A, 0x3B, 0x37E, 0x589, 0x60C, 0x60D, 0x7F8, 0x2044, 0xFE10, 0xFE13, 0xFE14].contains(v)
        let solidus = v == 0x2F
        let inseparable = [0x2024, 0x2025, 0x2026, 0x22EF, 0xFE19].contains(v)
        let glue = [0xA0, 0x34F, 0x180E, 0x2007, 0x2011, 0x202F, 0x2060, 0xFEFF].contains(v)
        // BA and HY that are not spaces.
        let breakAfter = [0x09, 0x2D, 0x7C, 0xAD, 0x58A, 0x5BE, 0x1400, 0x2010, 0x2012, 0x2013, 0x2027,
                          0x2E17, 0x2E40].contains(v)
        // Minikin's isLineBreakingHyphen and the soft hyphen: with hyphenation off, no break after.
        let hyphen = [0x2D, 0x58A, 0x5BE, 0x1400, 0x2010, 0x2013, 0x2027, 0x2E17, 0x2E40, 0xAD].contains(v)
        let nonStarter = BreakClass.isNonStarter(v)
        noBreakBefore = close || exclamation || infix || solidus || quote || nonStarter || breakAfter || glue
            || inseparable || zeroWidthSpace
        noBreakAfter = open || quote || glue || hyphen
        breakBeforeLetter = solidus || exclamation || v == 0x2026 || v == 0x2012
        ideograph = !nonStarter && BreakClass.isIdeographic(scalar)
        letter = !ideograph && scalar.properties.isAlphabetic
    }

    /// NS and CJ: small kana, the prolonged sound mark, iteration marks, middle dots and the like.
    static func isNonStarter(_ v: UInt32) -> Bool {
        switch v {
        case 0x17D6, 0x203C, 0x203D, 0x2047...0x2049, 0x3005, 0x301C, 0x303B, 0x303C, 0x309B...0x309E, 0x30A0,
             0x30FB...0x30FE, 0xA015, 0xFE54, 0xFE55, 0xFF1A, 0xFF1B, 0xFF65, 0xFF67...0xFF70, 0xFF9E, 0xFF9F,
             0x3041, 0x3043, 0x3045, 0x3047, 0x3049, 0x3063, 0x3083, 0x3085, 0x3087, 0x308E, 0x3095, 0x3096,
             0x30A1, 0x30A3, 0x30A5, 0x30A7, 0x30A9, 0x30C3, 0x30E3, 0x30E5, 0x30E7, 0x30EE, 0x30F5, 0x30F6,
             0x31F0...0x31FF:
            return true
        default:
            return false
        }
    }

    static func isIdeographic(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x2E80...0x2FDF, 0x3006, 0x3007, 0x3040...0x309F, 0x30A0...0x30FF, 0x3100...0x312F, 0x3130...0x318F,
             0x31A0...0x31BF, 0x31F0...0x31FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xA000...0xA4CF, 0xAC00...0xD7AF,
             0xF900...0xFAFF, 0xFF66...0xFF9F, 0x1F000...0x1FAFF, 0x20000...0x3FFFD:
            return true
        default:
            return scalar.properties.isEmojiPresentation && scalar.value > 0xFF
        }
    }
}

/// Where a line may break inside a paragraph, as the ICU line breaker Minikin uses finds it and
/// Minikin then filters it (a subset of UAX #14 that covers the app's text): element i says a
/// line may start at character i. Besides the spaces, breaks fall on either side of an em dash
/// (not between two, nor before closing punctuation), after "/", "…", "?" and "!" before a
/// letter, and between ideographs; never after a hyphen, since hyphenation is off
/// (HYPHENATION_FREQUENCY_NONE, the Builder's default, so Minikin drops those breaks).
func lineBreakOpportunities(_ characters: [Character]) -> [Bool] {
    let classes = characters.map(BreakClass.init)
    var breaks = [Bool](repeating: false, count: characters.count + 1)
    if !characters.isEmpty { breaks[characters.count] = true }
    guard characters.count > 1 else { return breaks }
    for i in 1..<characters.count {
        let a = classes[i - 1], b = classes[i]
        breaks[i] = {
            if b.space { return false }
            if a.space {
                // The character before the run of spaces.
                var j = i - 1
                while j > 0 && classes[j - 1].space { j -= 1 }
                if j > 0 {
                    let before = classes[j - 1]
                    if before.open { return false }            // OP SP* ×
                    if before.dash && b.dash { return false }  // B2 SP* × B2
                }
                return true                                    // SP ÷
            }
            if a.zeroWidthSpace { return true }
            if b.noBreakBefore || a.noBreakAfter { return false }
            if a.dash || b.dash { return !(a.dash && b.dash) }
            if a.breakBeforeLetter && (b.letter || b.ideograph) { return true }
            if a.ideograph || b.ideograph { return true }
            return false
        }()
    }
    return breaks
}

/// Greedy line breaking of one paragraph (StaticLayout's BREAK_STRATEGY_SIMPLE): each line takes
/// the pieces between break opportunities while they fit, the spaces at the end of a piece hang
/// past the line's end, and a piece too wide for a line of its own is broken after as many
/// characters as fit (at least one). The ranges include each line's trailing spaces; an empty
/// paragraph is one empty line.
private func wrapParagraph(_ canvas: Canvas, _ characters: [Character], _ paint: Paint,
                           _ width: Double) -> [Range<Int>] {
    let count = characters.count
    guard count > 0 else { return [0..<0] }
    let breaks = lineBreakOpportunities(characters)
    func fits(_ start: Int, _ end: Int) -> Bool {
        canvas.textAdvance(String(characters[start..<end]), paint) <= width
    }
    var lines: [Range<Int>] = []
    var lineStart = 0
    while lineStart < count {
        var lineEnd = lineStart
        var position = lineStart
        while position < count {
            // The piece up to the next break, and where its hanging spaces begin.
            var spaceEnd = position + 1
            while spaceEnd < count && !breaks[spaceEnd] { spaceEnd += 1 }
            var wordEnd = spaceEnd
            while wordEnd > position && isLineEndSpace(characters[wordEnd - 1]) { wordEnd -= 1 }
            if fits(lineStart, wordEnd) {
                lineEnd = spaceEnd
                position = spaceEnd
                continue
            }
            if lineEnd == lineStart {
                // Not even this one piece fits: break it between characters.
                var end = lineStart + 1
                while end < wordEnd && fits(lineStart, end + 1) { end += 1 }
                lineEnd = end
            }
            break
        }
        lines.append(lineStart..<lineEnd)
        lineStart = lineEnd
    }
    return lines
}

/// StaticLayout.calculateEllipsis (END) for the last visible line, which holds the rest of its
/// paragraph: as many characters as fit beside "…" followed by "…". The spaces before the cut
/// stay, as Android keeps them. When the rest fits but more paragraphs follow ([forceEllipsis]),
/// the ellipsis replaces the paragraph's newline.
private func ellipsizedLastLine(_ canvas: Canvas, _ characters: [Character], _ paint: Paint, _ width: Double,
                                forceEllipsis: Bool) -> String {
    let line = visibleLine(characters[...])
    if canvas.textAdvance(line, paint) <= width && !forceEllipsis { return line }
    let kept = fittingPrefixCount(canvas, characters, paint, width - canvas.measureText(ellipsisString, paint))
    if kept == characters.count { return forceEllipsis ? String(characters) + ellipsisString : line }
    return String(characters[..<kept]) + ellipsisString
}
