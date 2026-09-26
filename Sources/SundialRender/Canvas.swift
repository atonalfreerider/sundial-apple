@_exported import SundialCore
import Foundation

// The drawing surface the instrument paints on. It follows android.graphics.Canvas closely, so
// the Android instrument ports call for call: y grows down, angles are degrees clockwise from
// 3 o'clock, text sits on a baseline and paints are copied and adjusted. Backends implement only
// the Canvas protocol; circles, arcs, lines and the rest are built from paths below.

// MARK: - Geometry

public struct Point: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
}

/// A rectangle by its edges, like android.graphics.RectF.
public struct Rect: Equatable, Sendable {
    public var left: Double
    public var top: Double
    public var right: Double
    public var bottom: Double

    public init(_ left: Double, _ top: Double, _ right: Double, _ bottom: Double) {
        self.left = left; self.top = top; self.right = right; self.bottom = bottom
    }

    public var width: Double { right - left }
    public var height: Double { bottom - top }
    public var centerX: Double { (left + right) / 2 }
    public var centerY: Double { (top + bottom) / 2 }

    public func contains(_ x: Double, _ y: Double) -> Bool {
        left < right && top < bottom && x >= left && x < right && y >= top && y < bottom
    }

    /// Grows (negative) or shrinks (positive) the rectangle on every side (RectF.inset).
    public func inset(_ dx: Double, _ dy: Double) -> Rect { Rect(left + dx, top + dy, right - dx, bottom - dy) }

    public static func intersects(_ a: Rect, _ b: Rect) -> Bool {
        a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom
    }
}

/// x' = a·x + c·y + tx, y' = b·x + d·y + ty (Core Graphics' convention).
public struct AffineTransform: Equatable, Sendable {
    public var a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double

    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }

    public static let identity = AffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    public static func translation(_ dx: Double, _ dy: Double) -> AffineTransform {
        AffineTransform(a: 1, b: 0, c: 0, d: 1, tx: dx, ty: dy)
    }

    public static func scaling(_ sx: Double, _ sy: Double) -> AffineTransform {
        AffineTransform(a: sx, b: 0, c: 0, d: sy, tx: 0, ty: 0)
    }

    /// Rotation by [degrees], clockwise on a y-down screen.
    public static func rotation(_ degrees: Double) -> AffineTransform {
        let r = degrees * .pi / 180
        return AffineTransform(a: cos(r), b: sin(r), c: -sin(r), d: cos(r), tx: 0, ty: 0)
    }

    /// This transform applied after [first] (so a point goes through [first] then this).
    public func after(_ first: AffineTransform) -> AffineTransform {
        AffineTransform(
            a: a * first.a + c * first.b, b: b * first.a + d * first.b,
            c: a * first.c + c * first.d, d: b * first.c + d * first.d,
            tx: a * first.tx + c * first.ty + tx, ty: b * first.tx + d * first.ty + ty)
    }

    public func apply(_ p: Point) -> Point { Point(a * p.x + c * p.y + tx, b * p.x + d * p.y + ty) }
}

// MARK: - Paths

/// A path of lines and cubic curves. Arcs and circles are flattened to cubics here, in screen
/// coordinates, so every backend draws them the same way.
public struct Path: Sendable {
    public enum Element: Sendable {
        case move(Point)
        case line(Point)
        case cubic(Point, Point, Point)
        case close
    }

    public enum FillRule: Sendable { case winding, evenOdd }

    public private(set) var elements: [Element] = []
    public var fillRule: FillRule = .winding
    private var current: Point?
    private var contourStart: Point?

    public init() {}

    public var isEmpty: Bool { elements.isEmpty }

    public mutating func rewind() {
        elements.removeAll(keepingCapacity: true)
        current = nil
        contourStart = nil
    }

    public mutating func moveTo(_ x: Double, _ y: Double) {
        let p = Point(x, y)
        elements.append(.move(p))
        current = p
        contourStart = p
    }

    public mutating func lineTo(_ x: Double, _ y: Double) {
        if current == nil { moveTo(0, 0) }
        let p = Point(x, y)
        elements.append(.line(p))
        current = p
    }

