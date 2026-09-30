import Foundation

// The Earth view: the hour sprocket, the lunar dial, the local wheel and its date strip, the globe
// seal and the Moon glyph, drawn around the Earth with the Sun at the top. Ported from
// SundialView.kt.

extension Instrument {
    func drawGeocentric(_ canvas: Canvas, includeBackdrop: Bool = true, includeSun: Bool = true) {
        let (cx, cy, r) = geometry()
        let moonR = r * DialGeometry.moonDial
        let hourR = r * DialGeometry.hourDial
        let sphereRadius = r * DialGeometry.earthRadius
        let sunY = cy - r * DialGeometry.geocentricSunDistance

        if includeBackdrop {
            // Unity's Earth camera still saw the annual sprocket, season cross and Earth spike
            // arcing around the Earth; keep them in the same place the camera flight leaves them.
            let roll = earthCameraRotation()
            canvas.save()
            canvas.translate(cx, sunY)
            canvas.rotate(roll)
            canvas.scale(DialGeometry.earthCameraZoom, DialGeometry.earthCameraZoom)
            canvas.translate(-cx, -cy)
            drawDialFace(canvas, cx, cy, r)
            withTextScreenRotation(roll) { drawAnnualBackdrop(canvas, cx, cy, r) }
            canvas.restore()
        }

        drawHourSprocket(canvas, cx, cy, hourR, r)
        text.textSize = label(r * 0.038, 7.5)
        for hour in 0..<24 {
            drawRotatedText(canvas, String(hour), cx, cy, hourR * 0.87, hourAngle(Double(hour)), text, true)
        }

        let moonAngle = DialGeometry.moonAngle(Astronomy.moonPhaseDegrees(selectedInstant), north)
        moonPoint = point(cx, cy, moonR, moonAngle)
        drawAnnularPointer(canvas, cx, cy, sphereRadius * 1.055, moonR * 0.97, moonAngle,
                           moonR * 0.05, withAlpha(instrumentColor, 122))
        drawAnnularPointer(canvas, cx, cy, sphereRadius * 1.065, moonR * 0.82, moonAngle,
                           moonR * 0.021, 0x9B85_858A)
        drawLunarDial(canvas, cx, cy, moonR, r)

        // Sun stays at the top in Earth-following view, as in the original camera behavior.
        if includeSun { drawSun(canvas, cx, sunY, r * 0.058) }

        drawCalendarDayEvents(canvas, cx, cy, hourR)
        drawLocalWheel(canvas, cx, cy, r)
        var shadow = Paint()
        shadow.shader = .radial(
            center: Point(cx + sphereRadius * 0.05, cy + sphereRadius * 0.12),
            radius: sphereRadius * 1.18,
            colors: [Colors.argb(82, 0, 0, 0), Colors.argb(32, 0, 0, 0), Colors.transparent],
            stops: [0, 0.68, 1])
        canvas.drawOval(Rect(cx - sphereRadius * 1.08, cy - sphereRadius * 0.92,
                             cx + sphereRadius * 1.16, cy + sphereRadius * 1.2), shadow)
        drawEarthSeal(canvas, cx, cy, sphereRadius, cx, sunY, true,
                      highlightOffsetMinutes: selectedTimeZoneOffset())

        drawMoonGlyph(canvas, moonPoint.x, moonPoint.y, r * 0.041, cx, sunY)
    }

    /// Unity's Earth sprocket: 24 hour teeth with three quarter-hour teeth between them.
    func drawHourSprocket(_ canvas: Canvas, _ cx: Double, _ cy: Double, _ radius: Double, _ r: Double) {
        white.color = instrumentColor
        white.strokeWidth = max(density, r * 0.005)
        canvas.drawCircle(cx, cy, radius, white)
        polygon.color = instrumentColor
        for quarter in 0..<96 {
            let major = quarter % 4 == 0
            drawSprocketTooth(
                canvas, cx, cy, radius, radius - (major ? r * 0.058 : r * 0.025),
                hourAngle(Double(quarter) / 4.0),
                major ? r * 0.0048 : r * 0.0032,
                major ? r * 0.0016 : r * 0.0011,
                polygon)
        }
    }

