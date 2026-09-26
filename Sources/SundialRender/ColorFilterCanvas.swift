import Foundation

/// A colour transform (android.graphics.ColorMatrixColorFilter): a 4 × 5 matrix in Android's
/// ColorMatrix layout, applied to straight (unpremultiplied) components in 0...255:
///
///     R' = a·R + b·G + c·B + d·A + e
///     G' = f·R + g·G + h·B + i·A + j
///     B' = k·R + l·G + m·B + n·A + o
///     A' = p·R + q·G + r·B + s·A + t
///
/// The results are clamped to 0...255 and rounded to the nearest integer, as Skia does.
public struct ColorFilter: Hashable, Sendable {
    /// Row-major, 20 entries, as ColorMatrix.getArray().
    public let matrix: [Float]

    public init(matrix: [Float]) {
        precondition(matrix.count == 20, "a colour matrix has 20 entries")
        self.matrix = matrix
    }

    public func apply(_ color: ARGB) -> ARGB {
        let r = Float(Colors.red(color))
        let g = Float(Colors.green(color))
        let b = Float(Colors.blue(color))
        let a = Float(Colors.alpha(color))
        func channel(_ row: Int) -> Int {
            let m = matrix
            let value = m[row] * r + m[row + 1] * g + m[row + 2] * b + m[row + 3] * a + m[row + 4]
            return Int((min(max(value, 0), 255) + 0.5).rounded(.down))
        }
        return Colors.argb(channel(15), channel(0), channel(5), channel(10))
    }

    /// The always-on display's ink, SundialView's ambientPaint:
    /// `ColorMatrix().apply { setSaturation(0f); postConcat(ColorMatrix().apply { setScale(.55f, .55f, .55f, 1f) }) }`.
    /// setSaturation(0) turns every channel into the luminance 0.213 R + 0.715 G + 0.072 B; the
    /// scale, concatenated after it, multiplies each colour row by .55 and leaves alpha alone. The
    /// entries are the Float products ColorMatrix.setConcat computes.
    public static let ambientGrey: ColorFilter = {
        // setSaturation(0f): invSat = 1, so R = 0.213f, G = 0.715f, B = 0.072f in every colour row.
        let red: Float = 0.213
        let green: Float = 0.715
        let blue: Float = 0.072
        let scale: Float = 0.55
        let r = scale * red
        let g = scale * green
        let b = scale * blue
        return ColorFilter(matrix: [
            r, g, b, 0, 0,
            r, g, b, 0, 0,
            r, g, b, 0, 0,
            0, 0, 0, 1, 0,
        ])
    }()
}

/// A Canvas that draws into [base] through a ColorFilter. Android dims the always-on display by
/// drawing into a layer composited through a colour filter (saveLayer(null, ambientPaint)); here
/// every colour is filtered on its way to the base canvas instead: paint colours, gradient
/// colours, shadows, drawColor and image pixels. The matrix acts on each colour independently of
/// its alpha, so filtering before compositing gives the same picture as filtering the layer.
/// Transforms, layers, clips, measuring and the pixel scale are the base canvas's own.
public final class ColorFilterCanvas: Canvas {
    public let base: Canvas
    public let filter: ColorFilter

    public init(_ base: Canvas, filter: ColorFilter) {
        self.base = base
        self.filter = filter
    }

    public var width: Double { base.width }
    public var height: Double { base.height }

    @discardableResult public func save() -> Int { base.save() }
    @discardableResult public func saveLayer(alpha: Double) -> Int { base.saveLayer(alpha: alpha) }
    public func restore() { base.restore() }
    public func restore(toCount: Int) { base.restore(toCount: toCount) }
    public var saveCount: Int { base.saveCount }

    public var pixelScale: Double { base.pixelScale }

    public func translate(_ dx: Double, _ dy: Double) { base.translate(dx, dy) }
    public func rotate(_ degrees: Double) { base.rotate(degrees) }
    public func scale(_ sx: Double, _ sy: Double) { base.scale(sx, sy) }
    public func concat(_ transform: AffineTransform) { base.concat(transform) }
    public func clip(_ path: Path) { base.clip(path) }

    public func drawPath(_ path: Path, _ paint: Paint) { base.drawPath(path, filtered(paint)) }