    public mutating func cubicTo(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x: Double, _ y: Double) {
        if current == nil { moveTo(0, 0) }
        let p = Point(x, y)
        elements.append(.cubic(Point(x1, y1), Point(x2, y2), p))
        current = p
    }

    public mutating func quadTo(_ x1: Double, _ y1: Double, _ x: Double, _ y: Double) {
        let p0 = current ?? Point(0, 0)
        cubicTo(p0.x + 2 / 3 * (x1 - p0.x), p0.y + 2 / 3 * (y1 - p0.y),
                x + 2 / 3 * (x1 - x), y + 2 / 3 * (y1 - y), x, y)
    }

    public mutating func close() {
        guard current != nil else { return }
        elements.append(.close)
        current = contourStart
    }

    /// Adds [sweepAngle] degrees of the ellipse in [oval], from [startAngle], as a new contour
    /// (Path.addArc). Positive sweeps run clockwise on screen.
    public mutating func addArc(_ oval: Rect, _ startAngle: Double, _ sweepAngle: Double) {
        arcTo(oval, startAngle, sweepAngle, forceMoveTo: true)
    }

    /// Path.arcTo: joins the arc to the current point with a line unless [forceMoveTo].
    public mutating func arcTo(_ oval: Rect, _ startAngle: Double, _ sweepAngle: Double, forceMoveTo: Bool) {
        let cx = oval.centerX, cy = oval.centerY, rx = oval.width / 2, ry = oval.height / 2
        func at(_ degrees: Double) -> Point {
            let r = degrees * .pi / 180
            return Point(cx + rx * cos(r), cy + ry * sin(r))
        }
        let start = at(startAngle)
        if forceMoveTo || current == nil { moveTo(start.x, start.y) } else { lineTo(start.x, start.y) }
        guard sweepAngle != 0 else { return }
        let segments = max(1, Int((abs(sweepAngle) / 90).rounded(.up)))
        let step = sweepAngle / Double(segments)
        // Control-point distance for a circular arc of [step] degrees.
        let k = 4.0 / 3.0 * tan(step * .pi / 180 / 4)
        var angle = startAngle
        for _ in 0..<segments {
            let a0 = angle * .pi / 180, a1 = (angle + step) * .pi / 180
            let p0 = Point(cx + rx * cos(a0), cy + ry * sin(a0))
            let p3 = Point(cx + rx * cos(a1), cy + ry * sin(a1))
            cubicTo(p0.x - k * rx * sin(a0), p0.y + k * ry * cos(a0),
                    p3.x + k * rx * sin(a1), p3.y - k * ry * cos(a1),
                    p3.x, p3.y)
            angle += step
        }
    }

    /// A closed ellipse contour (Path.addOval), clockwise unless [counterClockwise].
    public mutating func addOval(_ oval: Rect, counterClockwise: Bool = false) {
        arcTo(oval, 0, counterClockwise ? -360 : 360, forceMoveTo: true)
        close()
    }

    public mutating func addCircle(_ cx: Double, _ cy: Double, _ radius: Double, counterClockwise: Bool = false) {
        addOval(Rect(cx - radius, cy - radius, cx + radius, cy + radius), counterClockwise: counterClockwise)
    }

    public mutating func addRect(_ rect: Rect) {
        moveTo(rect.left, rect.top)
        lineTo(rect.right, rect.top)
        lineTo(rect.right, rect.bottom)
        lineTo(rect.left, rect.bottom)
        close()
    }

    public mutating func addRoundRect(_ rect: Rect, _ rx: Double, _ ry: Double) {
        let rx = min(rx, rect.width / 2), ry = min(ry, rect.height / 2)
        guard rx > 0, ry > 0 else { addRect(rect); return }
        moveTo(rect.left + rx, rect.top)
        lineTo(rect.right - rx, rect.top)
        arcTo(Rect(rect.right - 2 * rx, rect.top, rect.right, rect.top + 2 * ry), -90, 90, forceMoveTo: false)
        lineTo(rect.right, rect.bottom - ry)
        arcTo(Rect(rect.right - 2 * rx, rect.bottom - 2 * ry, rect.right, rect.bottom), 0, 90, forceMoveTo: false)
        lineTo(rect.left + rx, rect.bottom)
        arcTo(Rect(rect.left, rect.bottom - 2 * ry, rect.left + 2 * rx, rect.bottom), 90, 90, forceMoveTo: false)
        lineTo(rect.left, rect.top + ry)
        arcTo(Rect(rect.left, rect.top, rect.left + 2 * rx, rect.top + 2 * ry), 180, 90, forceMoveTo: false)
        close()
    }

