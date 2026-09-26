import Foundation

// The sky behind the instrument: the atmosphere gradient, the fixed star field, the dust lane and
// the constellations, turned and zoomed by the camera. Ported from SundialView.kt.

extension Instrument {
    func drawBackground(_ canvas: Canvas, _ from: ViewState?, _ progress: Double) {
        let (cx, cy, _) = geometry()
        // Android keeps the RadialGradient keyed on the size and style; a Shader here is a value,
        // so it is simply rebuilt each frame.
        var atmosphere = Paint()
        atmosphere.shader = .radial(
            center: Point(cx, cy),
            radius: hypot(width, height) * 0.72,
            colors: [
                backgroundStyle.haloColor,
                blendColor(backgroundStyle.haloColor, backgroundStyle.baseColor, 0.58),
                backgroundStyle.baseColor,
            ],
            stops: [0, 0.58, 1])
        canvas.drawRect(0, 0, width, height, atmosphere)
        let (rotation, scale) = skyCamera(from, progress)
        canvas.save()
        canvas.rotate(rotation, cx, cy)
        canvas.scale(scale, scale, cx, cy)
        drawAmbientStars(canvas, cx, cy)
        canvas.restore()
    }

    /// Camera roll and zoom seen in the distant sky. The stars are fixed in the solar system, so
    /// the Earth camera's roll turns them too, while a fraction of its zoom gives the flight parallax.
    func skyCamera(_ from: ViewState?, _ progress: Double) -> (Double, Double) {
        let earthZoom = pow(DialGeometry.earthCameraZoom, DialGeometry.skyParallax)
        if let from, isEarthFlight(from, state) {
            let flight = state == .geocentric ? progress : 1 - progress
            return (transitionCameraRotation * flight, DialGeometry.earthFlightFrame(flight).skyScale)
        } else if from == nil && state == .geocentric {
            return (earthCameraRotation(), earthZoom)
        } else {
            return (0, 1)
        }
    }

    func drawAmbientStars(_ canvas: Canvas, _ cx: Double, _ cy: Double) {
        constellationPaint.color = withAlpha(blendColor(instrumentColor, backgroundStyle.accentColor, 0.35), 30)
        constellationPaint.strokeWidth = 0.55 * density
        if constellationPaint.dash == nil {
            constellationPaint.dash = [2.5 * density, 5 * density]
        }
        var constellationPath = Path()
        for points in constellationPaths {
            constellationPath.rewind()
            for (index, point) in points.enumerated() {
                let x = point.0 * width
                let y = point.1 * height
                if index == 0 { constellationPath.moveTo(x, y) } else { constellationPath.lineTo(x, y) }
            }
            canvas.drawPath(constellationPath, constellationPaint)
        }

        skyPaint.style = .fill
        for point in dustLaneStars {
            skyPaint.color = withAlpha(backgroundStyle.accentColor, point.alpha)
            canvas.drawCircle(point.xFraction * width, point.yFraction * height, point.radiusDp * density, skyPaint)
        }

        // Reach every screen corner from the dial centre, whatever the camera's roll.
        let reach = hypot(max(cx, width - cx), max(cy, height - cy))
        for point in ambientStars {
            let x = cx + point.xFraction * reach
            let y = cy + point.yFraction * reach
            let radius = point.radiusDp * density
            skyPaint.color = withAlpha(instrumentColor, point.alpha)
            canvas.drawCircle(x, y, radius, skyPaint)
            if point.flare {
                skyPaint.strokeWidth = max(0.45 * density, radius * 0.42)
                canvas.drawLine(x - radius * 2.4, y, x + radius * 2.4, y, skyPaint)
                canvas.drawLine(x, y - radius * 2.4, x, y + radius * 2.4, skyPaint)
            }
        }

        for (index, point) in constellationPaths.joined().enumerated() {
            skyPaint.color = withAlpha(instrumentColor, index % 4 == 0 ? 112 : 72)
            canvas.drawCircle(
                point.0 * width,
                point.1 * height,
                (index % 4 == 0 ? 1.15 : 0.72) * density,
                skyPaint)
        }
    }
}
