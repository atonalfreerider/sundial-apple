import Foundation
import SundialRender

/// Foundation has an AffineTransform of its own; this module means the Canvas one.
typealias AffineTransform = SundialRender.AffineTransform

/// A Canvas that writes SVG, so the instrument can be rendered on any platform (Linux included)
/// for previews, store art and side-by-side comparisons with the Android app.
///
/// Every element carries the full current transform, so stroke widths, dashes, gradients, shadow
/// blurs and text sizes live in the same local coordinates as on Android. Clips are stored in
/// device coordinates and layers are groups: save() starts a new level, clip() and
/// saveLayer(alpha:) open a <g> on it, and restore() closes that level's groups.
///
/// - Paths: fill or stroke, width (0 is a hairline one device pixel wide), cap, join, dash.
/// - Shaders: radial and linear gradients in <defs>, userSpaceOnUse with pad spread (CLAMP).
/// - Shadows: a blurred copy under the element (feGaussianBlur), drawn in the shadow colour as
///   Android's hardware renderer draws a shadow layer, with Skia's radius-to-sigma conversion.
/// - Text: <text> with the font family, size, fill and shadow, each character placed at Minikin's
///   position for it (textAlign and letter spacing included); Sundial Condensed is embedded as an
///   @font-face so any renderer draws the real font.
/// - Images: PNG data URIs in <defs>, each distinct image once, drawn with <use>.
public final class SVGCanvas: Canvas {
    public let width: Double
    public let height: Double
    public let fonts: SVGFonts

    private struct SavedState {
        let transform: AffineTransform
        let openGroups: Int
    }

    private var transform = AffineTransform.identity
    /// Groups (clips and layers) opened since the last save, which the matching restore closes.
    private var openGroups = 0
    private var stack: [SavedState] = []

    private var body = ""
    private var defs = ""
    private var nextId = 0
    /// Gradient and filter markup (without its id) → id, so identical definitions are shared.
    private var definitions: [String: String] = [:]
    private var images: [ImageKey: String] = [:]
    private var usesCondensed = false

    private struct ImageKey: Hashable {
        let width: Int
        let height: Int
        let pixels: [ARGB]
    }

    public init(width: Double, height: Double, fonts: SVGFonts = SVGFonts()) {
        self.width = width
        self.height = height
        self.fonts = fonts
    }

    // MARK: Output

    /// The document so far. Groups still open (unbalanced saves) are closed in the output only.
    public func svgString() -> String {
        var out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        out += "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\""
        out += " width=\"\(SVGCanvas.number(width))\" height=\"\(SVGCanvas.number(height))\""
        out += " viewBox=\"0 0 \(SVGCanvas.number(width)) \(SVGCanvas.number(height))\" xml:space=\"preserve\">\n"
        if usesCondensed, let condensed = fonts.condensed {
            out += "<style>@font-face{font-family:'\(SVGFonts.condensedFamily)';src:url(data:font/ttf;base64,"
            out += condensed.data.base64EncodedString()
            out += ") format('truetype');}</style>\n"
        }
        if !defs.isEmpty { out += "<defs>\n" + defs + "</defs>\n" }
        out += body
        let unclosed = openGroups + stack.reduce(0) { $0 + $1.openGroups }
        out += String(repeating: "</g>", count: unclosed)
        out += "</svg>\n"
        return out
    }

    // MARK: State

    @discardableResult public func save() -> Int {
        let count = saveCount
        stack.append(SavedState(transform: transform, openGroups: openGroups))
        openGroups = 0
        return count
    }

    @discardableResult public func saveLayer(alpha: Double) -> Int {
        let count = save()
        body += "<g opacity=\"\(SVGCanvas.opacity(alpha))\">\n"
        openGroups += 1
        return count
    }

    /// Like Android, restoring past the first level does nothing (Android would throw).
    public func restore() {
        guard let saved = stack.popLast() else { return }
        if openGroups > 0 { body += String(repeating: "</g>", count: openGroups) + "\n" }
        transform = saved.transform
        openGroups = saved.openGroups
    }

    public func restore(toCount: Int) {
        while saveCount > max(1, toCount) { restore() }
    }

    /// Starts at 1, as Canvas.getSaveCount does.
    public var saveCount: Int { stack.count + 1 }

    /// The current transform's scale: device pixels (SVG units) per canvas unit.
    public var pixelScale: Double {
        abs(transform.a * transform.d - transform.b * transform.c).squareRoot()
    }