    public mutating func addPath(_ other: Path) {
        elements.append(contentsOf: other.elements)
        current = other.current
        contourStart = other.contourStart
    }

    public func transformed(_ t: AffineTransform) -> Path {
        var out = Path()
        out.fillRule = fillRule
        out.elements = elements.map {
            switch $0 {
            case .move(let p): return .move(t.apply(p))
            case .line(let p): return .line(t.apply(p))
            case .cubic(let a, let b, let p): return .cubic(t.apply(a), t.apply(b), t.apply(p))
            case .close: return .close
            }
        }
        out.current = current.map(t.apply)
        out.contourStart = contourStart.map(t.apply)
        return out
    }
}

// MARK: - Paint

public struct Shadow: Equatable, Sendable {
    public var radius: Double
    public var dx: Double
    public var dy: Double
    public var color: ARGB
    public init(radius: Double, dx: Double = 0, dy: Double = 0, color: ARGB) {
        self.radius = radius; self.dx = dx; self.dy = dy; self.color = color
    }
}

/// Gradients with Android's CLAMP tiling. Sweep gradients have no Core Graphics or SVG
/// equivalent, so they are drawn as wedges by Canvas.fillSweep instead.
public enum Shader: Equatable, Sendable {
    case radial(center: Point, radius: Double, colors: [ARGB], stops: [Double]?)
    case linear(start: Point, end: Point, colors: [ARGB], stops: [Double]?)
}

public enum FontFace: Equatable, Sendable {
    /// Franklin Gothic condensed, bundled with the app: the instrument's labels.
    case franklinCondensed
    /// The platform serif, for the zodiac glyphs (Typeface.SERIF).
    case serif
    /// The platform sans serif (Android's default typeface).
    case sans
}

/// A copyable description of how to draw, like android.graphics.Paint.
public struct Paint: Equatable, Sendable {
    public enum Style: Sendable { case fill, stroke }
    public enum Cap: Sendable { case butt, round, square }
    public enum Join: Sendable { case miter, round, bevel }
    public enum Align: Sendable { case left, center, right }

    public var color: ARGB = Colors.black
    public var style: Style = .fill
    /// 0 is a hairline, one device pixel wide, as on Android.
    public var strokeWidth: Double = 0
    public var strokeCap: Cap = .butt
    public var strokeJoin: Join = .miter
    /// Dash and gap lengths (DashPathEffect), or nil for a solid line.
    public var dash: [Double]? = nil
    public var dashPhase: Double = 0
    public var shader: Shader? = nil
    /// setShadowLayer; drawn under text and shapes alike.
    public var shadow: Shadow? = nil
    public var textSize: Double = 12
    public var font: FontFace = .sans
    public var textAlign: Align = .left
    /// Extra space between letters in ems (Paint.letterSpacing).
    public var letterSpacing: Double = 0

    public init(color: ARGB = Colors.black, style: Style = .fill, strokeWidth: Double = 0) {
        self.color = color
        self.style = style
        self.strokeWidth = strokeWidth
    }

    /// Like Paint.setAlpha: keeps the colour, replaces its alpha.
    public var alpha: Int {
        get { Colors.alpha(color) }
        set { color = (color & 0x00FF_FFFF) | ARGB(max(0, min(255, newValue))) << 24 }
    }
}

/// Paint.FontMetrics: ascent is negative (above the baseline), descent positive.
public struct FontMetrics: Equatable, Sendable {
    public var ascent: Double
    public var descent: Double
    public var leading: Double
    public init(ascent: Double, descent: Double, leading: Double = 0) {
        self.ascent = ascent; self.descent = descent; self.leading = leading
    }
    /// Recommended distance between baselines (Paint.getFontSpacing).
    public var fontSpacing: Double { descent - ascent + leading }
}

// MARK: - Images

