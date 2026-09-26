import Foundation
import SundialRender

// Text metrics for the SVG backend, read straight from TrueType files so that measureText and
// fontMetrics give what Android's Paint gives for the same font: the instrument lays out its
// labels, cards and ellipses from these numbers, and SVG has no way to ask the renderer.
//
// Android measures through Minikin, HarfBuzz and Skia on FreeType, with the Paint defaults the
// app uses (hinting on, neither linear nor subpixel text). That means:
//   - ascent, descent and leading are hhea's ascender, descender and lineGap scaled to the text
//     size (OS/2's typo values instead when the font sets USE_TYPO_METRICS), unrounded;
//   - each glyph advances by hmtx's width scaled to the size and rounded to a whole pixel (the
//     hinted advance), plus the pair kerning, unrounded (HarfBuzz): GPOS's 'kern' feature when
//     the font has a GPOS table, else the legacy 'kern' table;
//   - letter spacing, letterSpacing × size, is rounded to a whole pixel and added once per
//     character;
//   - Paint.measureText rounds the total up (Math.ceil); SVGCanvas does that last step.
// Of GPOS, only pair adjustment (lookup type 2, directly or through an extension) in the 'kern'
// feature is read: Sundial Condensed kerns that way, and the serif and sans fonts draw single
// glyphs or plain words where anything else hardly matters.

/// The metrics of one TrueType font: head, hhea, OS/2, hmtx, cmap (format 4 and 12), and the
/// pair kerning of GPOS or kern.
public final class TrueTypeFont {
    public enum Error: Swift.Error, Equatable {
        case malformed(String)
    }

    /// The file itself, for embedding in the SVG.
    public let data: Data
    /// The CSS font-family that names this font in the SVG.
    public let family: String
    public let unitsPerEm: Int
    /// Font units, y up: ascender is positive, descender negative.
    public let ascender: Int
    public let descender: Int
    public let lineGap: Int
    public let glyphCount: Int

    private let advances: [UInt16]
    private let glyphs: [UInt32: UInt16]
    private let legacyKerning: [UInt32: Int]
    private let pairKerning: PairKerning?

    public convenience init(contentsOf url: URL, family: String) throws {
        try self.init(data: Data(contentsOf: url), family: family)
    }

    public init(data: Data, family: String) throws {
        let reader = Reader(bytes: [UInt8](data))
        self.data = data
        self.family = family

        guard reader.bytes.count >= 12 else { throw Error.malformed("too short for a table directory") }
        let tableCount = try reader.u16(4)
        var tables: [String: (offset: Int, length: Int)] = [:]
        for index in 0..<tableCount {
            let record = 12 + index * 16
            let tag = String(decoding: try reader.slice(record, 4), as: UTF8.self)
            tables[tag] = (try reader.u32(record + 8), try reader.u32(record + 12))
        }
        func table(_ tag: String) throws -> Int {
            guard let entry = tables[tag] else { throw Error.malformed("no \(tag) table") }
            return entry.offset
        }

        let head = try table("head")
        unitsPerEm = try reader.u16(head + 18)
        guard unitsPerEm > 0 else { throw Error.malformed("unitsPerEm is 0") }

        let hhea = try table("hhea")
        var ascender = try reader.i16(hhea + 4)
        var descender = try reader.i16(hhea + 6)
        var lineGap = try reader.i16(hhea + 8)
        let metricCount = try reader.u16(hhea + 34)

        // Skia prefers the typo metrics when the font asks for them (fsSelection bit 7).
        if let os2 = tables["OS/2"]?.offset, os2 + 74 <= reader.bytes.count {
            let version = try reader.u16(os2)
            let selection = try reader.u16(os2 + 62)
            if version != 0xFFFF && selection & (1 << 7) != 0 {
                ascender = try reader.i16(os2 + 68)
                descender = try reader.i16(os2 + 70)
                lineGap = try reader.i16(os2 + 72)
            }
        }
        self.ascender = ascender
        self.descender = descender
        // Skia: "disallow negative linespacing".
        self.lineGap = max(0, lineGap)

        let maxp = try table("maxp")
        glyphCount = try reader.u16(maxp + 4)

        let hmtx = try table("hmtx")
        guard metricCount > 0 else { throw Error.malformed("no horizontal metrics") }
        var advances = [UInt16](repeating: 0, count: max(glyphCount, metricCount))
        for glyph in 0..<metricCount { advances[glyph] = UInt16(try reader.u16(hmtx + glyph * 4)) }
        // Glyphs past numberOfHMetrics share the last advance (monospaced tails).
        for glyph in metricCount..<advances.count { advances[glyph] = advances[metricCount - 1] }
        self.advances = advances

        glyphs = try TrueTypeFont.readCmap(reader, try table("cmap"))
        // HarfBuzz leaves the 'kern' table alone whenever GPOS has any lookups.
        pairKerning = try tables["GPOS"].flatMap { try PairKerning(reader, $0.offset) }
        legacyKerning = pairKerning == nil
            ? try tables["kern"].map { try TrueTypeFont.readKern(reader, $0.offset) } ?? [:]
            : [:]
    }