    public func translate(_ dx: Double, _ dy: Double) { concat(.translation(dx, dy)) }
    public func rotate(_ degrees: Double) { concat(.rotation(degrees)) }
    public func scale(_ sx: Double, _ sy: Double) { concat(.scaling(sx, sy)) }

    /// Pre-concatenates, as Canvas.concat: [t] applies to points before the current transform.
    public func concat(_ t: SundialRender.AffineTransform) { transform = transform.after(t) }

    /// Intersects the clip with [path] (clipPath, antialiased like Android's).
    public func clip(_ path: Path) {
        let id = newId("c")
        let rule = path.fillRule == .evenOdd ? " clip-rule=\"evenodd\"" : ""
        defs += "<clipPath id=\"\(id)\"><path d=\"\(SVGCanvas.pathData(path.transformed(transform)))\"\(rule)/></clipPath>\n"
        body += "<g clip-path=\"url(#\(id))\">\n"
        openGroups += 1
    }

    // MARK: Drawing

    public func drawPath(_ path: Path, _ paint: Paint) {
        guard !path.isEmpty else { return }
        let d = SVGCanvas.pathData(path)
        let rule = path.fillRule == .evenOdd && paint.style == .fill ? " fill-rule=\"evenodd\"" : ""
        if let shadow = SVGCanvas.shadowLayer(paint) {
            let pad = paint.style == .stroke ? 2 * max(paint.strokeWidth, hairline) : 0
            let region = SVGCanvas.bounds(path).map { Rect($0.left - pad, $0.top - pad, $0.right + pad, $0.bottom + pad) }
            let filter = blurFilter(shadow, region ?? Rect(0, 0, 0, 0))
            body += "<path d=\"\(d)\"\(rule)\(paintAttributes(paint, color: shadow.color))"
            body += " filter=\"url(#\(filter))\"\(SVGCanvas.transformAttribute(shadowTransform(shadow)))/>\n"
        }
        guard Colors.alpha(paint.color) > 0 else { return }
        body += "<path d=\"\(d)\"\(rule)\(paintAttributes(paint, color: paint.color))\(SVGCanvas.transformAttribute(transform))/>\n"
    }

    public func drawText(_ text: String, _ x: Double, _ y: Double, _ paint: Paint) {
        guard !text.isEmpty, paint.textSize > 0 else { return }
        if let shadow = SVGCanvas.shadowLayer(paint) { writeText(text, x, y, paint, shadow: shadow) }
        guard Colors.alpha(paint.color) > 0 else { return }
        writeText(text, x, y, paint, shadow: nil)
    }

    public func drawTextShadow(_ text: String, _ x: Double, _ y: Double, _ paint: Paint) {
        guard !text.isEmpty, paint.textSize > 0, let shadow = SVGCanvas.shadowLayer(paint) else { return }
        writeText(text, x, y, paint, shadow: shadow)
    }

    /// One <text>, in the paint's colour or, with [shadow], as the blurred shadow copy. Each
    /// character is placed where Minikin puts it (SVGFonts.origins: hinted whole-pixel advances,
    /// kerning, rounded letter spacing), and the run is aligned on its unrounded advance, as
    /// Android aligns; the renderer's own advances would drift from measureText's.
    private func writeText(_ text: String, _ x: Double, _ y: Double, _ paint: Paint, shadow: Shadow?) {
        let size = paint.textSize
        let alignment: Double
        switch paint.textAlign {
        case .left: alignment = 0
        case .center: alignment = 0.5
        case .right: alignment = 1
        }
        if paint.font == .sundialCondensed && fonts.condensed != nil { usesCondensed = true }
        let advance = fonts.advance(text, paint.font, size: size, letterSpacing: paint.letterSpacing)
        let left = x - advance * alignment
        let origins = fonts.origins(text, paint.font, size: size, letterSpacing: paint.letterSpacing)
        let characters = Array(text)
        // Chrome honours xml:space only on the <text> itself, not inherited from the root, and
        // would otherwise collapse runs of spaces.
        var attributes = " xml:space=\"preserve\""
        let content: String
        if characters.allSatisfy({ $0.unicodeScalars.count == 1 }) {
            // One x per code point, which is one per character here.
            let xs = origins.map { SVGCanvas.number(left + $0) }.joined(separator: " ")
            attributes += " x=\"\(xs)\" y=\"\(SVGCanvas.number(y))\""
            content = SVGCanvas.escape(text)
        } else {
            // A renderer applies x values per code point, so a list would split clusters (a
            // variation selector, a joiner, a combining mark): one <tspan> per character instead,
            // with nothing between them.
            attributes += " x=\"\(SVGCanvas.number(left))\" y=\"\(SVGCanvas.number(y))\""
            var spans = ""
            for (character, origin) in zip(characters, origins) where !character.isWhitespace {
                spans += "<tspan x=\"\(SVGCanvas.number(left + origin))\">\(SVGCanvas.escape(String(character)))</tspan>"
            }
            content = spans
        }
        attributes += " font-family=\"\(SVGCanvas.escape(fonts.cssFamily(paint.font)))\""
        attributes += " font-size=\"\(SVGCanvas.number(size))\""
        if let shadow {
            // Generous: glyphs overhang their advances, and fallback glyphs can be tall.
            let region = Rect(left - size, y - 1.5 * size, left + advance + size, y + size)
            let filter = blurFilter(shadow, region)
            body += "<text\(attributes)\(paintAttributes(paint, color: shadow.color)) filter=\"url(#\(filter))\""
            body += "\(SVGCanvas.transformAttribute(shadowTransform(shadow)))>\(content)</text>\n"
        } else {
            body += "<text\(attributes)\(paintAttributes(paint, color: paint.color))\(SVGCanvas.transformAttribute(transform))>"
            body += "\(content)</text>\n"
        }
    }