/// An image as straight (not premultiplied) 0xAARRGGBB pixels, row by row, like the IntArray the
/// Android renderers fill. A class, so backends can cache what they build from each one.
public final class PixelImage {
    public let width: Int
    public let height: Int
    public var pixels: [ARGB]

    public init(width: Int, height: Int, pixels: [ARGB]) {
        precondition(pixels.count == width * height)
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public convenience init(width: Int, height: Int) {
        self.init(width: width, height: height, pixels: Array(repeating: 0, count: width * height))
    }
}

// MARK: - Canvas

public protocol Canvas: AnyObject {
    var width: Double { get }
    var height: Double { get }

    /// Pushes the matrix and clip; returns the count to pass to restore(toCount:).
    @discardableResult func save() -> Int
    /// Like save(), and everything drawn until the matching restore is composited at [alpha]
    /// (0...1) as one layer (saveLayerAlpha).
    @discardableResult func saveLayer(alpha: Double) -> Int
    func restore()
    func restore(toCount: Int)
    var saveCount: Int { get }

    /// Device pixels per canvas unit under the current transform, so rasterised effects (sweep
    /// gradients) come out sharp at any zoom.
    var pixelScale: Double { get }

    func translate(_ dx: Double, _ dy: Double)
    /// Clockwise degrees about the origin.
    func rotate(_ degrees: Double)
    func scale(_ sx: Double, _ sy: Double)
    func concat(_ transform: AffineTransform)
    func clip(_ path: Path)

    func drawPath(_ path: Path, _ paint: Paint)
    /// Text on a baseline at y; x is the left, centre or right per paint.textAlign.
    func drawText(_ text: String, _ x: Double, _ y: Double, _ paint: Paint)
    /// Draws [image] scaled into [rect] with bitmap filtering, at [alpha] (0...1).
    func drawImage(_ image: PixelImage, _ rect: Rect, alpha: Double)
    /// Fills the whole canvas (within the clip) with [color].
    func drawColor(_ color: ARGB)

    /// Advance width of [text], letter spacing included (Paint.measureText).
    func measureText(_ text: String, _ paint: Paint) -> Double
    func fontMetrics(_ paint: Paint) -> FontMetrics
}

public extension Canvas {
    func rotate(_ degrees: Double, _ px: Double, _ py: Double) {
        translate(px, py)
        rotate(degrees)
        translate(-px, -py)
    }

    func scale(_ sx: Double, _ sy: Double, _ px: Double, _ py: Double) {
        translate(px, py)
        scale(sx, sy)
        translate(-px, -py)
    }

    func drawCircle(_ cx: Double, _ cy: Double, _ radius: Double, _ paint: Paint) {
        guard radius > 0 else { return }
        var path = Path()
        path.addCircle(cx, cy, radius)
        drawPath(path, paint)
    }

    func drawLine(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ paint: Paint) {
        var path = Path()
        path.moveTo(x0, y0)
        path.lineTo(x1, y1)
        var stroke = paint
        stroke.style = .stroke
        drawPath(path, stroke)
    }

    func drawRect(_ rect: Rect, _ paint: Paint) {
        var path = Path()
        path.addRect(rect)
        drawPath(path, paint)
    }

    func drawRect(_ left: Double, _ top: Double, _ right: Double, _ bottom: Double, _ paint: Paint) {
        drawRect(Rect(left, top, right, bottom), paint)
    }

    func drawOval(_ oval: Rect, _ paint: Paint) {
        var path = Path()
        path.addOval(oval)
        drawPath(path, paint)
    }

    func drawRoundRect(_ rect: Rect, _ rx: Double, _ ry: Double, _ paint: Paint) {
        var path = Path()
        path.addRoundRect(rect, rx, ry)
        drawPath(path, paint)
    }

    /// Canvas.drawArc. With [useCenter] the arc is closed through the centre (a wedge).
    func drawArc(_ oval: Rect, _ startAngle: Double, _ sweepAngle: Double, _ useCenter: Bool, _ paint: Paint) {
        var path = Path()
        if useCenter {
            path.moveTo(oval.centerX, oval.centerY)
            path.arcTo(oval, startAngle, sweepAngle, forceMoveTo: false)
            path.close()
        } else {
            path.addArc(oval, startAngle, sweepAngle)
        }
        drawPath(path, paint)
    }