    /// Unity's lunar dial: one tick at each coming local midnight, placed where the Moon will be then,
    /// with the date between ticks. The 29-day window leaves a gap just behind the Moon, and the
    /// first of a month gets a split tick labelled with both months.
    func drawLunarDial(_ canvas: Canvas, _ cx: Double, _ cy: Double, _ moonR: Double, _ r: Double) {
        let today = ZonedDateTime(selectedInstant, zone).date
        let midnights = (0...29).map { today.plusDays($0).atStartOfDay(zone) }
        let phases = midnights.map { Astronomy.moonPhaseDegrees($0) }
        let angles = phases.map { DialGeometry.moonAngle($0, north) }
        let direction = north ? -1.0 : 1.0

        var span = 0.0
        for i in 0..<(phases.count - 1) {
            span += Astronomy.normalizeDegrees(phases[i + 1] - phases[i])
        }
        white.color = instrumentColor
        white.strokeWidth = max(density, r * 0.004)
        canvas.drawArc(Rect(cx - moonR, cy - moonR, cx + moonR, cy + moonR),
                       angles[0], direction * span, false, white)

        var monthPaint = text
        monthPaint.textSize = label(r * 0.033, 6.5)
        text.textSize = label(r * 0.037, 7)
        for i in 0...29 {
            let date = today.plusDays(i)
            let monthStart = date.day == 1 && i > 0
            white.strokeWidth = monthStart ? max(density, r * 0.0045) : max(0.8 * density, r * 0.0026)
            drawRadialLine(canvas, cx, cy,
                           moonR - (monthStart ? r * 0.05 : r * 0.024),
                           moonR + (monthStart ? r * 0.035 : 0),
                           angles[i], white)
            if monthStart {
                // Earlier dates lie clockwise (north); the new month continues counter-clockwise.
                drawRotatedText(canvas, date.monthAbbreviation, cx, cy, moonR + r * 0.038,
                                angles[i] + direction * 3.6, monthPaint, true)
                drawRotatedText(canvas, date.minusDays(1).monthAbbreviation, cx, cy, moonR + r * 0.038,
                                angles[i] - direction * 3.6, monthPaint, true)
            }
            if i < 29 {
                let middle = angles[i] + direction * Astronomy.normalizeDegrees(phases[i + 1] - phases[i]) / 2.0
                drawRotatedText(canvas, String(date.day), cx, cy, moonR * 0.94, middle, text, true)
            }
        }
        // Current month sits just outside the ring where today's window begins.
        drawRotatedText(canvas, today.monthAbbreviation, cx, cy, moonR + r * 0.038,
                        angles[0] - direction * 3.6, monthPaint, true)
    }

    func selectedTimeZoneOffset() -> Int {
        let currentLocalOffset = TimeZoneDial.localOffsetMinutes(selectedInstant, zone)
        if selectedTimeZoneOffsetMinutes == nil { selectedTimeZoneOffsetMinutes = currentLocalOffset }
        return selectedTimeZoneIsLocal ? currentLocalOffset : selectedTimeZoneOffsetMinutes!
    }