    /// The glyph for [scalar], or nil when the font has none (it would draw .notdef).
    public func glyph(_ scalar: Unicode.Scalar) -> Int? {
        guard let glyph = glyphs[scalar.value], glyph != 0 else { return nil }
        return Int(glyph)
    }

    /// Advance width of [glyph] in font units.
    public func advanceWidth(_ glyph: Int) -> Int {
        glyph >= 0 && glyph < advances.count ? Int(advances[glyph]) : Int(advances[0])
    }

    /// Kerning between two glyphs in font units: GPOS pair adjustment, or the legacy 'kern' table
    /// in a font without GPOS.
    public func kerning(_ left: Int, _ right: Int) -> Int {
        if let pairKerning { return pairKerning.value(left, right) }
        return legacyKerning[UInt32(left) << 16 | UInt32(right)] ?? 0
    }

    /// Paint.FontMetrics at [size]: hhea's values scaled, ascent negative.
    public func metrics(size: Double) -> FontMetrics {
        let scale = size / Double(unitsPerEm)
        return FontMetrics(ascent: -Double(ascender) * scale, descent: -Double(descender) * scale,
                           leading: Double(lineGap) * scale)
    }

    // MARK: Tables

    private static func readCmap(_ reader: Reader, _ cmap: Int) throws -> [UInt32: UInt16] {
        let count = try reader.u16(cmap + 2)
        var format4: Int?
        var format12: Int?
        for index in 0..<count {
            let record = cmap + 4 + index * 8
            let platform = try reader.u16(record)
            let encoding = try reader.u16(record + 2)
            let subtable = cmap + (try reader.u32(record + 4))
            let format = try reader.u16(subtable)
            let unicode = platform == 0 || (platform == 3 && (encoding == 1 || encoding == 10))
            guard unicode else { continue }
            if format == 12 && format12 == nil { format12 = subtable }
            if format == 4 && format4 == nil { format4 = subtable }
        }
        var map: [UInt32: UInt16] = [:]
        if let subtable = format12 {
            let groups = try reader.u32(subtable + 12)
            for index in 0..<groups {
                let group = subtable + 16 + index * 12
                let start = try reader.u32(group)
                let end = try reader.u32(group + 4)
                let first = try reader.u32(group + 8)
                guard start <= end, end <= 0x10FFFF else { continue }
                for code in start...end { map[UInt32(code)] = UInt16(truncatingIfNeeded: first + code - start) }
            }
        } else if let subtable = format4 {
            let segments = try reader.u16(subtable + 6) / 2
            let ends = subtable + 14
            let starts = ends + segments * 2 + 2
            let deltas = starts + segments * 2
            let rangeOffsets = deltas + segments * 2
            for segment in 0..<segments {
                let end = try reader.u16(ends + segment * 2)
                let start = try reader.u16(starts + segment * 2)
                let delta = try reader.u16(deltas + segment * 2)
                let rangeOffsetAt = rangeOffsets + segment * 2
                let rangeOffset = try reader.u16(rangeOffsetAt)
                guard start <= end else { continue }
                for code in start...end where code != 0xFFFF {
                    var glyph: Int
                    if rangeOffset == 0 {
                        glyph = (code + delta) & 0xFFFF
                    } else {
                        glyph = try reader.u16(rangeOffsetAt + rangeOffset + (code - start) * 2)
                        if glyph != 0 { glyph = (glyph + delta) & 0xFFFF }
                    }
                    if glyph != 0 { map[UInt32(code)] = UInt16(glyph) }
                }
            }
        } else {
            throw Error.malformed("no Unicode cmap in format 4 or 12")
        }
        return map
    }

