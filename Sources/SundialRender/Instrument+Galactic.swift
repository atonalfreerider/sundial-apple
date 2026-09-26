import Foundation

// The galactic view, after Unity's: the Sun carries the planets along the direction of travel and
// an endless ribbon of years slides beneath it. Ported from SundialView.kt.

extension Instrument {
    func drawGalactic(_ canvas: Canvas) {
        let (cx, cy, r) = geometry()
        let g = GalacticGeometry.self
        // The ribbon runs off every edge of the screen; there is no end to scroll against.
        let reach = hypot(max(cx, width - cx), max(cy, height - cy))
        let nowYear = g.continuousYear(selectedInstant, zone)
        sunPoint = Point(cx, cy)

        var axis = Paint()
        axis.color = withAlpha(instrumentColor, 175)
        axis.strokeWidth = r * 0.0032
        axis.style = .stroke
        canvas.drawLine(cx - g.travelX * reach, cy - g.travelY * reach,
                        cx + g.travelX * reach, cy + g.travelY * reach, axis)
        drawGalacticYearTicks(canvas, cx, cy, r, nowYear, reach)
        drawOrthonormalPlane(canvas, cx, cy, r)
        drawGalacticTrails(canvas, cx, cy, r, nowYear, reach)
        drawGalacticEvents(canvas, cx, cy, r, nowYear, reach)
        for body in Astronomy.Body.allCases {
            let (along, side) = g.orbitOffset(
                Astronomy.heliocentricPosition(body, selectedInstant).longitudeDegrees, r * galacticOrbit(body))
            drawPlanetMarker(canvas, body, cx + g.travelX * along + g.sideX * side,
                             cy + g.travelY * along + g.sideY * side, r * 0.82, cx, cy)
        }
        drawSun(canvas, cx, cy, r * 0.061)

        // Unity's Sun travels toward the north ecliptic pole: later years lie ahead of it.
        let arrowTip = min(r * 1.13, reach - r * 0.12)
        axis.color = withAlpha(instrumentColor, 210)
        drawDirectionArrow(canvas, cx + g.travelX * arrowTip, cy + g.travelY * arrowTip, r, axis)
        var label = dimText
        label.textSize = max(r * 0.037, 12 * density)
        label.letterSpacing = 0.17
        label.textAlign = .left
        // Written down the axis from behind the arrowhead, on its left so the axis stays clear.
        canvas.save()
        canvas.translate(cx + g.travelX * arrowTip, cy + g.travelY * arrowTip)
        canvas.rotate(atan2(-g.travelY, -g.travelX) * 180 / .pi)
        canvas.drawText("DIRECTION OF TRAVEL", r * 0.13, r * 0.03 - canvas.fontMetrics(label).ascent, label)
        canvas.restore()
        var yearLabel = text
        yearLabel.textSize = r * 0.055
        canvas.drawText(CivilFormat.format(selectedInstant, "MMM d  yyyy", zone),
                        cx, cy + r * 1.13, yearLabel)
    }

    /// Unity's galactic sun line: a big tick and year label at each New Year, lighter month ticks.
    func drawGalacticYearTicks(_ canvas: Canvas, _ cx: Double, _ cy: Double, _ r: Double, _ nowYear: Double,
                               _ reach: Double) {
        let g = GalacticGeometry.self
        let pitch = r * g.yearPitch
        // A zero-sized canvas (r = 0) makes the span below NaN or infinite, which Swift's Int(_:)
        // traps on where Kotlin's toInt() does not; nothing would show on such a canvas anyway.
        guard pitch > 0 else { return }
        var tick = Paint()
        tick.style = .stroke
        tick.strokeCap = .round
        var yearLabel = text
        yearLabel.textSize = r * 0.05
        yearLabel.color = withAlpha(instrumentColor, 190)
        yearLabel.textAlign = g.sideX < 0 ? .right : .left
        let span = Int((reach / pitch).rounded(.up))
        let first = max(Int(nowYear.rounded(.down)) - span, g.minYear)
        let last = min(Int(nowYear.rounded(.down)) + span, g.maxYear)
        for year in stride(from: first, through: last, by: 1) {
            for month in 1...12 {
                let distance = (g.monthStart(year, month) - nowYear) * pitch
                if abs(distance) > reach { continue }
                let x = cx + g.travelX * distance
                let y = cy + g.travelY * distance
                let newYear = month == 1
                let half = newYear ? r * 0.045 : r * 0.014
                tick.color = withAlpha(instrumentColor, newYear ? 200 : 120)
                tick.strokeWidth = newYear ? r * 0.0045 : r * 0.0025
                canvas.drawLine(x - g.sideX * half, y - g.sideY * half, x + g.sideX * half, y + g.sideY * half, tick)
                if newYear {
                    let metrics = canvas.fontMetrics(yearLabel)
                    canvas.drawText(String(year), x + g.sideX * r * 0.065,
                                    y + g.sideY * r * 0.065 - (metrics.ascent + metrics.descent) / 2, yearLabel)
                }
            }
        }
    }