    /// A sweep gradient (SweepGradient) over the ring between [innerRadius] and [outerRadius]
    /// (0 for a disc): [colors] run clockwise from 3 o'clock at [positions] (0...1, or evenly).
    /// Neither Core Graphics nor SVG has sweep gradients, and wedges would show seams in a
    /// translucent band, so it is rendered as an antialiased image at the canvas's pixel scale.
    func fillSweep(center: Point, innerRadius: Double, outerRadius: Double, colors: [ARGB], positions: [Double]? = nil) {
        guard colors.count >= 2, outerRadius > innerRadius else { return }
        // Round the scale up to a quarter step so a cached image serves small zoom changes.
        let scale = max(0.25, (pixelScale * 4).rounded(.up) / 4)
        let image = SweepGradientImages.image(innerRadius: innerRadius, outerRadius: outerRadius, colors: colors,
                                              positions: positions, scale: scale)
        let half = outerRadius + 1 / scale
        drawImage(image, Rect(center.x - half, center.y - half, center.x + half, center.y + half), alpha: 1)
    }
}

/// The last few sweep-gradient rings, which change only with the season or the zoom.
enum SweepGradientImages {
    private struct Key: Hashable {
        let inner: Double, outer: Double, colors: [ARGB], positions: [Double]?, scale: Double
    }

    private static var cache: [(Key, PixelImage)] = []
    private static let lock = NSLock()

    static func image(innerRadius: Double, outerRadius: Double, colors: [ARGB], positions: [Double]?,
                      scale: Double) -> PixelImage {
        let key = Key(inner: innerRadius, outer: outerRadius, colors: colors, positions: positions, scale: scale)
        lock.lock()
        if let index = cache.firstIndex(where: { $0.0 == key }) {
            let hit = cache.remove(at: index)
            cache.append(hit)
            lock.unlock()
            return hit.1
        }
        lock.unlock()
        let image = render(key)
        lock.lock()
        cache.append((key, image))
        if cache.count > 6 { cache.removeFirst() }
        lock.unlock()
        return image
    }

    private static func render(_ key: Key) -> PixelImage {
        let stops = key.positions ?? key.colors.indices.map { Double($0) / Double(key.colors.count - 1) }
        let colors = key.colors
        func colorAt(_ t: Double) -> (Double, Double, Double, Double) {
            func parts(_ c: ARGB) -> (Double, Double, Double, Double) {
                (Double(Colors.alpha(c)), Double(Colors.red(c)), Double(Colors.green(c)), Double(Colors.blue(c)))
            }
            if t <= stops[0] { return parts(colors[0]) }
            for i in 1..<stops.count where t <= stops[i] {
                let span = stops[i] - stops[i - 1]
                let f = span > 0 ? (t - stops[i - 1]) / span : 0
                let a = parts(colors[i - 1]), b = parts(colors[i])
                return (a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f, a.2 + (b.2 - a.2) * f, a.3 + (b.3 - a.3) * f)
            }
            return parts(colors[colors.count - 1])
        }
        let half = key.outer + 1 / key.scale
        let size = max(2, Int((2 * half * key.scale).rounded(.up)))
        let unit = 2 * half / Double(size)
        var pixels = [ARGB](repeating: 0, count: size * size)
        for py in 0..<size {
            let y = (Double(py) + 0.5) * unit - half
            for px in 0..<size {
                let x = (Double(px) + 0.5) * unit - half
                let distance = (x * x + y * y).squareRoot()
                // Antialiased edges: coverage across one device pixel at each rim.
                var coverage = min(1, max(0, (key.outer - distance) / unit + 0.5))
                if key.inner > 0 { coverage *= min(1, max(0, (distance - key.inner) / unit + 0.5)) }
                if coverage <= 0 { continue }
                var degrees = atan2(y, x) * 180 / .pi
                if degrees < 0 { degrees += 360 }
                let c = colorAt(degrees / 360)
                pixels[py * size + px] = Colors.argb(Int((c.0 * coverage).rounded()), Int(c.1.rounded()),
                                                     Int(c.2.rounded()), Int(c.3.rounded()))
            }
        }
        return PixelImage(width: size, height: size, pixels: pixels)
    }
}