    /// The Microsoft 'kern' table (version 0), format 0 subtables, horizontal kerning only;
    /// values add up across subtables unless one overrides, as HarfBuzz applies them.
    private static func readKern(_ reader: Reader, _ kern: Int) throws -> [UInt32: Int] {
        var pairs: [UInt32: Int] = [:]
        guard try reader.u16(kern) == 0 else { return pairs }
        let count = try reader.u16(kern + 2)
        var subtable = kern + 4
        for _ in 0..<count {
            let length = try reader.u16(subtable + 2)
            let coverage = try reader.u16(subtable + 4)
            let format = coverage >> 8
            let horizontal = coverage & 1 != 0
            let minimum = coverage & 2 != 0
            let crossStream = coverage & 4 != 0
            let override = coverage & 8 != 0
            if format == 0 && horizontal && !minimum && !crossStream {
                let pairCount = try reader.u16(subtable + 6)
                for index in 0..<pairCount {
                    let pair = subtable + 14 + index * 6
                    let key = UInt32(try reader.u16(pair)) << 16 | UInt32(try reader.u16(pair + 2))
                    let value = try reader.i16(pair + 4)
                    pairs[key] = override ? value : (pairs[key] ?? 0) + value
                }
            }
            guard length > 0 else { break }
            subtable += length
        }
        return pairs
    }

    /// GPOS pair adjustment in the 'kern' feature: the first value record's XAdvance, which is how
    /// fonts kern horizontally. Lookups apply in list order and add up; within a lookup the first
    /// subtable that applies wins, as in HarfBuzz: a format 1 subtable applies when it lists the
    /// pair, a format 2 subtable whenever it covers the first glyph (its class values, zero or not).
    private struct PairKerning {
        enum Subtable {
            case pairs(coverage: Set<UInt16>, values: [UInt32: Int])
            case classes(coverage: Set<UInt16>, first: [UInt16: Int], second: [UInt16: Int], secondCount: Int, values: [Int])
        }

        let lookups: [[Subtable]]

        /// Nil when GPOS has no lookups at all (HarfBuzz then falls back to 'kern').
        init?(_ reader: Reader, _ gpos: Int) throws {
            let features = gpos + (try reader.u16(gpos + 6))
            let lookupList = gpos + (try reader.u16(gpos + 8))
            let lookupCount = try reader.u16(lookupList)
            guard lookupCount > 0 else { return nil }
            var indices = Set<Int>()
            for index in 0..<(try reader.u16(features)) {
                let record = features + 2 + index * 6
                guard String(decoding: try reader.slice(record, 4), as: UTF8.self) == "kern" else { continue }
                let feature = features + (try reader.u16(record + 4))
                for lookup in 0..<(try reader.u16(feature + 2)) { indices.insert(try reader.u16(feature + 4 + lookup * 2)) }
            }
            var lookups: [[Subtable]] = []
            for index in indices.sorted() where index < lookupCount {
                let lookup = lookupList + (try reader.u16(lookupList + 2 + index * 2))
                let type = try reader.u16(lookup)
                var subtables: [Subtable] = []
                for subtable in 0..<(try reader.u16(lookup + 4)) {
                    var offset = lookup + (try reader.u16(lookup + 6 + subtable * 2))
                    var subtableType = type
                    if type == 9 { // Extension: the real type and a 32-bit offset.
                        subtableType = try reader.u16(offset + 2)
                        offset += try reader.u32(offset + 4)
                    }
                    if subtableType == 2, let pair = try PairKerning.readPairPos(reader, offset) { subtables.append(pair) }
                }
                if !subtables.isEmpty { lookups.append(subtables) }
            }
            self.lookups = lookups
        }

        func value(_ left: Int, _ right: Int) -> Int {
            guard let first = UInt16(exactly: left), let second = UInt16(exactly: right) else { return 0 }
            var total = 0
            for subtables in lookups {
                subtables: for subtable in subtables {
                    switch subtable {
                    case let .pairs(coverage, values):
                        guard coverage.contains(first), let value = values[UInt32(first) << 16 | UInt32(second)] else { continue }
                        total += value
                    case let .classes(coverage, firstClasses, secondClasses, secondCount, values):
                        guard coverage.contains(first) else { continue }
                        total += values[(firstClasses[first] ?? 0) * secondCount + (secondClasses[second] ?? 0)]
                    }
                    break subtables
                }
            }
            return total
        }

