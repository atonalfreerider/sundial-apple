// Canvas on Core Graphics, with Core Text for the labels: how the iOS and watchOS apps draw the
// instrument. Apple platforms only; on Linux this file compiles to nothing and renders go through
// SundialSVG instead.
//
// Every Core Graphics call here assumes a user space that is y-down with its origin at the top
// left, as UIKit and SwiftUI hand it over. Paths are already flattened to lines and cubics in
// screen coordinates by SundialRender's Path, so they need no flipping; the places where Core
// Graphics or Core Text still assume a y-up space (glyphs, images, shadows) say so where they are
// handled.

#if canImport(CoreGraphics) && canImport(CoreText)
import CoreGraphics
import CoreText
import Foundation
import SundialRender
#if canImport(UIKit)
import UIKit
#endif

// SundialRender's Rect, Point, Path and AffineTransform are written with their module name in
// this file: Foundation, and Darwin's MacTypes under it, have types of the same names on Apple
// platforms.

/// Canvas on a Core Graphics context whose user space is y-down with the origin at the top left,
/// as UIKit (UIView.draw, UIGraphicsImageRenderer) and SwiftUI (GraphicsContext.withCGContext)
/// provide it. As on Android, angles run clockwise on screen, text sits on a baseline and a stroke
/// width of 0 is a one-pixel hairline.
///
/// Drawing the instrument in SwiftUI: a Canvas lends its graphics context to Core Graphics
/// through withCGContext, in the Canvas's points, y-down and the size of the Canvas. Pass the
/// view's display scale, so hairlines and rasterised sweep gradients stay one device pixel sharp
/// even if that context reports its device space in points:
///
///     struct InstrumentView: View {
///         let instrument: Instrument
///         @Environment(\.displayScale) private var displayScale
///
///         var body: some View {
///             TimelineView(.animation) { _ in
///                 Canvas { context, size in
///                     context.withCGContext { cg in
///                         let canvas = CGCanvas(context: cg, width: Double(size.width),
///                                               height: Double(size.height), displayScale: displayScale)
///                         instrument.draw(canvas)
///                     }
///                 }
///             }
///         }
///     }
///
/// (instrument.nextRedrawDelay says how soon the next frame is wanted; a host can use it to pause
/// the TimelineView.) A UIView does the same in draw(_:) with UIGraphicsGetCurrentContext(), whose
/// device space is already in pixels.
public final class CGCanvas: Canvas {
    public let context: CGContext
    public let width: Double
    public let height: Double
    public let fonts: FontLibrary

    /// One entry per save() or saveLayer(alpha:) not yet restored: true for a layer.
    private var saves: [Bool] = []
    /// The context's user-to-device transform when the canvas was made, before any Canvas
    /// transform: the host's own frame, which shadows are expressed in.
    private let hostTransform: CGAffineTransform
    /// Extra device pixels per device unit when the context's device space is coarser than the
    /// display (1 for bitmap and layer contexts, whose device space is pixels already).
    private let displayScaleFactor: Double
    /// Device pixels per canvas unit before any Canvas transform: the pixels Android's text and
    /// shadow rounding works in (its canvas is in view pixels).
    private let unitPixels: Double
    /// Whether the context's base space, where Core Graphics reads shadow offsets and blurs, is
    /// its device space (a bitmap context made with CGContext(data:…): y-up pixels) rather than
    /// the host's user space (UIKit's views and image renderers, a SwiftUI Canvas).
    private let shadowsInDeviceSpace: Bool

    /// [displayScale] is the screen's pixels per point. It only matters for a context that records
    /// in points rather than rasterising in pixels; the default trusts the context.
    /// [shadowsInDeviceSpace]: the context is a plain bitmap context, whose shadows are set in its
    /// device pixels (y up) rather than in the host's y-down user space.
    public init(context: CGContext, width: Double, height: Double, fonts: FontLibrary = .shared,
                displayScale: Double = 1, shadowsInDeviceSpace: Bool = false) {
        self.context = context
        self.width = width
        self.height = height
        self.fonts = fonts
        self.shadowsInDeviceSpace = shadowsInDeviceSpace
        hostTransform = context.userSpaceToDeviceSpaceTransform
        let hostScale = CGCanvas.scale(of: hostTransform)
        displayScaleFactor = hostScale > 0 ? max(1, displayScale / hostScale) : 1
        let pixels = hostScale * displayScaleFactor
        unitPixels = pixels > 0 ? pixels : 1
    }

    // MARK: State