    public func drawImage(_ image: PixelImage, _ rect: Rect, alpha: Double) {
        guard image.width > 0, image.height > 0, rect.width != 0, rect.height != 0, alpha > 0 else { return }
        let key = ImageKey(width: image.width, height: image.height, pixels: image.pixels)
        let id: String
        if let existing = images[key] {
            id = existing
        } else {
            id = newId("i")
            images[key] = id
            defs += "<image id=\"\(id)\" width=\"\(image.width)\" height=\"\(image.height)\" preserveAspectRatio=\"none\""
            defs += " xlink:href=\"data:image/png;base64,\(PNG.encode(image).base64EncodedString())\"/>\n"
        }
        let placement = AffineTransform.translation(rect.left, rect.top)
            .after(.scaling(rect.width / Double(image.width), rect.height / Double(image.height)))
        let opacity = alpha < 1 ? " opacity=\"\(SVGCanvas.opacity(alpha))\"" : ""
        body += "<use xlink:href=\"#\(id)\"\(SVGCanvas.transformAttribute(transform.after(placement)))\(opacity)/>\n"
    }

    /// A rectangle over the whole canvas in device coordinates, inside the current clip and layers.
    public func drawColor(_ color: ARGB) {
        guard Colors.alpha(color) > 0 else { return }
        body += "<rect width=\"\(SVGCanvas.number(width))\" height=\"\(SVGCanvas.number(height))\""
        body += " fill=\"\(SVGCanvas.hex(color))\"\(SVGCanvas.opacityAttribute("fill-opacity", color))/>\n"
    }

    // MARK: Text metrics

    /// Paint.measureText: Minikin's advance, rounded up to a whole unit as Android does.
    public func measureText(_ text: String, _ paint: Paint) -> Double {
        guard !text.isEmpty else { return 0 }
        return fonts.advance(text, paint.font, size: paint.textSize, letterSpacing: paint.letterSpacing).rounded(.up)
    }

    /// Minikin's advance, unrounded (the widths StaticLayout and TextUtils measure with).
    public func textAdvance(_ text: String, _ paint: Paint) -> Double {
        guard !text.isEmpty else { return 0 }
        return fonts.advance(text, paint.font, size: paint.textSize, letterSpacing: paint.letterSpacing)
    }

    public func fontMetrics(_ paint: Paint) -> FontMetrics {
        fonts.metrics(paint.font, size: paint.textSize)
    }

    // MARK: Paint

    /// One device pixel in local units, for strokeWidth 0.
    private var hairline: Double {
        let scale = pixelScale
        return scale > 0 ? 1 / scale : 1
    }

