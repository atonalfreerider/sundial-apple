import Foundation

/// The classical astronomical symbols, engraved as strokes like the hands of an astrological watch:
/// Mercury ☿, Venus ♀ (female), Earth ⊕, Mars ♂ (male) and the lunar crescent ☽. Drawn as paths
/// rather than font glyphs so they share one line weight and never fall back to colour emoji.
final class PlanetSymbols {
    private var path = Path()

    /// Draws [body]'s symbol centred on ([x], [y]), about 2 × [size] tall, with a stroke [paint].
    func draw(_ canvas: Canvas, _ body: Astronomy.Body, _ x: Double, _ y: Double, _ size: Double, _ paint: Paint) {
        // Paint is a value here: Android sets these on the caller's paint, which only ever draws symbols.
        var paint = paint
        paint.style = .stroke
        paint.strokeCap = .round
        paint.strokeWidth = size * 0.11
        switch body {
        case .mercury:
            canvas.drawCircle(x, y - size * 0.08, size * 0.32, paint)
            canvas.drawLine(x, y + size * 0.24, x, y + size * 0.9, paint)
            canvas.drawLine(x - size * 0.26, y + size * 0.6, x + size * 0.26, y + size * 0.6, paint)
            let oval = Rect(x - size * 0.3, y - size * 0.98, x + size * 0.3, y - size * 0.38)
            canvas.drawArc(oval, 0, 180, false, paint)
        case .venus:
            canvas.drawCircle(x, y - size * 0.28, size * 0.4, paint)
            canvas.drawLine(x, y + size * 0.12, x, y + size * 0.92, paint)
            canvas.drawLine(x - size * 0.3, y + size * 0.55, x + size * 0.3, y + size * 0.55, paint)
        case .earth:
            canvas.drawCircle(x, y, size * 0.5, paint)
            canvas.drawLine(x - size * 0.5, y, x + size * 0.5, y, paint)
            canvas.drawLine(x, y - size * 0.5, x, y + size * 0.5, paint)
        case .mars:
            let cx = x - size * 0.14
            let cy = y + size * 0.14
            canvas.drawCircle(cx, cy, size * 0.4, paint)
            let tipX = x + size * 0.62
            let tipY = y - size * 0.62
            canvas.drawLine(cx + size * 0.28, cy - size * 0.28, tipX, tipY, paint)
            path.rewind()
            path.moveTo(tipX - size * 0.36, tipY)
            path.lineTo(tipX, tipY)
            path.lineTo(tipX, tipY + size * 0.36)
            canvas.drawPath(path, paint)
        }
    }

    /// The lunar crescent, horns turned away from the Sun at [sunAngleDegrees] (canvas angle).
    func drawCrescent(_ canvas: Canvas, _ x: Double, _ y: Double, _ size: Double, _ sunAngleDegrees: Double,
                      _ paint: Paint) {
        let away = (sunAngleDegrees + 180.0) * (Double.pi / 180)
        path.rewind()
        path.fillRule = .evenOdd
        path.addCircle(x, y, size * 0.5)
        path.addCircle(
            x + cos(away) * size * 0.24,
            y + sin(away) * size * 0.24,
            size * 0.42
        )
        var paint = paint
        paint.style = .fill
        canvas.drawPath(path, paint)
    }
}