        /// PairPos format 1 (pair sets) or 2 (class pairs); nil for any other format.
        private static func readPairPos(_ reader: Reader, _ table: Int) throws -> Subtable? {
            let format = try reader.u16(table)
            let coverage = try readCoverage(reader, table + (try reader.u16(table + 2)))
            let format1 = try reader.u16(table + 4)
            let format2 = try reader.u16(table + 6)
            // Each value record holds one 16-bit field per bit set in the low byte of its format.
            let size1 = (format1 & 0xFF).nonzeroBitCount * 2
            let size2 = (format2 & 0xFF).nonzeroBitCount * 2
            // XAdvance (bit 2) follows XPlacement and YPlacement when they are present.
            let xAdvance: Int? = format1 & 4 != 0 ? (format1 & 3).nonzeroBitCount * 2 : nil
            func advance(_ record: Int) throws -> Int { try xAdvance.map { try reader.i16(record + $0) } ?? 0 }

            switch format {
            case 1:
                var values: [UInt32: Int] = [:]
                let setCount = try reader.u16(table + 8)
                for (glyph, index) in coverage where index < setCount {
                    let set = table + (try reader.u16(table + 10 + index * 2))
                    for pair in 0..<(try reader.u16(set)) {
                        let record = set + 2 + pair * (2 + size1 + size2)
                        values[UInt32(glyph) << 16 | UInt32(try reader.u16(record))] = try advance(record + 2)
                    }
                }
                return .pairs(coverage: Set(coverage.keys), values: values)
            case 2:
                let first = try readClassDef(reader, table + (try reader.u16(table + 8)))
                let second = try readClassDef(reader, table + (try reader.u16(table + 10)))
                let firstCount = try reader.u16(table + 12)
                let secondCount = try reader.u16(table + 14)
                guard firstCount > 0, secondCount > 0 else { return nil }
                var values = [Int](repeating: 0, count: firstCount * secondCount)
                for index in values.indices { values[index] = try advance(table + 16 + index * (size1 + size2)) }
                // A class number past the declared counts reads as class 0, as HarfBuzz does.
                return .classes(coverage: Set(coverage.keys), first: first.filter { $0.value < firstCount },
                                second: second.filter { $0.value < secondCount }, secondCount: secondCount, values: values)
            default:
                return nil
            }
        }

        /// Coverage table: glyph → coverage index.
        private static func readCoverage(_ reader: Reader, _ table: Int) throws -> [UInt16: Int] {
            var coverage: [UInt16: Int] = [:]
            switch try reader.u16(table) {
            case 1:
                for index in 0..<(try reader.u16(table + 2)) { coverage[UInt16(try reader.u16(table + 4 + index * 2))] = index }
            case 2:
                for range in 0..<(try reader.u16(table + 2)) {
                    let record = table + 4 + range * 6
                    let start = try reader.u16(record)
                    let end = try reader.u16(record + 2)
                    let startIndex = try reader.u16(record + 4)
                    guard start <= end else { continue }
                    for glyph in start...end { coverage[UInt16(glyph)] = startIndex + glyph - start }
                }
            default:
                break
            }
            return coverage
        }

        /// Class definition table: glyph → class (glyphs it does not list are class 0).
        private static func readClassDef(_ reader: Reader, _ table: Int) throws -> [UInt16: Int] {
            var classes: [UInt16: Int] = [:]
            switch try reader.u16(table) {
            case 1:
                let start = try reader.u16(table + 2)
                for index in 0..<(try reader.u16(table + 4)) {
                    classes[UInt16(truncatingIfNeeded: start + index)] = try reader.u16(table + 6 + index * 2)
                }
            case 2:
                for range in 0..<(try reader.u16(table + 2)) {
                    let record = table + 4 + range * 6
                    let start = try reader.u16(record)
                    let end = try reader.u16(record + 2)
                    let value = try reader.u16(record + 4)
                    guard start <= end else { continue }
                    for glyph in start...end { classes[UInt16(glyph)] = value }
                }
            default:
                break
            }
            return classes
        }
    }

    private struct Reader {
        let bytes: [UInt8]

        func check(_ offset: Int, _ count: Int) throws {
            guard offset >= 0, offset + count <= bytes.count else { throw Error.malformed("read past the end at \(offset)") }
        }

        func u16(_ offset: Int) throws -> Int {
            try check(offset, 2)
            return Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
        }

        func i16(_ offset: Int) throws -> Int {
            Int(Int16(bitPattern: UInt16(try u16(offset))))
        }

        func u32(_ offset: Int) throws -> Int {
            try check(offset, 4)
            return Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16 | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
        }