    /// Fill or stroke attributes for [paint] drawn in [color] (the paint's own, or its shadow's).
    /// With a shader the colour's RGB is ignored and its alpha scales the gradient, as in Skia.
    private func paintAttributes(_ paint: Paint, color: ARGB) -> String {
        let reference = paint.shader.map { "url(#\(gradient($0)))" } ?? SVGCanvas.hex(color)
        switch paint.style {
        case .fill:
            return " fill=\"\(reference)\"\(SVGCanvas.opacityAttribute("fill-opacity", color))"
        case .stroke:
            var out = " fill=\"none\" stroke=\"\(reference)\"\(SVGCanvas.opacityAttribute("stroke-opacity", color))"
            out += " stroke-width=\"\(SVGCanvas.precise(paint.strokeWidth > 0 ? paint.strokeWidth : hairline))\""
            switch paint.strokeCap {
            case .butt: break
            case .round: out += " stroke-linecap=\"round\""
            case .square: out += " stroke-linecap=\"square\""
            }
            switch paint.strokeJoin {
            case .miter: break
            case .round: out += " stroke-linejoin=\"round\""
            case .bevel: out += " stroke-linejoin=\"bevel\""
            }
            if let dash = paint.dash, !dash.isEmpty, dash.allSatisfy({ $0 >= 0 }), dash.reduce(0, +) > 0 {
                out += " stroke-dasharray=\"\(dash.map { SVGCanvas.number($0) }.joined(separator: ","))\""
                if paint.dashPhase != 0 { out += " stroke-dashoffset=\"\(SVGCanvas.number(paint.dashPhase))\"" }
            }
            return out
        }
    }

    /// The gradient's id, defining it on first use. Its coordinates are the drawing's local ones,
    /// as an Android shader's are.
    private func gradient(_ shader: Shader) -> String {
        let colors: [ARGB]
        let stops: [Double]?
        var markup: String
        switch shader {
        case let .radial(center, radius, radialColors, radialStops):
            colors = radialColors
            stops = radialStops
            markup = "<radialGradient gradientUnits=\"userSpaceOnUse\" cx=\"\(SVGCanvas.number(center.x))\""
            markup += " cy=\"\(SVGCanvas.number(center.y))\" r=\"\(SVGCanvas.number(radius))\" spreadMethod=\"pad\">"
        case let .linear(start, end, linearColors, linearStops):
            colors = linearColors
            stops = linearStops
            markup = "<linearGradient gradientUnits=\"userSpaceOnUse\" x1=\"\(SVGCanvas.number(start.x))\""
            markup += " y1=\"\(SVGCanvas.number(start.y))\" x2=\"\(SVGCanvas.number(end.x))\" y2=\"\(SVGCanvas.number(end.y))\""
            markup += " spreadMethod=\"pad\">"
        }
        // Without positions the colours are spread evenly, as Android does with null positions.
        // SVG interpolates straight colour and Android premultiplied, so the stops are rewritten
        // to give Android's fades (GradientStops).
        let premultiplied = GradientStops.premultiplied(colors, stops)
        for (color, offset) in zip(premultiplied.colors, premultiplied.positions) {
            markup += "<stop offset=\"\(SVGCanvas.precise(min(max(offset, 0), 1)))\" stop-color=\"\(SVGCanvas.hex(color))\""
            markup += "\(SVGCanvas.opacityAttribute("stop-opacity", color))/>"
        }
        switch shader {
        case .radial: markup += "</radialGradient>"
        case .linear: markup += "</linearGradient>"
        }
        return define(markup, prefix: "g")
    }

    /// Paint.setShadowLayer: a radius of 0 or less means no shadow.
    private static func shadowLayer(_ paint: Paint) -> Shadow? {
        guard let shadow = paint.shadow, shadow.radius > 0 else { return nil }
        return shadow
    }

    /// The shadow copy is drawn offset by (dx, dy) in local coordinates.
    private func shadowTransform(_ shadow: Shadow) -> AffineTransform {
        transform.after(.translation(shadow.dx, shadow.dy))
    }

    /// A Gaussian blur over [bounds] (local coordinates) grown to hold the blur's tails. Android
    /// converts the radius to a sigma as 0.57735 × radius + 0.5 (Blur::convertRadiusToSigma).
    private func blurFilter(_ shadow: Shadow, _ bounds: Rect) -> String {
        let sigma = 0.57735 * shadow.radius + 0.5
        let margin = 3 * sigma + 1
        var markup = "<filter filterUnits=\"userSpaceOnUse\" x=\"\(SVGCanvas.number(bounds.left - margin))\""
        markup += " y=\"\(SVGCanvas.number(bounds.top - margin))\" width=\"\(SVGCanvas.number(bounds.width + 2 * margin))\""
        markup += " height=\"\(SVGCanvas.number(bounds.height + 2 * margin))\" color-interpolation-filters=\"sRGB\">"
        markup += "<feGaussianBlur stdDeviation=\"\(SVGCanvas.precise(sigma))\"/></filter>"
        return define(markup, prefix: "f")
    }

