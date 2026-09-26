import Foundation

// Camera moves between the views: the rigid Earth camera flight between the solar and Earth
// views, and a cross-fade for the rest. Ported from SundialView.kt.

extension Instrument {
    func isEarthFlight(_ from: ViewState, _ to: ViewState) -> Bool {
        (from == .heliocentric && to == .geocentric) ||
            (from == .geocentric && to == .heliocentric)
    }

    /// Roll of the Earth camera: it keeps the Sun straight above the Earth.
    func earthCameraRotation() -> Double { Astronomy.normalizeSignedDegrees(90.0 - currentEarthAngle()) }

    func drawTransition(_ canvas: Canvas, _ from: ViewState, _ to: ViewState, _ progress: Double) {
        let (cx, cy, _) = geometry()
        if isEarthFlight(from, to) {
            let flightProgress = to == .geocentric ? progress : 1 - progress
            drawEarthCameraFlight(canvas, cx, cy, flightProgress)
        } else {
            drawTransformedState(canvas, from, cx, cy, 1, 0, 1 - progress)
            drawTransformedState(canvas, to, cx, cy, 1, 0, progress)
        }
    }

    /// One rigid camera move from the Sun-centred dial to the Earth, as in Unity: the camera rolls,
    /// zooms and follows the Earth while the Earth system swells from the planet glyph into the
    /// Earth instrument. Everything, the Earth included, shares the camera's roll, so nothing turns
    /// against the dial on the way in.
    func drawEarthCameraFlight(_ canvas: Canvas, _ cx: Double, _ cy: Double, _ progress: Double) {
        // The zoom changes every frame: sweep gradients reuse the resting views' images.
        cameraInMotion = true
        defer { cameraInMotion = false }
        let targetX = lerp(transitionEarthPoint.x, cx, progress)
        let targetY = lerp(transitionEarthPoint.y, cy, progress)
        let frame = DialGeometry.earthFlightFrame(progress)
        let cameraRotation = transitionCameraRotation * progress
        // The Earth instrument is drawn Sun-up; until the camera has finished rolling it is still
        // turned by the roll that remains, exactly like the dial around it.
        let earthSystemRotation = cameraRotation - transitionCameraRotation

        let heliocentricAlpha: Double
        if progress < 0.48 {
            heliocentricAlpha = 1
        } else if progress > 0.94 {
            heliocentricAlpha = 0
        } else {
            heliocentricAlpha = 1 - (progress - 0.48) / 0.46
        }
        let geocentricAlpha = min(max(progress / 0.22, 0), 1)

        let r = geometry().r
        func heliocentricCamera() {
            canvas.translate(targetX, targetY)
            canvas.rotate(cameraRotation)
            canvas.scale(frame.cameraScale, frame.cameraScale)
            canvas.translate(-transitionEarthPoint.x, -transitionEarthPoint.y)
        }
        // The annual sprocket stays visible from the Earth camera, so it rides the camera at full
        // opacity and lands exactly where the Earth view draws it.
        canvas.save()
        heliocentricCamera()
        drawDialFace(canvas, cx, cy, r)
        withTextScreenRotation(cameraRotation) { drawAnnualBackdrop(canvas, cx, cy, r) }
        canvas.restore()

        if heliocentricAlpha > 0.01 {
            let checkpoint = canvas.saveLayer(alpha: Double(Int(heliocentricAlpha * 255)) / 255)
            heliocentricCamera()
            withTextScreenRotation(cameraRotation) {
                drawSeasonShading(canvas, cx, cy, r)
                drawHeliocentricForeground(canvas, cx, cy, r, includeSun: false)
            }
            canvas.restore(toCount: checkpoint)
        }

        if geocentricAlpha > 0.01 {
            let checkpoint = canvas.saveLayer(alpha: Double(Int(geocentricAlpha * 255)) / 255)
            canvas.translate(targetX, targetY)
            canvas.rotate(earthSystemRotation)
            canvas.scale(frame.earthSystemScale, frame.earthSystemScale)
            canvas.translate(-cx, -cy)
            withTextScreenRotation(earthSystemRotation) {
                drawGeocentric(canvas, includeBackdrop: false, includeSun: false)
            }
            canvas.restore(toCount: checkpoint)
        }

        // One Sun for the whole flight: it follows the camera from the dial centre to the top of
        // the Earth view instead of cross-fading between two differently scaled copies.
        let sunOffsetX = (cx - transitionEarthPoint.x) * frame.cameraScale
        let sunOffsetY = (cy - transitionEarthPoint.y) * frame.cameraScale
        let cameraRadians = cameraRotation * .pi / 180
        drawSun(
            canvas,
            targetX + (sunOffsetX * cos(cameraRadians) - sunOffsetY * sin(cameraRadians)),
            targetY + (sunOffsetX * sin(cameraRadians) + sunOffsetY * cos(cameraRadians)),
            r * lerp(0.052, 0.058, progress))
    }

    func drawTransformedState(
        _ canvas: Canvas,
        _ requestedState: ViewState,
        _ cx: Double,
        _ cy: Double,
        _ scale: Double,
        _ rotation: Double,
        _ alpha: Double
    ) {
        if alpha <= 0.01 { return }
        let checkpoint = canvas.saveLayer(alpha: Double(Int(alpha * 255)) / 255)
        canvas.scale(scale, scale, cx, cy)
        canvas.rotate(rotation, cx, cy)
        drawState(canvas, requestedState)
        canvas.restore(toCount: checkpoint)
    }

    func smoothStep(_ value: Double) -> Double { value * value * (3 - 2 * value) }

    func switchToState(_ newState: ViewState) {
        if state == newState { return }
        if isEarthFlight(state, newState) {
            let (cx, cy, r) = geometry()
            transitionEarthPoint = point(cx, cy, r * DialGeometry.earthOrbit, currentEarthAngle())
            transitionCameraRotation = earthCameraRotation()
        }
        transitionFrom = state
        state = newState
        transitionStartedAt = uptime()
        onControlsChanged?()
        invalidate()
    }
}