    /// Orbit radius of each planet in the galactic helix, in dial radii.
    func galacticOrbit(_ body: Astronomy.Body) -> Double {
        switch body {
        case .mercury: return 0.105
        case .venus: return 0.185
        case .earth: return 0.285
        case .mars: return 0.434
        }
    }

    // GalacticTrails, the cached helices, is declared with the instrument's state in Instrument.swift.

    func galacticTrails(_ r: Double, _ nowYear: Double, _ reach: Double) -> GalacticTrails {
        let g = GalacticGeometry.self
        let pitch = r * g.yearPitch
        let span = Int((reach / pitch).rounded(.up)) + 1
        let base = max(Int(nowYear.rounded(.down)) - span, g.minYear)
        let end = min(Int(nowYear.rounded(.down)) + span + 1, g.maxYear + 1)
        if let cached = galacticTrails, cached.baseYear == base && cached.endYear == end && cached.pitch == pitch {
            return cached
        }

        // Dash the outer helices once here, rather than with a PathEffect on every frame. A Swift
        // Path is a value, so each builder holds the path it appends to.
        let builders = Dictionary(uniqueKeysWithValues: Astronomy.Body.allCases.map { body in
            (body, body == .earth ? DashedPathBuilder(.greatestFiniteMagnitude, 0)
                                  : DashedPathBuilder(r * 0.012, r * 0.014))
        })
        for year in stride(from: base, to: end, by: 1) {
            let yearStart = LocalDate(year, 1, 1).atStartOfDay(zone)
            let yearSeconds = LocalDate(year + 1, 1, 1).atStartOfDay(zone).timeIntervalSince(yearStart)
            for step in 0..<Instrument.galacticStepsPerYear {
                let fraction = Double(step) / Double(Instrument.galacticStepsPerYear)
                let instant = yearStart.addingTimeInterval(yearSeconds * fraction)
                let along = (Double(year - base) + fraction) * pitch
                for body in Astronomy.Body.allCases {
                    let (depth, side) = g.orbitOffset(
                        Astronomy.heliocentricPosition(body, instant).longitudeDegrees, r * galacticOrbit(body))
                    builders[body]!.to(along + depth, side)
                }
            }
        }
        let paths = builders.mapValues { $0.path }
        let trails = GalacticTrails(baseYear: base, endYear: end, pitch: pitch, paths: paths)
        galacticTrails = trails
        return trails
    }

    /// Appends a polyline to [path] as dashes of [dash] length separated by [gap].
    final class DashedPathBuilder {
        private(set) var path = Path()
        private let dash: Double
        private let gap: Double
        private var started = false
        private var lastX = 0.0
        private var lastY = 0.0
        private var phase = 0.0

        init(_ dash: Double, _ gap: Double) {
            self.dash = dash
            self.gap = gap
        }

        func to(_ x: Double, _ y: Double) {
            if !started {
                path.moveTo(x, y)
                started = true
            } else {
                var fromX = lastX
                var fromY = lastY
                var remaining = hypot(x - fromX, y - fromY)
                if remaining > 0 {
                    let ux = (x - fromX) / remaining
                    let uy = (y - fromY) / remaining
                    while remaining > 0 {
                        let inDash = phase < dash
                        let step = min(inDash ? dash - phase : dash + gap - phase, remaining)
                        fromX += ux * step
                        fromY += uy * step
                        if inDash { path.lineTo(fromX, fromY) } else { path.moveTo(fromX, fromY) }
                        phase += step
                        if phase >= dash + gap { phase -= dash + gap }
                        remaining -= step
                    }
                }
            }
            lastX = x
            lastY = y
        }
    }

    func drawGalacticTrails(_ canvas: Canvas, _ cx: Double, _ cy: Double, _ r: Double, _ nowYear: Double,
                            _ reach: Double) {
        let g = GalacticGeometry.self
        // As in drawGalacticYearTicks: galacticTrails' span traps in Swift on a zero-sized canvas.
        guard r > 0 else { return }
        let trails = galacticTrails(r, nowYear, reach)
        let offset = (nowYear - Double(trails.baseYear)) * trails.pitch
        // Ribbon (along, side) → screen, with the current moment under the Sun.
        let galacticMatrix = AffineTransform(
            a: g.travelX, b: g.travelY, c: g.sideX, d: g.sideY,
            tx: cx - g.travelX * offset, ty: cy - g.travelY * offset)
        let pathColors: [Astronomy.Body: ARGB] = [
            .mercury: 0xFF9B_B6C7,
            .venus: 0xFFFF_D591,
            .earth: 0xFF6E_D6F3,
            .mars: 0xFFE7_523E,
        ]
        var trail = Paint()
        trail.style = .stroke
        trail.strokeCap = .round
        canvas.save()
        canvas.concat(galacticMatrix)
        for body in Astronomy.Body.allCases {
            let earth = body == .earth
            trail.color = withAlpha(pathColors[body]!, earth ? 150 : 90)
            trail.strokeWidth = r * (earth ? 0.006 : 0.003)
            canvas.drawPath(trails.paths[body]!, trail)
        }
        canvas.restore()
    }