    /// Android counts the base state as 1: save() returns the count to restore to.
    public var saveCount: Int { saves.count + 1 }

    @discardableResult public func save() -> Int {
        let count = saveCount
        // saveGState pushes the CTM, clip, colours, line and shadow settings, as Canvas.save does
        // for the matrix and clip.
        context.saveGState()
        saves.append(false)
        return count
    }

    @discardableResult public func saveLayer(alpha: Double) -> Int {
        let count = saveCount
        context.saveGState()
        // A transparency layer is composited, when it ends, with the global alpha that was set
        // when it began; inside it the alpha starts again at 1, as in Android's offscreen layer.
        context.setAlpha(CGFloat(min(max(alpha, 0), 1)))
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        saves.append(true)
        return count
    }

    public func restore() {
        // Android throws on an unbalanced restore; here it is ignored, so the host's state is kept.
        guard let isLayer = saves.popLast() else { return }
        if isLayer { context.endTransparencyLayer() }
        context.restoreGState()
    }

    public func restore(toCount count: Int) {
        while saveCount > max(1, count) { restore() }
    }

    /// Device pixels per canvas unit, from the context's user-to-device transform (which includes
    /// the host's screen scale and every Canvas transform). A rotation leaves it unchanged; an
    /// uneven scale gives the geometric mean of the two axes.
    public var pixelScale: Double {
        CGCanvas.scale(of: context.userSpaceToDeviceSpaceTransform) * displayScaleFactor
    }

    private static func scale(of t: CGAffineTransform) -> Double {
        Double(abs(t.a * t.d - t.b * t.c)).squareRoot()
    }

    // MARK: Transforms

    public func translate(_ dx: Double, _ dy: Double) {
        context.translateBy(x: CGFloat(dx), y: CGFloat(dy))
    }

    /// CGContext.rotate turns user space from +x towards +y (the matrix cos, sin, −sin, cos, the
    /// same as AffineTransform.rotation). Apple's documentation calls a positive angle
    /// counterclockwise, which holds in a y-up space; in this y-down space +y points down the
    /// screen, so a positive angle turns clockwise on screen, as Canvas.rotate does.
    public func rotate(_ degrees: Double) {
        context.rotate(by: CGFloat(degrees * .pi / 180))
    }

    public func scale(_ sx: Double, _ sy: Double) {
        context.scaleBy(x: CGFloat(sx), y: CGFloat(sy))
    }

    /// Both AffineTransform and CGAffineTransform map x' = a·x + c·y + tx, y' = b·x + d·y + ty, and
    /// concatenate applies the new transform to points before the current CTM, as Canvas.concat
    /// (a pre-concatenation) does.
    public func concat(_ transform: SundialRender.AffineTransform) {
        context.concatenate(CGAffineTransform(a: CGFloat(transform.a), b: CGFloat(transform.b),
                                              c: CGFloat(transform.c), d: CGFloat(transform.d),
                                              tx: CGFloat(transform.tx), ty: CGFloat(transform.ty)))
    }

    public func clip(_ path: SundialRender.Path) {
        // An empty path clips everything away, as Canvas.clipPath with an empty path does.
        guard !path.isEmpty else {
            context.clip(to: CGRect.zero)
            return
        }
        context.beginPath()
        context.addPath(CGCanvas.makePath(path))
        context.clip(using: CGCanvas.fillRule(path))
    }

    // MARK: Drawing

    public func drawPath(_ path: SundialRender.Path, _ paint: Paint) {
        guard !path.isEmpty else { return }
        let cgPath = CGCanvas.makePath(path)
        context.saveGState()
        if let shader = paint.shader {
            // Android modulates a shader by the paint's alpha (its colour is otherwise unused).
            if paint.alpha < 255 { context.setAlpha(CGFloat(paint.alpha) / 255) }
            // The gradient is drawn clipped to the shape, and a clip would cut its shadow off too;
            // drawn in a transparency layer, the shadow is cast by the finished shape instead,
            // when the layer is composited.
            //
            // Unsupported: Android casts a gradient's shadow as the blurred gradient at the
            // shadow's alpha (BlurDrawLooper keeps the shader); Core Graphics casts it in the
            // shadow colour, scaled by the paint's alpha. No instrument paint has both.
            let shadowed = applyGradientShadow(paint)
            if shadowed { context.beginTransparencyLayer(auxiliaryInfo: nil) }
            context.saveGState()
            context.beginPath()
            context.addPath(cgPath)
            if paint.style == .stroke {
                // The stroke's outline, with this paint's width, caps, joins and dashes, becomes
                // the area the gradient fills. The outline is filled with the winding rule, so
                // overlapping parts of the stroke are covered once.
                applyStroke(paint)
                context.replacePathWithStrokedPath()
                context.clip(using: .winding)
            } else {
                context.clip(using: CGCanvas.fillRule(path))
            }
            drawGradient(shader)
            context.restoreGState()
            if shadowed { context.endTransparencyLayer() }
        } else {
            drawWithShadow(paint) { argb in
                let color = CGCanvas.cgColor(argb)
                context.beginPath()
                context.addPath(cgPath)
                if paint.style == .stroke {
                    applyStroke(paint)
                    context.setStrokeColor(color)
                    context.strokePath()
                } else {
                    context.setFillColor(color)
                    context.fillPath(using: CGCanvas.fillRule(path))
                }
            }
        }
        context.restoreGState()
    }