    /// Adds [markup] (an element without an id) to <defs> once and returns its id.
    private func define(_ markup: String, prefix: String) -> String {
        if let id = definitions[markup] { return id }
        let id = newId(prefix)
        definitions[markup] = id
        // Insert the id after the element name.
        let nameEnd = markup.firstIndex(of: " ") ?? markup.endIndex
        defs += String(markup[..<nameEnd]) + " id=\"\(id)\"" + String(markup[nameEnd...]) + "\n"
        return id
    }

    private func newId(_ prefix: String) -> String {
        nextId += 1
        return prefix + String(nextId)
    }

    // MARK: Formatting

    /// The bounding box of the path's points and control points (which contain its curves).
    static func bounds(_ path: Path) -> Rect? {
        var points: [Point] = []
        for element in path.elements {
            switch element {
            case .move(let p), .line(let p): points.append(p)
            case .cubic(let a, let b, let p): points += [a, b, p]
            case .close: break
            }
        }
        guard let first = points.first else { return nil }
        var box = Rect(first.x, first.y, first.x, first.y)
        for p in points {
            box.left = min(box.left, p.x); box.top = min(box.top, p.y)
            box.right = max(box.right, p.x); box.bottom = max(box.bottom, p.y)
        }
        return box
    }

    static func pathData(_ path: Path) -> String {
        var d = ""
        for element in path.elements {
            switch element {
            case .move(let p): d += "M\(number(p.x)),\(number(p.y))"
            case .line(let p): d += "L\(number(p.x)),\(number(p.y))"
            case let .cubic(a, b, p):
                d += "C\(number(a.x)),\(number(a.y)) \(number(b.x)),\(number(b.y)) \(number(p.x)),\(number(p.y))"
            case .close: d += "Z"
            }
        }
        return d
    }

    static func transformAttribute(_ t: AffineTransform) -> String {
        if t == .identity { return "" }
        return " transform=\"matrix(\(precise(t.a)) \(precise(t.b)) \(precise(t.c)) \(precise(t.d)) \(number(t.tx)) \(number(t.ty)))\""
    }

    static func opacityAttribute(_ name: String, _ color: ARGB) -> String {
        let alpha = Colors.alpha(color)
        return alpha == 255 ? "" : " \(name)=\"\(opacity(Double(alpha) / 255))\""
    }

    static func opacity(_ value: Double) -> String { format(min(max(value, 0), 1), places: 4) }

    static func hex(_ color: ARGB) -> String {
        let digits = Array("0123456789abcdef")
        var out = "#"
        for shift in stride(from: 20, through: 0, by: -4) { out.append(digits[Int((color >> UInt32(shift)) & 0xF)]) }
        return out
    }

    /// Coordinates: three decimals (a thousandth of a pixel), trailing zeros dropped.
    static func number(_ value: Double) -> String { format(value, places: 3) }

    /// Scale factors, widths and offsets that are multiplied up: six decimals.
    static func precise(_ value: Double) -> String { format(value, places: 6) }

    static func format(_ value: Double, places: Int) -> String {
        guard value.isFinite else { return "0" }
        var unit: Int64 = 1
        for _ in 0..<places { unit *= 10 }
        let scaled = (value * Double(unit)).rounded()
        guard abs(scaled) < 9e15 else { return String(value) }
        let whole = Int64(scaled)
        let magnitude = whole < 0 ? -whole : whole
        var out = whole < 0 ? "-" : ""
        out += String(magnitude / unit)
        var fraction = magnitude % unit
        if fraction != 0 {
            var digits = places
            while fraction % 10 == 0 { fraction /= 10; digits -= 1 }
            let text = String(fraction)
            out += "." + String(repeating: "0", count: digits - text.count) + text
        }
        return out
    }

    /// Escapes text for XML content and attribute values, dropping characters XML 1.0 forbids.
    static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.utf8.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default:
                let v = scalar.value
                let allowed = v == 0x9 || v == 0xA || v == 0xD || (v >= 0x20 && v <= 0xD7FF)
                    || (v >= 0xE000 && v <= 0xFFFD) || v >= 0x10000
                if allowed { out.unicodeScalars.append(scalar) }
            }
        }
        return out
    }
}