    /// Unity's local wheel around the globe: a thin ring with an outward tooth for every hour. The
    /// long tooth points at the selected zone's local time and carries a smaller red tooth inside
    /// it; the other teeth fall on the whole-hour zones either side. A translucent strip inside the
    /// ring spans the zones that have already reached the new date, from local midnight round to the
    /// international date line, with the two weekdays labelled at each boundary.
    func drawLocalWheel(_ canvas: Canvas, _ cx: Double, _ cy: Double, _ r: Double) {
        let wheelR = r * DialGeometry.localWheel
        let direction = north ? -1.0 : 1.0

        let datelineHours = TimeZoneDial.datelineHours(selectedInstant)
        let stripR = r * (DialGeometry.dateStripOuter + DialGeometry.dateStripInner) / 2
        white.color = withAlpha(instrumentColor, 77)
        white.strokeWidth = r * (DialGeometry.dateStripOuter - DialGeometry.dateStripInner)
        canvas.drawArc(Rect(cx - stripR, cy - stripR, cx + stripR, cy + stripR),
                       hourAngle(0.0), direction * datelineHours * 15, false, white)

        let newDate = LocalDate.of(selectedInstant, .offset(seconds: 43_200))
        let newDay = newDate.weekdayAbbreviation
        let oldDay = newDate.minusDays(1).weekdayAbbreviation
        var dayPaint = text
        dayPaint.textSize = max(r * 0.03, 9 * density)
        dayPaint.color = withAlpha(instrumentColor, 220)
        // Unity sets each weekday 4.2° either side of the boundary it names; small dials (a watch)
        // need a wider split so the two names don't run together.
        let split = max(4.2, ((canvas.measureText("WED", dayPaint) / 2 + 2 * density) / stripR) * 180 / .pi) / 15.0
        for (boundary, newDayAfter) in [(0.0, true), (datelineHours, false)] {
            drawRotatedText(canvas, newDayAfter ? newDay : oldDay, cx, cy, stripR,
                            hourAngle(boundary + split), dayPaint, true)
            drawRotatedText(canvas, newDayAfter ? oldDay : newDay, cx, cy, stripR,
                            hourAngle(boundary - split), dayPaint, true)
        }

        white.color = instrumentColor
        white.strokeWidth = max(0.8 * density, r * 0.006)
        canvas.drawCircle(cx, cy, wheelR, white)

        let selectedAngle = TimeZoneDial.angleForOffsetMinutes(selectedInstant, selectedTimeZoneOffset(), north: north)
        let baseHalfWidth = wheelR * (DialGeometry.localWheelToothHalfAngle * .pi / 180)
        polygon.color = instrumentColor
        for hour in 0..<24 {
            let tooth = hour == 0 ? DialGeometry.localWheelBigTooth : DialGeometry.localWheelSmallTooth
            drawSprocketTooth(canvas, cx, cy, wheelR, wheelR + r * tooth, selectedAngle + Double(hour) * 15.0,
                              baseHalfWidth, wheelR * 0.001, polygon)
        }
        polygon.color = Instrument.localToothRed
        drawSprocketTooth(canvas, cx, cy, wheelR, wheelR + r * DialGeometry.localWheelRedTooth, selectedAngle,
                          r * DialGeometry.localWheelRedHalfBase, 0, polygon)
    }

    /// Name and local time of the zone the local wheel is set to, shown above the Earth view.
    func drawSelectedZoneCaption(_ canvas: Canvas) {
        let offset = selectedTimeZoneOffset()
        // Int.floorDiv(60): whole hours, rounded toward negative infinity.
        let name = selectedTimeZoneIsLocal ? TimeZoneDial.localName(zone, selectedInstant)
            : TimeZoneDial.commonName(Int((Double(offset) / 60).rounded(.down)))
        let local = CivilFormat.format(selectedInstant, "EEE HH:mm", .offset(seconds: offset * 60))
        var caption = text
        caption.textSize = 15 * density
        caption.letterSpacing = 0.08
        caption.color = withAlpha(instrumentColor, 215)
        let label = "\(name.uppercased())  ·  \(local.uppercased())"
        if width > height {
            // In landscape the Sun sits at the top centre of the Earth view; use the free corner
            // beside the settings button instead.
            caption.textAlign = .left
            canvas.drawText(label, 80 * density, 38 * density, caption)
        } else {
            canvas.drawText(label, width / 2, (showClock ? 62 : 36) * density, caption)
        }
    }