    public func drawImage(_ image: PixelImage, _ rect: SundialRender.Rect, alpha: Double) {
        guard alpha > 0, rect.width > 0, rect.height > 0,
              let cgImage = CGImageCache.shared.cgImage(for: image) else { return }
        context.saveGState()
        context.setAlpha(CGFloat(min(alpha, 1)))
        // Bitmap filtering (Paint.FILTER_BITMAP_FLAG).
        context.interpolationQuality = .high
        // CGContext.draw puts the image's first row at the rectangle's maximum y, the top of a
        // y-up space. Here maximum y is the bottom of the screen, so the image is drawn through a
        // local flip about the rectangle: local y 0 is the rectangle's bottom edge and local y
        // `height` its top, where the first row then lands, right side up.
        context.translateBy(x: CGFloat(rect.left), y: CGFloat(rect.bottom))
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(rect.width), height: CGFloat(rect.height)))
        context.restoreGState()
    }

    public func drawColor(_ color: ARGB) {
        // Canvas.drawColor paints the whole clip (source-over). The clip's bounding box, in the
        // current user space, covers it; the fill is clipped to its exact shape.
        var area = context.boundingBoxOfClipPath
        if area.isNull || area.isEmpty { return }
        if area.isInfinite {
            // A context without a finite clip: the canvas rectangle, carried from the host's
            // frame into the current user space.
            let toUser = hostTransform.concatenating(context.userSpaceToDeviceSpaceTransform.inverted())
            area = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)).applying(toUser)
        }
        context.saveGState()
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.setFillColor(CGCanvas.cgColor(color))
        context.fill(area)
        context.restoreGState()
    }

    // MARK: Text

    /// Letter spacing as Minikin applies it: letterSpacing × textSize rounded to a whole Android
    /// pixel (the app's paints have no LINEAR_TEXT_FLAG), in those pixels.
    private func letterSpacePixels(_ paint: Paint) -> Double {
        (paint.letterSpacing * paint.textSize * unitPixels).rounded()
    }

    /// [text] laid out with the rounded letter spacing as its kern.
    private func layoutLine(_ text: String, _ paint: Paint) -> CTLine {
        fonts.line(text, paint, kern: letterSpacePixels(paint) / unitPixels)
    }

    /// Where the line starts for textAlign at [x]: aligned on its advance (letter spacing
    /// included, as Android aligns), then moved right by Minikin's letterSpaceHalfLeft. Core
    /// Text's kern adds the whole spacing after each character (the last one included, which is
    /// why the advances agree); Minikin puts floor(spacing / 2) pixels before each character and
    /// the rest after, so a centred label's ink stays centred.
    private func lineStart(_ line: CTLine, _ x: Double, _ paint: Paint) -> Double {
        let advance = CTLineGetTypographicBounds(line, nil, nil, nil)
        var left = x
        switch paint.textAlign {
        case .left: break
        case .center: left -= advance / 2
        case .right: left -= advance
        }
        return left + (letterSpacePixels(paint) * 0.5).rounded(.down) / unitPixels
    }

    /// Draws [line] with its baseline starting at (left, y) in [argb], filled or outlined per the
    /// paint. The caller saves the graphics state and the text matrix around it.
    private func showLine(_ line: CTLine, _ left: Double, _ y: Double, _ paint: Paint, _ argb: ARGB) {
        // The line takes its colour from the context (kCTForegroundColorFromContextAttributeName),
        // so one laid-out line serves every colour. Text is filled, or outlined for a stroke paint.
        let color = CGCanvas.cgColor(argb)
        context.setFillColor(color)
        if paint.style == .stroke {
            applyStroke(paint)
            context.setStrokeColor(color)
            context.setTextDrawingMode(.stroke)
        } else {
            context.setTextDrawingMode(.fill)
        }
        // Glyphs are y-up. In this y-down user space they would stand upside down, so the text
        // matrix flips them back (y → −y), and the text position puts the baseline's start at
        // (left, y): with that matrix, ascenders rise towards smaller y, above the baseline, as on
        // Android.
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: CGFloat(left), y: CGFloat(y))
        CTLineDraw(line, context)
    }

    public func drawText(_ text: String, _ x: Double, _ y: Double, _ paint: Paint) {
        guard !text.isEmpty, paint.textSize > 0 else { return }
        let line = layoutLine(text, paint)
        let left = lineStart(line, x, paint)
        context.saveGState()
        // The text matrix is not part of the graphics state, so it is put back by hand.
        let hostTextMatrix = context.textMatrix
        drawWithShadow(paint) { argb in showLine(line, left, y, paint, argb) }
        context.textMatrix = hostTextMatrix
        context.restoreGState()
    }

    public func drawTextShadow(_ text: String, _ x: Double, _ y: Double, _ paint: Paint) {
        guard !text.isEmpty, paint.textSize > 0, let shadow = paint.shadow, shadow.radius > 0 else { return }
        let line = layoutLine(text, paint)
        let left = lineStart(line, x, paint)
        context.saveGState()
        let hostTextMatrix = context.textMatrix
        drawShadowOnly(shadow) { showLine(line, left, y, paint, paint.color | 0xFF00_0000) }
        context.textMatrix = hostTextMatrix
        context.restoreGState()
    }

    /// drawTextOnPath along a circular arc, shaped as Minikin shapes it: one Core Text line for
    /// the whole label (bidi, joining, ligatures, kerning, fallback fonts), each glyph then placed
    /// on the arc in visual order at its centre, hOffset + x + advance / 2 (Skia's
    /// drawLayoutOnPath), turned to the tangent there and drawn in its run's own font. As
    /// Android draws the run as one blob, its shadow is cast once under all of it.
    public func drawTextOnArc(_ text: String, cx: Double, cy: Double, radius: Double, startAngle: Double,
                              clockwise: Bool, vOffset: Double, _ paint: Paint) {
        guard !text.isEmpty, radius > 0, paint.textSize > 0 else { return }
        let line = layoutLine(text, paint)
        let direction = clockwise ? 1.0 : -1.0
        // Minikin puts letterSpaceHalfLeft before each glyph; Core Text's positions do not.
        let halfSpacing = (letterSpacePixels(paint) * 0.5).rounded(.down) / unitPixels
        var placed: [(font: CTFont, glyph: CGGlyph, x: Double, y: Double, rotation: Double, left: Double,
                      rise: Double)] = []
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            // The run's own font: a fallback font where the label's font has no glyph.
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let font: CTFont
            if let value = attributes[kCTFontAttributeName as String] {
                font = value as! CTFont
            } else {
                font = fonts.font(paint.font, paint.textSize)
            }
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            var advances = [CGSize](repeating: .zero, count: count)
            let all = CFRange(location: 0, length: 0)
            CTRunGetGlyphs(run, all, &glyphs)
            CTRunGetPositions(run, all, &positions)
            CTRunGetAdvances(run, all, &advances)
            for index in 0..<count {
                // Positions are along the line, left to right whatever the run's direction.
                let halfWidth = Double(advances[index].width) / 2
                let centre = Double(positions[index].x) + halfSpacing + halfWidth
                let angle = startAngle + direction * centre / radius * 180 / .pi
                let a = angle * .pi / 180
                placed.append((font, glyphs[index], cx + cos(a) * radius, cy + sin(a) * radius,
                                angle + direction * 90, -halfWidth, Double(positions[index].y)))
            }
        }
        context.saveGState()
        let hostTextMatrix = context.textMatrix
        let shadowed = paint.shadow.map { $0.radius > 0 } ?? false
        drawWithShadow(paint) { argb in
            // With a shadow the glyphs go into one transparency layer, which casts the shadow
            // once as it is composited: no glyph's shadow falls across its neighbour.
            if shadowed { context.beginTransparencyLayer(auxiliaryInfo: nil) }
            let color = CGCanvas.cgColor(argb)
            context.setFillColor(color)
            if paint.style == .stroke {
                applyStroke(paint)
                context.setStrokeColor(color)
                context.setTextDrawingMode(.stroke)
            } else {
                context.setTextDrawingMode(.fill)
            }
            // Glyphs are y-up; the text matrix flips them upright in this y-down space (see
            // showLine). Each glyph's origin is reached through the CTM, so it is drawn at (0, 0),
            // where text space and user space agree.
            context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            for glyph in placed {
                context.saveGState()
                context.translateBy(x: CGFloat(glyph.x), y: CGFloat(glyph.y))
                context.rotate(by: CGFloat(glyph.rotation * .pi / 180))
                // Core Text's y is up: a raised glyph (a mark) sits above the baseline.
                context.translateBy(x: CGFloat(glyph.left), y: CGFloat(vOffset - glyph.rise))
                var id = glyph.glyph
                var origin = CGPoint.zero
                CTFontDrawGlyphs(glyph.font, &id, &origin, 1, context)
                context.restoreGState()
            }
            if shadowed { context.endTransparencyLayer() }
        }
        context.textMatrix = hostTextMatrix
        context.restoreGState()
    }

    /// Paint.measureText: the advance (letter spacing included) rounded up to a whole Android
    /// pixel, as Android's measureText is (Math.ceil).
    public func measureText(_ text: String, _ paint: Paint) -> Double {
        (textAdvance(text, paint) * unitPixels).rounded(.up) / unitPixels
    }

    /// The typographic advance of the line, letter spacing included, unrounded (Minikin's layout
    /// width). Core Text's glyph advances are not hinted to whole pixels as Android's are, so
    /// this approximates Android's rather than matching it exactly.
    public func textAdvance(_ text: String, _ paint: Paint) -> Double {
        guard !text.isEmpty, paint.textSize > 0 else { return 0 }
        return CTLineGetTypographicBounds(layoutLine(text, paint), nil, nil, nil)
    }

    /// Core Text reports the ascent above the baseline as a positive distance; Android's is
    /// negative (y grows down), so it is negated. Descent and leading are positive in both.
    public func fontMetrics(_ paint: Paint) -> FontMetrics {
        guard paint.textSize > 0 else { return FontMetrics(ascent: 0, descent: 0, leading: 0) }
        let font = fonts.font(paint.font, paint.textSize)
        return FontMetrics(ascent: -Double(CTFontGetAscent(font)), descent: Double(CTFontGetDescent(font)),
                           leading: Double(CTFontGetLeading(font)))
    }

    // MARK: Paint

    /// Stroke width, caps, joins and dashes into the graphics state.
    private func applyStroke(_ paint: Paint) {
        // A width of 0 is Android's hairline: one device pixel whatever the transform.
        let scale = pixelScale
        let width = paint.strokeWidth > 0 ? paint.strokeWidth : 1 / (scale > 0 ? scale : 1)
        context.setLineWidth(CGFloat(width))
        switch paint.strokeCap {
        case .butt: context.setLineCap(.butt)
        case .round: context.setLineCap(.round)
        case .square: context.setLineCap(.square)
        }
        switch paint.strokeJoin {
        case .miter: context.setLineJoin(.miter)
        case .round: context.setLineJoin(.round)
        case .bevel: context.setLineJoin(.bevel)
        }
        // Android's default miter limit is 4 (Core Graphics' is 10).
        context.setMiterLimit(4)
        // Dash lengths are in user space in both, and the phase is the distance into the pattern.
        if let dash = paint.dash, !dash.isEmpty {
            context.setLineDash(phase: CGFloat(paint.dashPhase), lengths: dash.map { CGFloat($0) })
        } else {
            context.setLineDash(phase: 0, lengths: [])
        }
    }

    /// Sets [shadow] in the graphics state in [color], offset by (dx, dy) canvas units.
    ///
    /// setShadow takes its offset and blur in the context's base space, which the CTM does not
    /// reach. In UIKit's contexts that base space is the view's own y-down points (UIKit sets the
    /// screen scale and the flip below the CTM, which is why shadow offsets there point down for a
    /// positive height and do not grow on a Retina screen), and a SwiftUI Canvas lends its context
    /// in the same points. Android's shadow follows the canvas matrix, so the offset and blur are
    /// carried through the Canvas transforms made since the host handed the context over, and set
    /// in the host's points; or, for a plain bitmap context ([shadowsInDeviceSpace]), through the
    /// whole CTM into its device pixels.
    ///
    /// The blur: Android turns the radius into a Gaussian sigma of 0.57735 × radius + 0.5
    /// (Blur::convertRadiusToSigma, the 0.5 in its pixels), and Core Graphics' blur is about
    /// twice the sigma (the canvas shadowBlur convention, which WebKit passes straight through).
    private func setShadow(_ shadow: Shadow, dx: Double, dy: Double, color: CGColor) {
        let toBase = shadowsInDeviceSpace
            ? context.userSpaceToDeviceSpaceTransform
            : context.userSpaceToDeviceSpaceTransform.concatenating(hostTransform.inverted())
        let offset = CGSize(width: CGFloat(dx), height: CGFloat(dy)).applying(toBase)
        let sigma = 0.57735 * shadow.radius + 0.5 / unitPixels
        let blur = 2 * sigma * CGCanvas.scale(of: toBase)
        context.setShadow(offset: offset, blur: CGFloat(blur), color: color)
    }

    private func clearShadow() {
        context.setShadow(offset: .zero, blur: 0, color: nil)
    }

    /// Runs [draw] (which paints in the colour it is given) with the paint's shadow
    /// (setShadowLayer; a radius of 0 means none), as hwui's BlurDrawLooper draws it: the shadow in
    /// the shadow's colour at the shadow's own alpha, whatever the paint's alpha. Core Graphics
    /// multiplies the shadow's alpha by the alpha of what casts it, so for a translucent paint
    /// whose alpha is at least the shadow's, the shadow colour's alpha is divided by the paint's;
    /// otherwise (a paint more transparent than its shadow, or invisible) the shadow is cast by an
    /// opaque copy drawn off the canvas, and the paint drawn after it without a shadow.
    private func drawWithShadow(_ paint: Paint, _ draw: (ARGB) -> Void) {
        guard let shadow = paint.shadow, shadow.radius > 0 else {
            clearShadow()
            draw(paint.color)
            return
        }
        let paintAlpha = paint.alpha
        let shadowAlpha = Colors.alpha(shadow.color)
        if paintAlpha == 255 || (paintAlpha > 0 && shadowAlpha <= paintAlpha) {
            setShadow(shadow, dx: shadow.dx, dy: shadow.dy,
                      color: CGCanvas.cgColor(shadow.color, alphaScale: 255 / Double(paintAlpha)))
            draw(paint.color)
        } else {
            drawShadowOnly(shadow) { draw(paint.color | 0xFF00_0000) }
            clearShadow()
            if paintAlpha > 0 { draw(paint.color) }
        }
    }

    /// Only the shadow [draw] casts: the shape is moved far past the canvas, and the shadow's
    /// offset brings the shadow back to where the unmoved shape would cast it. A clip cannot do
    /// this, as it would clip the shadow too.
    private func drawShadowOnly(_ shadow: Shadow, _ draw: () -> Void) {
        context.saveGState()
        let relative = context.userSpaceToDeviceSpaceTransform.concatenating(hostTransform.inverted())
        // Four times the canvas's width and height, in the host's units, carried into local units.
        let distance = 4 * (width + height) / max(CGCanvas.scale(of: relative), 1e-6)
        context.translateBy(x: CGFloat(distance), y: 0)
        setShadow(shadow, dx: shadow.dx - distance, dy: shadow.dy, color: CGCanvas.cgColor(shadow.color))
        draw()
        context.restoreGState()
    }

    /// The shadow for a gradient paint, in the shadow's colour (see drawPath); true if set.
    @discardableResult private func applyGradientShadow(_ paint: Paint) -> Bool {
        guard let shadow = paint.shadow, shadow.radius > 0 else {
            clearShadow()
            return false
        }
        setShadow(shadow, dx: shadow.dx, dy: shadow.dy, color: CGCanvas.cgColor(shadow.color))
        return true
    }

    /// Fills the current clip with the gradient. Android's CLAMP tiling carries the end colours on
    /// past the gradient's ends, as the before-start and after-end options do.
    private func drawGradient(_ shader: Shader) {
        let options: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        switch shader {
        case let .radial(center, radius, colors, stops):
            guard radius > 0, let gradient = CGCanvas.makeGradient(colors, stops) else { return }
            let point = CGPoint(x: CGFloat(center.x), y: CGFloat(center.y))
            context.drawRadialGradient(gradient, startCenter: point, startRadius: 0, endCenter: point,
                                       endRadius: CGFloat(radius), options: options)
        case let .linear(start, end, colors, stops):
            guard let gradient = CGCanvas.makeGradient(colors, stops) else { return }
            context.drawLinearGradient(gradient, start: CGPoint(x: CGFloat(start.x), y: CGFloat(start.y)),
                                       end: CGPoint(x: CGFloat(end.x), y: CGFloat(end.y)), options: options)
        }
    }

    // MARK: Conversions

    static let sRGB: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    /// Android colours are sRGB with straight alpha; [alphaScale] multiplies the alpha (to 1 at
    /// most).
    static func cgColor(_ color: ARGB, alphaScale: Double = 1) -> CGColor {
        CGColor(srgbRed: CGFloat(Colors.red(color)) / 255, green: CGFloat(Colors.green(color)) / 255,
                blue: CGFloat(Colors.blue(color)) / 255,
                alpha: CGFloat(min(1, Double(Colors.alpha(color)) / 255 * alphaScale)))
    }

    /// Stops are the gradient's locations; without them the colours are spread evenly, as Android
    /// does for a null array. Core Graphics interpolates unpremultiplied colours while Android
    /// interpolates premultiplied (a fade to transparent keeps its hue), so the stops are
    /// rewritten by GradientStops to give Android's result.
    static func makeGradient(_ colors: [ARGB], _ stops: [Double]?) -> CGGradient? {
        let premultiplied = GradientStops.premultiplied(colors, stops)
        let cgColors = premultiplied.colors.map { cgColor($0) } as CFArray
        let locations = premultiplied.positions.map { CGFloat($0) }
        return CGGradient(colorsSpace: sRGB, colors: cgColors, locations: locations)
    }

    static func fillRule(_ path: SundialRender.Path) -> CGPathFillRule {
        path.fillRule == .evenOdd ? .evenOdd : .winding
    }

    /// The path's lines and cubics as they are: its points are already in y-down canvas units.
    static func makePath(_ path: SundialRender.Path) -> CGPath {
        let cgPath = CGMutablePath()
        func cg(_ p: SundialRender.Point) -> CGPoint { CGPoint(x: CGFloat(p.x), y: CGFloat(p.y)) }
        for element in path.elements {
            switch element {
            case .move(let p): cgPath.move(to: cg(p))
            case .line(let p): cgPath.addLine(to: cg(p))
            case .cubic(let c1, let c2, let p): cgPath.addCurve(to: cg(p), control1: cg(c1), control2: cg(c2))
            case .close: cgPath.closeSubpath()
            }
        }
        return cgPath
    }
}