        func slice(_ offset: Int, _ count: Int) throws -> ArraySlice<UInt8> {
            try check(offset, count)
            return bytes[offset..<(offset + count)]
        }
    }
}

/// The fonts an SVGCanvas measures with and names: Sundial Condensed (embedded in the SVG, as the app
/// bundles it), the platform serif and sans serif, and a symbol font for the zodiac glyphs that
/// neither has. Any font that cannot be found is approximated from Android's own font's metrics.
public final class SVGFonts {
    public let condensed: TrueTypeFont?
    public let serif: TrueTypeFont?
    public let sans: TrueTypeFont?
    public let symbols: TrueTypeFont?

    /// The family name the embedded Sundial Condensed gets in the SVG's @font-face.
    public static let condensedFamily = "Sundial Condensed"

    public init(condensed: TrueTypeFont? = nil, serif: TrueTypeFont? = nil, sans: TrueTypeFont? = nil,
                symbols: TrueTypeFont? = nil) {
        self.condensed = condensed
        self.serif = serif
        self.sans = sans
        self.symbols = symbols
    }

    /// Android's own fonts first (Noto Serif is its serif, Roboto its sans serif, Noto Sans
    /// Symbols its fallback for the zodiac signs), then the DejaVu fonts most Linux systems have.
    static let serifCandidates = [("NotoSerif-Regular.ttf", "Noto Serif"), ("DejaVuSerif.ttf", "DejaVu Serif")]
    static let sansCandidates = [("Roboto-Regular.ttf", "Roboto"), ("NotoSans-Regular.ttf", "Noto Sans"),
                                 ("DejaVuSans.ttf", "DejaVu Sans")]
    static let symbolCandidates = [("NotoSansSymbols-Regular.ttf", "Noto Sans Symbols"), ("DejaVuSans.ttf", "DejaVu Sans")]
    static let fontDirectories = ["/usr/share/fonts", "/usr/local/share/fonts", "/Library/Fonts", "/System/Library/Fonts"]