    public func drawText(_ text: String, _ x: Double, _ y: Double, _ paint: Paint) {
        base.drawText(text, x, y, filtered(paint))
    }

    public func drawImage(_ image: PixelImage, _ rect: Rect, alpha: Double) {
        base.drawImage(FilteredImages.image(image, filter), rect, alpha: alpha)
    }

    public func drawColor(_ color: ARGB) { base.drawColor(filter.apply(color)) }

    public func drawTextShadow(_ text: String, _ x: Double, _ y: Double, _ paint: Paint) {
        base.drawTextShadow(text, x, y, filtered(paint))
    }

    /// Forwarded whole, so a backend that shapes the arc label itself still does.
    public func drawTextOnArc(_ text: String, cx: Double, cy: Double, radius: Double, startAngle: Double,
                              clockwise: Bool, vOffset: Double, _ paint: Paint) {
        base.drawTextOnArc(text, cx: cx, cy: cy, radius: radius, startAngle: startAngle, clockwise: clockwise,
                           vOffset: vOffset, filtered(paint))
    }

    public func measureText(_ text: String, _ paint: Paint) -> Double { base.measureText(text, paint) }
    public func textAdvance(_ text: String, _ paint: Paint) -> Double { base.textAdvance(text, paint) }
    public func fontMetrics(_ paint: Paint) -> FontMetrics { base.fontMetrics(paint) }

    /// [paint] with its colour, gradient colours and shadow colour passed through the filter.
    func filtered(_ paint: Paint) -> Paint {
        var out = paint
        out.color = filter.apply(paint.color)
        switch paint.shader {
        case .radial(let center, let radius, let colors, let stops)?:
            out.shader = .radial(center: center, radius: radius, colors: colors.map(filter.apply), stops: stops)
        case .linear(let start, let end, let colors, let stops)?:
            out.shader = .linear(start: start, end: end, colors: colors.map(filter.apply), stops: stops)
        case nil:
            break
        }
        if let shadow = paint.shadow {
            out.shadow = Shadow(radius: shadow.radius, dx: shadow.dx, dy: shadow.dy, color: filter.apply(shadow.color))
        }
        return out
    }
}

/// Filtered copies of the last few images drawn through a ColorFilterCanvas. The instrument makes
/// a new ColorFilterCanvas every frame but draws the same cached globe, Moon and gradient images,
/// so each is filtered once, and backends that cache per image see the same filtered instance.
/// An entry lasts only as long as its source (the renderers keep a few frames), so an image they
/// have dropped is not kept alive here; Android keeps no filtered copies at all.
enum FilteredImages {
    private final class Entry {
        weak var source: PixelImage?
        /// The source's pixels when it was filtered: an edit to them copies the source's buffer, so
        /// a changed image no longer matches (and an unchanged one compares by buffer, at no cost).
        let sourcePixels: [ARGB]
        let filter: ColorFilter
        let image: PixelImage

        init(source: PixelImage, sourcePixels: [ARGB], filter: ColorFilter, image: PixelImage) {
            self.source = source
            self.sourcePixels = sourcePixels
            self.filter = filter
            self.image = image
        }
    }

    /// A safety bound: each always-on frame filters three images (the sweep ring, the Moon and the
    /// Earth), and the entries of dropped sources are pruned first.
    static let capacity = 8
    private static var cache: [Entry] = []
    private static let lock = NSLock()

    /// Forgets every filtered copy (the always-on display ended).
    static func removeAll() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    static func image(_ source: PixelImage, _ filter: ColorFilter) -> PixelImage {
        lock.lock()
        cache.removeAll { $0.source == nil }
        if let index = cache.firstIndex(where: { $0.source === source && $0.filter == filter && $0.sourcePixels == source.pixels }) {
            let hit = cache.remove(at: index)
            cache.append(hit)
            lock.unlock()
            return hit.image
        }
        lock.unlock()
        let pixels = source.pixels
        let image = PixelImage(width: source.width, height: source.height, pixels: pixels.map(filter.apply))
        lock.lock()
        cache.removeAll { $0.source === source && $0.filter == filter }
        cache.append(Entry(source: source, sourcePixels: pixels, filter: filter, image: image))
        if cache.count > capacity { cache.removeFirst() }
        lock.unlock()
        return image
    }
}