// MARK: - Images

/// CGImages built from PixelImages, each kept only as long as its image. The renderers make a new
/// PixelImage whenever the picture changes (as the Android ones make a new Bitmap), so an image's
/// pixels are taken as fixed once it has been drawn.
final class CGImageCache: @unchecked Sendable {
    static let shared = CGImageCache()

    private final class Entry {
        weak var image: PixelImage?
        let cgImage: CGImage
        init(_ image: PixelImage, _ cgImage: CGImage) {
            self.image = image
            self.cgImage = cgImage
        }
    }

    private let lock = NSLock()
    private var entries: [ObjectIdentifier: Entry] = [:]

    func cgImage(for image: PixelImage) -> CGImage? {
        let id = ObjectIdentifier(image)
        lock.lock()
        defer { lock.unlock() }
        // The weak reference tells a live image from a new one at a freed image's address.
        if let entry = entries[id], entry.image === image { return entry.cgImage }
        entries = entries.filter { $0.value.image != nil }
        guard let cgImage = CGImageCache.makeImage(image) else { return nil }
        entries[id] = Entry(image, cgImage)
        return cgImage
    }

    /// The pixels are 0xAARRGGBB words in memory order, little-endian on every Apple device: read
    /// as 32-bit little-endian words with alpha in the most significant byte (alpha first),
    /// straight rather than premultiplied, exactly as PixelImage holds them. Row 0 is the top row.
    static func makeImage(_ image: PixelImage) -> CGImage? {
        guard image.width > 0, image.height > 0 else { return nil }
        let data = image.pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.first.rawValue)
        return CGImage(width: image.width, height: image.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: image.width * 4, space: CGCanvas.sRGB, bitmapInfo: bitmapInfo,
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

// MARK: - Fonts

/// The fonts CGCanvas draws with: Sundial Condensed (bundled with the app) for the
/// instrument's labels, the system serif design for the zodiac glyphs (Android's Typeface.SERIF)
/// and the system font for everything else (Android's default typeface). It also keeps the lines
/// Core Text lays out, since the instrument draws the same labels frame after frame.
public final class FontLibrary: @unchecked Sendable {
    /// sundial_condensed.ttf's PostScript name (its name table, name ID 6).
    public static let condensedPostScriptName = "SundialCondensed"

    /// Fonts from the main bundle. Each target that draws the instrument (the iOS app, its widget
    /// extension, the watch app) must copy sundial_condensed.ttf into its own bundle; without it
    /// the labels fall back to the system font.
    public static let shared = FontLibrary(condensedURL: Bundle.main.url(forResource: "sundial_condensed",
                                                                        withExtension: "ttf"))

    private struct FontKey: Hashable {
        let face: FontFace
        let size: Double
    }

    private struct LineKey: Hashable {
        let text: String
        let face: FontFace
        let size: Double
        /// The kern in canvas units: the letter spacing rounded at the canvas's pixel density.
        let kern: Double
    }

    private let condensedURL: URL?
    private let lock = NSLock()
    private var condensedChecked = false
    private var condensedAvailable = false
    private var fonts: [FontKey: CTFont] = [:]
    private var lines: [LineKey: CTLine] = [:]

    public init(condensedURL: URL?) {
        self.condensedURL = condensedURL
    }

    /// The Core Text font for [face] at [size] canvas units (Paint.textSize).
    public func font(_ face: FontFace, _ size: Double) -> CTFont {
        let key = FontKey(face: face, size: size)
        lock.lock()
        defer { lock.unlock() }
        if let font = fonts[key] { return font }
        let font: CTFont
        switch face {
        case .sundialCondensed: font = condensed(size)
        case .serif: font = FontLibrary.systemSerif(size)
        case .sans: font = FontLibrary.system(size)
        }
        if fonts.count >= 128 { fonts.removeAll() }
        fonts[key] = font
        return font
    }

    /// [text] laid out in the paint's font and size, with [kern] canvas units after every
    /// character (kCTKernAttributeName): the paint's letter spacing, letterSpacing × textSize,
    /// rounded as CGCanvas rounds it to whole pixels. Its colour comes from the context when it is
    /// drawn (kCTForegroundColorFromContextAttributeName), so it is not part of the key.
    public func line(_ text: String, _ paint: Paint, kern: Double) -> CTLine {
        let key = LineKey(text: text, face: paint.font, size: paint.textSize, kern: kern)
        lock.lock()
        let cached = lines[key]
        lock.unlock()
        if let cached { return cached }
        var attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font(paint.font, paint.textSize),
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        if kern != 0 {
            attributes[NSAttributedString.Key(kCTKernAttributeName as String)] = kern
        }
        let string = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(string as CFAttributedString)
        lock.lock()
        if lines.count >= 512 { lines.removeAll() }
        lines[key] = line
        lock.unlock()
        return line
    }

    /// Sundial Condensed, registered for this process from the bundled TTF on first use and then looked up
    /// by its PostScript name. Called with the lock held.
    private func condensed(_ size: Double) -> CTFont {
        let name = FontLibrary.condensedPostScriptName
        if !condensedChecked {
            condensedChecked = true
            if let url = condensedURL {
                var error: Unmanaged<CFError>?
                // Fails harmlessly (already registered) if the app also lists it in UIAppFonts.
                _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
                _ = error?.takeRetainedValue()
            }
            // CTFontCreateWithName quietly substitutes another font for a name it cannot find.
            let probe = CTFontCreateWithName(name as CFString, 12, nil)
            condensedAvailable = (CTFontCopyPostScriptName(probe) as String) == name
        }
        guard condensedAvailable else { return FontLibrary.system(size) }
        return CTFontCreateWithName(name as CFString, CGFloat(size), nil)
    }

    /// The system UI font (San Francisco).
    static func system(_ size: Double) -> CTFont {
        CTFontCreateUIFontForLanguage(.system, CGFloat(size), nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, CGFloat(size), nil)
    }

    /// The system font's serif design (New York). Core Text has no public call for the system
    /// designs, so it comes through UIFontDescriptor (iOS 13, watchOS 6), whose UIFont is
    /// toll-free bridged to CTFont. Without UIKit (a macOS build of the package, which no app
    /// ships) it is Times New Roman.
    static func systemSerif(_ size: Double) -> CTFont {
        #if canImport(UIKit)
        let system = UIFont.systemFont(ofSize: CGFloat(size))
        if let serif = system.fontDescriptor.withDesign(.serif) {
            return UIFont(descriptor: serif, size: CGFloat(size)) as CTFont
        }
        return system as CTFont
        #else
        return CTFontCreateWithName("Times New Roman" as CFString, CGFloat(size), nil)
        #endif
    }
}
#endif