    /// sundial_condensed.ttf from [assetsDirectory]; the others from the system font folders.
    public static func load(assetsDirectory: URL?) -> SVGFonts {
        let condensed = assetsDirectory.flatMap {
            try? TrueTypeFont(contentsOf: $0.appendingPathComponent("sundial_condensed.ttf"), family: condensedFamily)
        }
        var files: [String: URL] = [:]
        let wanted = Set((serifCandidates + sansCandidates + symbolCandidates).map(\.0))
        for directory in fontDirectories {
            guard let walker = FileManager.default.enumerator(at: URL(fileURLWithPath: directory),
                                                              includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where wanted.contains(url.lastPathComponent) && files[url.lastPathComponent] == nil {
                files[url.lastPathComponent] = url
            }
        }
        func first(_ candidates: [(String, String)]) -> TrueTypeFont? {
            for (file, family) in candidates {
                if let url = files[file], let font = try? TrueTypeFont(contentsOf: url, family: family) { return font }
            }
            return nil
        }
        return SVGFonts(condensed: condensed, serif: first(serifCandidates), sans: first(sansCandidates),
                        symbols: first(symbolCandidates))
    }

    public func font(_ face: FontFace) -> TrueTypeFont? {
        switch face {
        case .sundialCondensed: return condensed
        case .serif: return serif
        case .sans: return sans
        }
    }

    /// The fonts tried in turn for each character, as Android falls back from a family to the
    /// system's default sans serif and then its symbol fonts.
    func chain(_ face: FontFace) -> [TrueTypeFont] {
        let fonts: [TrueTypeFont?]
        switch face {
        case .sundialCondensed: fonts = [condensed, sans, symbols]
        case .serif: fonts = [serif, symbols, sans]
        case .sans: fonts = [sans, symbols]
        }
        var seen = Set<ObjectIdentifier>()
        return fonts.compactMap { $0 }.filter { seen.insert(ObjectIdentifier($0)).inserted }
    }

    /// The CSS font-family list for [face], in the same order as the measuring chain.
    public func cssFamily(_ face: FontFace) -> String {
        let generic = face == .serif ? "serif" : "sans-serif"
        let names = chain(face).map { "'\($0.family)'" }
        return (names + [generic]).joined(separator: ", ")
    }

    /// Stand-ins when a font is missing: ascent, descent and a typical advance per em, from
    /// Sundial Condensed (878, −210 of 1000), Noto Serif (1069, −293 of 1000) and Roboto (1900, −500 of 2048).
    static func approximation(_ face: FontFace) -> (ascent: Double, descent: Double, advance: Double) {
        switch face {
        case .sundialCondensed: return (0.878, 0.210, 0.42)
        case .serif: return (1.069, 0.293, 0.56)
        case .sans: return (1900 / 2048, 500 / 2048, 0.55)
        }
    }

    /// Paint.getFontMetrics: the family's own font, whatever the text.
    public func metrics(_ face: FontFace, size: Double) -> FontMetrics {
        if let font = font(face) { return font.metrics(size: size) }
        let approximate = SVGFonts.approximation(face)
        return FontMetrics(ascent: -approximate.ascent * size, descent: approximate.descent * size)
    }

    /// Letter spacing in canvas units: Minikin rounds letterSpacing × size to a whole pixel
    /// unless the paint has linear text, which the app's paints do not.
    public static func letterSpace(_ letterSpacing: Double, size: Double) -> Double {
        (letterSpacing * size).rounded()
    }

    /// The advance of [text] as Minikin lays it out, before Paint.measureText's ceil: hinted
    /// (whole-pixel) glyph advances, kerning within a font, and the rounded letter spacing once per
    /// character. Default-ignorable characters (variation selectors, joiners) take no space.
    public func advance(_ text: String, _ face: FontFace, size: Double, letterSpacing: Double) -> Double {
        let space = SVGFonts.letterSpace(letterSpacing, size: size)
        let fonts = chain(face)
        var total = 0.0
        var previous: (font: TrueTypeFont, glyph: Int)?
        for character in text {
            var visible = false
            for scalar in character.unicodeScalars {
                if SVGFonts.isDefaultIgnorable(scalar) { continue }
                visible = true
                if let font = fonts.first(where: { $0.glyph(scalar) != nil }), let glyph = font.glyph(scalar) {
                    let scale = size / Double(font.unitsPerEm)
                    // FreeType's hinted advance: rounded half up to a whole pixel.
                    total += (Double(font.advanceWidth(glyph)) * scale + 0.5).rounded(.down)
                    if let previous, previous.font === font {
                        total += Double(font.kerning(previous.glyph, glyph)) * scale
                    }
                    previous = (font, glyph)
                } else {
                    total += (SVGFonts.approximation(face).advance * size + 0.5).rounded(.down)
                    previous = nil
                }
            }
            if visible { total += space }
        }
        return total
    }

    /// Where Minikin starts each Character's first glyph, from the start of [text], laid out as
    /// advance(_:_:size:letterSpacing:) measures it: half the rounded letter spacing (rounded
    /// down, letterSpaceHalfLeft) before each visible character and the rest after it, kerning
    /// with the glyph before (within a font) moving the glyph, and hinted advances.
    public func origins(_ text: String, _ face: FontFace, size: Double, letterSpacing: Double) -> [Double] {
        let space = SVGFonts.letterSpace(letterSpacing, size: size)
        let halfLeft = (space * 0.5).rounded(.down)
        let fonts = chain(face)
        var total = 0.0
        var origins: [Double] = []
        var previous: (font: TrueTypeFont, glyph: Int)?
        for character in text {
            var origin: Double?
            var visible = false
            for scalar in character.unicodeScalars {
                if SVGFonts.isDefaultIgnorable(scalar) { continue }
                if !visible {
                    visible = true
                    total += halfLeft
                }
                if let font = fonts.first(where: { $0.glyph(scalar) != nil }), let glyph = font.glyph(scalar) {
                    let scale = size / Double(font.unitsPerEm)
                    if let previous, previous.font === font {
                        total += Double(font.kerning(previous.glyph, glyph)) * scale
                    }
                    if origin == nil { origin = total }
                    total += (Double(font.advanceWidth(glyph)) * scale + 0.5).rounded(.down)
                    previous = (font, glyph)
                } else {
                    if origin == nil { origin = total }
                    total += (SVGFonts.approximation(face).advance * size + 0.5).rounded(.down)
                    previous = nil
                }
            }
            if visible { total += space - halfLeft }
            origins.append(origin ?? total)
        }
        return origins
    }

    static func isDefaultIgnorable(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00AD, 0x034F, 0x180B...0x180E, 0x200B...0x200F, 0x202A...0x202E, 0x2060...0x206F,
             0xFE00...0xFE0F, 0xFEFF, 0xE0000...0xE0FFF:
            return true
        default:
            return false
        }
    }
}