    func drawDirectionArrow(_ canvas: Canvas, _ tipX: Double, _ tipY: Double, _ r: Double, _ paint: Paint) {
        let g = GalacticGeometry.self
        let length = r * 0.085
        let halfWidth = r * 0.027
        // Paint is a value here, so filling a copy leaves the caller's stroke as it was.
        var paint = paint
        paint.style = .fill
        var polygonPath = Path()
        polygonPath.moveTo(tipX, tipY)
        polygonPath.lineTo(tipX - g.travelX * length + g.sideX * halfWidth, tipY - g.travelY * length + g.sideY * halfWidth)
        polygonPath.lineTo(tipX - g.travelX * length - g.sideX * halfWidth, tipY - g.travelY * length - g.sideY * halfWidth)
        polygonPath.close()
        canvas.drawPath(polygonPath, paint)
    }

    func drawOrthonormalPlane(_ canvas: Canvas, _ x: Double, _ y: Double, _ r: Double) {
        let g = GalacticGeometry.self
        var plane = Paint()
        plane.style = .stroke
        plane.strokeWidth = r * 0.002
        plane.color = withAlpha(backgroundStyle.accentColor, 105)
        let sideAngle = atan2(g.sideY, g.sideX) * 180 / .pi
        canvas.save()
        canvas.rotate(sideAngle, x, y)
        for scale in [0.35, 0.67, 1.0] {
            canvas.drawOval(
                Rect(x - r * 0.38 * scale, y - r * 0.085 * scale,
                     x + r * 0.38 * scale, y + r * 0.085 * scale),
                plane)
        }
        canvas.restore()
        plane.color = withAlpha(instrumentColor, 75)
        canvas.drawLine(x - g.sideX * r * 0.43, y - g.sideY * r * 0.43,
                        x + g.sideX * r * 0.43, y + g.sideY * r * 0.43, plane)
    }

    func drawGalacticEvents(_ canvas: Canvas, _ cx: Double, _ cy: Double, _ r: Double, _ nowYear: Double,
                            _ reach: Double) {
        let g = GalacticGeometry.self
        let pitch = r * g.yearPitch
        var bead = Paint()
        var eventText = text
        eventText.textSize = max(r * 0.03, 12 * density)
        eventText.textAlign = .left
        eventText.color = withAlpha(instrumentColor, 235)
        eventText.shadow = Shadow(radius: 2.5 * density, dx: 0, dy: 0, color: 0xD000_0000)
        // Events bunch up near the Sun (a year is only a hand's width of ribbon): label each one
        // only where it has room, nearest first.
        var placed: [Rect] = []
        let sorted = occurrences.sorted {
            abs(g.continuousYear($0.start.instant, zone) - nowYear) < abs(g.continuousYear($1.start.instant, zone) - nowYear)
        }
        for event in sorted {
            let instant = event.start.instant
            let distance = (g.continuousYear(instant, zone) - nowYear) * pitch
            if abs(distance) > reach { continue }
            let (depth, side) = g.orbitOffset(
                Astronomy.heliocentricPosition(.earth, instant).longitudeDegrees,
                r * galacticOrbit(.earth))
            let x = cx + g.travelX * (distance + depth) + g.sideX * side
            let y = cy + g.travelY * (distance + depth) + g.sideY * side
            bead.style = .fill
            bead.color = withAlpha(event.color, 230)
            canvas.drawCircle(x, y, r * (event.isAllDay ? 0.014 : 0.010), bead)
            bead.style = .stroke
            bead.strokeWidth = r * 0.002
            bead.color = withAlpha(instrumentColor, 155)
            canvas.drawCircle(x, y, r * 0.020, bead)
            let title = canvas.ellipsize(event.title, eventText, r * 0.6)
            let left = x + r * 0.035
            let metrics = canvas.fontMetrics(eventText)
            let baseline = y - (metrics.ascent + metrics.descent) / 2
            let box = Rect(left, baseline + metrics.ascent, left + canvas.measureText(title, eventText),
                           baseline + metrics.descent)
            if !placed.contains(where: { Rect.intersects($0, box) }) {
                placed.append(box)
                canvas.drawText(title, left, baseline, eventText)
            }
        }
    }
}