    func drawEarthSeal(_ canvas: Canvas, _ x: Double, _ y: Double, _ radius: Double, _ sunX: Double, _ sunY: Double,
                       _ ornate: Bool, highlightOffsetMinutes: Int? = nil) {
        let bitmap = earthRenderer.render(selectedInstant, north, highlightOffsetMinutes: highlightOffsetMinutes)
        let sunAngle = atan2(sunY - y, sunX - x) * 180 / .pi
        // EarthSphereRenderer uses Sun-up coordinates; rotate the complete globe into the actual
        // Earth-to-Sun direction without changing its geographic orientation.
        canvas.save()
        canvas.rotate(sunAngle + 90, x, y)
        let earthGlobeBounds = Rect(x - radius, y - radius, x + radius, y + radius)
        canvas.drawImage(bitmap, earthGlobeBounds, alpha: 1)
        if ornate {
            // A small gold ring on the visible geographic pole: it swings round the globe's centre
            // with the seasons as the fixed axis tilts toward and away from the Sun.
            let pole = EarthOrientation.projectedGeographicPole(north, Zodiac.sunLongitude(selectedInstant))
            var marker = Paint()
            marker.color = 0xC8E5_C47A
            marker.style = .stroke
            marker.strokeWidth = max(density, radius * 0.008)
            let px = x + pole.0 * radius
            let py = y - pole.1 * radius
            canvas.drawCircle(px, py, radius * 0.035, marker)
            marker.style = .fill
            canvas.drawCircle(px, py, radius * 0.011, marker)
        }
        canvas.restore()
        drawEarthSealRim(canvas, x, y, radius, ornate)
    }

    /// The Earth view's globe is framed by the local wheel's date strip, so it keeps only a fine
    /// rim; the small planet glyph gets a bolder ring to read against the dial.
    func drawEarthSealRim(_ canvas: Canvas, _ x: Double, _ y: Double, _ radius: Double, _ ornate: Bool) {
        var halo = Paint()
        halo.color = ornate ? 0x9EE5_C47A : withAlpha(instrumentColor, 190)
        halo.style = .stroke
        halo.strokeWidth = max(density, radius * (ornate ? 0.008 : 0.045))
        canvas.drawCircle(x, y, radius * (ornate ? 1.004 : 1.035), halo)
    }

    func drawMoonGlyph(_ canvas: Canvas, _ x: Double, _ y: Double, _ radius: Double, _ sunX: Double, _ sunY: Double) {
        var aura = Paint()
        aura.shader = .radial(
            center: Point(x, y),
            radius: radius * 2.7,
            colors: [0xAAFF_FCE5, 0x38D9_D4B9, Colors.transparent],
            stops: [0, 0.42, 1])
        canvas.drawCircle(x, y, radius * 2.7, aura)
        // Android's size is in device pixels (its canvas unit), and MoonSphereRenderer clamps it
        // in pixels: render at the resolution the glyph is drawn at, whatever the host's units.
        let moon = moonRenderer.render(Int(radius * 2 * pixelsPerUnit), sunX - x, sunY - y)
        // Android draws the bitmap with the shared fill paint, so it takes that paint's alpha.
        canvas.drawImage(moon, Rect(x - radius, y - radius, x + radius, y + radius), alpha: Double(fill.alpha) / 255)
        white.color = withAlpha(instrumentColor, 184); white.strokeWidth = max(devicePixels(1), radius * 0.075)
        canvas.drawCircle(x, y, radius * 1.04, white)
        // The Byzantine seal belongs to the astrology instrument; astronomy keeps a plain Moon.
        if zodiacProfile.enabled { drawByzantineMoonSeal(canvas, x, y, radius) }
    }

    func drawByzantineMoonSeal(_ canvas: Canvas, _ x: Double, _ y: Double, _ radius: Double) {
        var gold = Paint()
        gold.color = 0xB8E4_C171
        gold.style = .stroke
        gold.strokeWidth = max(0.7 * density, radius * 0.055)
        canvas.drawArc(Rect(x - radius * 1.22, y - radius * 1.22,
                            x + radius * 1.22, y + radius * 1.22), 198, 284, false, gold)
        gold.style = .fill
        for index in 0..<8 {
            let angle = (Double(index) * 45.0 + 22.5) * .pi / 180
            canvas.drawCircle(x + cos(angle) * radius * 1.21,
                              y + sin(angle) * radius * 1.21, radius * 0.055, gold)
        }
        // A tiny cross pattée crowns the lunar seal, echoing the reference's engraved metalwork.
        let crownY = y - radius * 1.48
        gold.strokeWidth = max(0.8 * density, radius * 0.10)
        gold.strokeCap = .square
        canvas.drawLine(x - radius * 0.18, crownY, x + radius * 0.18, crownY, gold)
        canvas.drawLine(x, crownY - radius * 0.18, x, crownY + radius * 0.18, gold)
    }
}
