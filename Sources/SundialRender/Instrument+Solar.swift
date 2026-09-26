import Foundation

// The Sun-centred (heliocentric) view: the annual dial, seasons, zodiac, orbits, planets and the
// Earth's subdial. Ported from SundialView.kt, drawHeliocentric through drawPlanetGlyph.

extension Instrument {
    func drawHeliocentric(_ canvas: Canvas) {
        let (cx, cy, r) = geometry()
        drawDialFace(canvas, cx, cy, r)
        drawSeasonShading(canvas, cx, cy, r)
        drawAnnualBackdrop(canvas, cx, cy, r)
        drawHeliocentricForeground(canvas, cx, cy, r)
    }

    /// Parts of the Sun-centred instrument that Unity kept on screen after the camera flew to the
    /// Earth: the annual sprocket, season cross and the Earth spike that points at today's date.
    func drawAnnualBackdrop(_ canvas: Canvas, _ cx: Double, _ cy: Double, _ r: Double) {
        drawReverseSeasonRing(canvas, cx, cy, r)
        drawAnnualDial(canvas, cx, cy, r)
        drawSeasonCross(canvas, cx, cy, r)
        drawEarthSpike(canvas, cx, cy, r, currentEarthAngle())
    }

    /// Unity's Earth line: a translucent spike from the Sun through the Earth to the annual dial.
    func drawEarthSpike(_ canvas: Canvas, _ cx: Double, _ cy: Double, _ r: Double, _ angle: Double) {
        drawDialTriangle(canvas, cx, cy, r * 0.99, angle, r * 0.025, withAlpha(instrumentColor, 77))
    }

    func drawHeliocentricForeground(_ canvas: Canvas, _ cx: Double, _ cy: Double, _ r: Double, includeSun: Bool = true) {
        if zodiacProfile.enabled { drawZodiacRing(canvas, cx, cy, r) }
        if zodiacProfile.enabled { drawPlanetZodiacHands(canvas, cx, cy, r) }
        drawOrbitPaths(canvas, cx, cy, r)
        drawCalendarYearEvents(canvas, cx, cy, r)
        if includeSun { drawSun(canvas, cx, cy, r * 0.052) }
        if layout.isWatch && showClock {
            // In ambient the time is drawn above the dimmed instrument instead (drawAmbientTime).
            if ambient { return }
            var time = text
            time.textSize = r * 0.17
            time.shadow = Shadow(radius: 4 * density, dx: 0, dy: 0, color: brass && onFace ? 0x80FF_F3D0 : Colors.black)
            canvas.drawText(CivilFormat.format(selectedInstant, "HH:mm", zone), cx, cy - r * 0.5, time)
            return
        }
        text.textSize = r * 0.086
        canvas.drawText("S U N : D I A L", cx, cy - r * 0.56, text)
    }

    /// Sweep gradients for the season wash and the brass season band. Around each solstice and
    /// equinox the outgoing season's colour fades into the next rather than stopping at a line.
    ///
    /// The gradients are kept as colour stops (seasonWashColors, seasonBandColors,
    /// seasonPositions) and drawn about the centre by Canvas.fillSweep, so unlike Android's
    /// SeasonShaderKey the key leaves out [cx] and [cy].
    func updateSeasonShaders(_ cx: Double, _ cy: Double) {
        let date = ZonedDateTime(selectedInstant, zone).date
        let active = Zodiac.seasonFor(date, north)
        let key = SeasonShaderKey(year: date.year, active: active, north: north, style: backgroundStyle)
        if key == seasonShaderKey { return }
        seasonShaderKey = key
        let starts = SeasonBands.starts(date.year)
        let days = Astronomy.daysInYear(date.year)
        let metals: [ARGB] = [0xFFDC_A247, 0xFFB3_6A32, 0xFF8D_553B, 0xFF9B_B8C6]
        let bandScale = brass ? 0.55 : 1.0
        func wash(_ season: Zodiac.Season) -> ARGB {
            withAlpha(backgroundStyle.accentColor, displayedSeason(season) == active ? 28 : 7)
        }
        func band(_ season: Zodiac.Season) -> ARGB {
            withAlpha(metals[season.ordinal],
                      Int(Double(displayedSeason(season) == active ? 215 : 72) * bandScale))
        }
        let samples = 120
        let positions = (0...samples).map { Double($0) / Double(samples) }
        var washColors = [ARGB](repeating: 0, count: samples + 1)
        var bandColors = [ARGB](repeating: 0, count: samples + 1)
        for i in 0...samples {
            // Sweep gradients start at 3 o'clock and run clockwise, like canvas angles.
            let mix = SeasonBands.mixAt(DialGeometry.yearFractionFromAngle(360.0 * Double(i) / Double(samples), north),
                                        starts, days)
            washColors[i] = blendArgb(wash(mix.from), wash(mix.to), mix.amount)
            bandColors[i] = blendArgb(band(mix.from), band(mix.to), mix.amount)
        }
        seasonWashColors = washColors
        seasonBandColors = bandColors
        seasonPositions = positions
    }

    func drawSeasonShading(_ canvas: Canvas, _ cx: Double, _ cy: Double, _ r: Double) {
        if ambient { return }
        updateSeasonShaders(cx, cy)
        // The season wash: a filled disc of radius r * .965.
        canvas.fillSweep(center: Point(cx, cy), innerRadius: 0, outerRadius: r * 0.965,
                         colors: seasonWashColors, positions: seasonPositions, inMotion: cameraInMotion)
    }

    /// drawReverseSeasonRing with Kotlin's default [active]: the season of the selected date.
    func drawReverseSeasonRing(_ canvas: Canvas, _ cx: Double, _ cy: Double, _ r: Double, band: Bool = true) {
        drawReverseSeasonRing(canvas, cx, cy, r, band: band,
                              active: Zodiac.seasonFor(ZonedDateTime(selectedInstant, zone).date, north))
    }

    /// The season band, names and rim with [active] lit. [band] false keeps only the names and rim,
    /// as on the watch face's always-on dial.
    func drawReverseSeasonRing(_ canvas: Canvas, _ cx: Double, _ cy: Double, _ r: Double, band: Bool = true,
                               active: Zodiac.Season?) {
        if band {
            updateSeasonShaders(cx, cy)
            // Android strokes a circle of radius r * 1.025, r * .058 wide, with the sweep shader.
            let bandStrokeWidth = r * 0.058
            canvas.fillSweep(center: Point(cx, cy), innerRadius: r * 1.025 - bandStrokeWidth / 2,
                             outerRadius: r * 1.025 + bandStrokeWidth / 2,
                             colors: seasonBandColors, positions: seasonPositions, inMotion: cameraInMotion)
        }

        let year = ZonedDateTime(selectedInstant, zone).year
        let days = Double(Astronomy.daysInYear(year))
        func fraction(_ month: Int, _ day: Int) -> Double { Double(LocalDate(year, month, day).dayOfYear - 1) / days }
        let labels: [(Zodiac.Season, Double)] = [
            (.winter, fraction(2, 1)),
            (.spring, fraction(5, 6)),
            (.summer, fraction(8, 7)),
            (.fall, fraction(11, 6)),
        ]
        var labelPaint = text
        labelPaint.textSize = r * 0.027
        labelPaint.letterSpacing = 0.14
        for (season, labelAt) in labels {
            let displayed = displayedSeason(season)
            labelPaint.color = withAlpha(instrumentColor, displayed == active ? 245 : 105)
            // Kotlin's Season.name: the case name in capitals.
            drawRotatedText(canvas, String(describing: displayed).uppercased(), cx, cy, r * 1.025,
                            annualAngle(labelAt), labelPaint, true)
        }
        white.color = withAlpha(brass ? instrumentColor : backgroundStyle.accentColor, 125)
        white.strokeWidth = r * 0.003
        canvas.drawCircle(cx, cy, r * 1.057, white)
    }

    /// drawZodiacRing with Kotlin's defaults: the Sun's sign today lit and the profile's sign
    /// enamelled.
    func drawZodiacRing(_ canvas: Canvas, _ cx: Double, _ cy: Double, _ r: Double, glyphs: Bool = true) {
        drawZodiacRing(canvas, cx, cy, r,
                       activeSign: Zodiac.signFor(ZonedDateTime(selectedInstant, zone).date),
                       natalSign: zodiacProfile.resolvedSign(),
                       glyphs: glyphs)
    }

    /// The zodiac ring with [activeSign] (the Sun's sign today) lit and [natalSign] enamelled. The
    /// watch face passes null for both and [glyphs] false, then lays its own highlight and glyphs on.
    func drawZodiacRing(_ canvas: Canvas, _ cx: Double, _ cy: Double, _ r: Double,
                        activeSign: Zodiac.Sign?, natalSign: Zodiac.Sign?, glyphs: Bool = true) {
        let outer = r * DialGeometry.zodiacOuter
        let inner = r * DialGeometry.zodiacInner
        for sign in Zodiac.Sign.allCases {
            drawZodiacSector(canvas, cx, cy, r, sign, zodiacSectorColor(sign, sign == activeSign))
            let start = zodiacAngle(Double(sign.ordinal) * 30.0)
            white.color = withAlpha(instrumentColor, sign == activeSign ? 210 : 80)
            white.strokeWidth = sign == activeSign ? r * 0.004 : r * 0.0014
            drawRadialLine(canvas, cx, cy, inner, outer, start, white)
            if glyphs { drawZodiacGlyph(canvas, cx, cy, r, sign, sign == activeSign, sign == natalSign) }
        }
        white.color = withAlpha(instrumentColor, 150)
        white.strokeWidth = r * 0.0024
        canvas.drawCircle(cx, cy, inner, white)
        white.color = withAlpha(brass ? instrumentColor : 0xFFFF_D58A, 195)
        canvas.drawCircle(cx, cy, outer, white)
    }

    func zodiacSectorColor(_ sign: Zodiac.Sign, _ active: Bool) -> ARGB {
        brass
            ? withAlpha(instrumentColor, active ? 46 : sign.ordinal % 2 == 0 ? 14 : 0)
            : withAlpha(sign.ordinal % 2 == 0 ? 0xFFD5_A24F : 0xFF9B_6C3A, active ? 112 : 44)
    }

    func drawZodiacSector(_ canvas: Canvas, _ cx: Double, _ cy: Double, _ r: Double, _ sign: Zodiac.Sign, _ color: ARGB) {
        let outer = r * DialGeometry.zodiacOuter
        let inner = r * DialGeometry.zodiacInner
        let centerRadius = (outer + inner) / 2
        var sector = Paint()
        sector.style = .stroke
        sector.strokeWidth = outer - inner
        sector.strokeCap = .butt
        sector.color = color
        let arcBounds = Rect(cx - centerRadius, cy - centerRadius, cx + centerRadius, cy + centerRadius)
        canvas.drawArc(arcBounds, zodiacAngle(Double(sign.ordinal) * 30.0), north ? -30 : 30, false, sector)
    }

    func drawZodiacGlyph(_ canvas: Canvas, _ cx: Double, _ cy: Double, _ r: Double, _ sign: Zodiac.Sign,
                         _ active: Bool, _ natal: Bool) {
        let mid = zodiacAngle(Double(sign.ordinal) * 30.0 + 15.0)
        let glyphPoint = point(cx, cy, r * 0.797, mid)
        zodiacGlyphPaint.textSize = label(r * (active || natal ? 0.078 : 0.061), 8)
        if natal {
            zodiacGlyphPaint.color = brass ? Instrument.brassEnamelRed : 0xFFFF_D889
        } else if active {
            zodiacGlyphPaint.color = instrumentColor
        } else {
            zodiacGlyphPaint.color = withAlpha(brass ? instrumentColor : 0xFFFF_E7B0, 190)
        }
        let glyphPaint = zodiacGlyphPaint
        let metrics = canvas.fontMetrics(glyphPaint)
        canvas.drawText(sign.symbol, glyphPoint.x, glyphPoint.y - (metrics.ascent + metrics.descent) / 2, glyphPaint)
        // Too small to read on a watch; the glyphs carry the ring there.
        if layout.isWatch { return }
        var signPaint = dimText
        signPaint.textSize = r * 0.020
        signPaint.color = withAlpha(instrumentColor, active ? 225 : 105)
        drawRotatedText(canvas, String(sign.displayName.prefix(3)).uppercased(), cx, cy, r * 0.735, mid, signPaint, true)
    }

    func drawPlanetZodiacHands(_ canvas: Canvas, _ cx: Double, _ cy: Double, _ r: Double) {
        let earth = point(cx, cy, r * DialGeometry.earthOrbit, currentEarthAngle())
        let bodies: [(Astronomy.Body, ZodiacHand)] = [
            (.mercury, .mercury),
            (.venus, .venus),
            (.mars, .mars),
        ]
        for (body, zodiacHand) in bodies {
            let color = zodiacHand.colorIn(backgroundStyle)
            let heliocentricLongitude = Astronomy.heliocentricPosition(body, selectedInstant).longitudeDegrees
            let planet = point(cx, cy, r * orbitRatio(body), eclipticAngle(heliocentricLongitude))
            let sign = Zodiac.signForLongitude(Zodiac.geocentricLongitude(body, selectedInstant))
            let signPoint = point(cx, cy, r * DialGeometry.zodiacHandEnd, zodiacAngle(Double(sign.ordinal) * 30.0 + 15.0))
            var hand = zodiacHandPaint(zodiacHand, color, r)
            hand.strokeCap = .round
            canvas.drawLine(earth.x, earth.y, planet.x, planet.y, hand)
            hand.dash = [r * zodiacHand.dashRatio, r * zodiacHand.gapRatio]
            canvas.drawLine(planet.x, planet.y, signPoint.x, signPoint.y, hand)
            drawSignMarker(canvas, cx, cy, r, sign, color)
        }

        let sunLongitude = Zodiac.sunLongitude(selectedInstant)
        drawCelestialZodiacHand(canvas, earth, Point(cx, cy), sunLongitude, r, .sun, true)
        drawCelestialZodiacHand(canvas, earth, subdialMoonPoint(earth.x, earth.y, r, cx, cy),
                                Astronomy.moonLongitudeDegrees(selectedInstant), r, .moon, false)
    }

    func zodiacHandPaint(_ hand: ZodiacHand, _ color: ARGB, _ r: Double) -> Paint {
        var paint = Paint()
        paint.color = withAlpha(color, hand.alpha)
        paint.style = .stroke
        paint.strokeWidth = r * hand.strokeRatio
        return paint
    }

    /// Where a planet's hand meets the zodiac: a pearl, with the sign's glyph above it.
    func drawSignMarker(_ canvas: Canvas, _ cx: Double, _ cy: Double, _ r: Double, _ sign: Zodiac.Sign, _ color: ARGB) {
        let signPoint = point(cx, cy, r * DialGeometry.zodiacHandEnd, zodiacAngle(Double(sign.ordinal) * 30.0 + 15.0))
        fill.color = color
        canvas.drawCircle(signPoint.x, signPoint.y, r * 0.0065, fill)
        var medallion = Paint()
        medallion.color = withAlpha(color, 225)
        medallion.textSize = r * 0.034
        medallion.textAlign = .center
        medallion.font = .serif
        let metrics = canvas.fontMetrics(medallion)
        canvas.drawText(sign.symbol, signPoint.x,
                        signPoint.y - r * 0.012 - (metrics.ascent + metrics.descent) / 2, medallion)
    }

    func drawCelestialZodiacHand(_ canvas: Canvas, _ earth: Point, _ body: Point, _ longitude: Double, _ r: Double,
                                 _ zodiacHand: ZodiacHand, _ marker: Bool) {
        let sign = Zodiac.signForLongitude(longitude)
        let (cx, cy, _) = geometry()
        let signPoint = point(cx, cy, r * DialGeometry.zodiacHandEnd, zodiacAngle(Double(sign.ordinal) * 30.0 + 15.0))
        let color = zodiacHand.colorIn(backgroundStyle)
        var hand = zodiacHandPaint(zodiacHand, color, r)
        canvas.drawLine(earth.x, earth.y, body.x, body.y, hand)
        hand.dash = [r * zodiacHand.dashRatio, r * zodiacHand.gapRatio]
        canvas.drawLine(body.x, body.y, signPoint.x, signPoint.y, hand)
        if marker {
            white.color = color
            white.strokeWidth = r * 0.002
            canvas.drawCircle(body.x, body.y, r * 0.019, white)
            fill.color = color
            canvas.drawCircle(body.x, body.y, r * 0.005, fill)
        }
    }

    func displayedSeason(_ northernSeason: Zodiac.Season) -> Zodiac.Season {
        if north { return northernSeason }
        switch northernSeason {
        case .spring: return .fall
        case .summer: return .winter
        case .fall: return .spring
        case .winter: return .summer
        }
    }

    func drawAnnualDial(_ canvas: Canvas, _ cx: Double, _ cy: Double, _ r: Double) {
        let local = ZonedDateTime(selectedInstant, zone)
        drawAnnualScale(canvas, cx, cy, r, local.year)
        drawYearMarker(canvas, cx, cy, r, annualAngle(Astronomy.civilYearFraction(local)))
    }

    /// The annual dial's rings, a tick for every day and the month names. [sundays] false leaves
    /// out Unity's medium Sunday ticks, which the watch face turns as a ring of their own.
    func drawAnnualScale(_ canvas: Canvas, _ cx: Double, _ cy: Double, _ r: Double, _ year: Int, sundays: Bool = true) {
        let days = Astronomy.daysInYear(year)
        white.strokeWidth = max(1.1 * density, r * 0.0034)
        white.color = instrumentColor
        canvas.drawCircle(cx, cy, r, white)
        white.color = withAlpha(instrumentColor, 75)
        white.strokeWidth = max(0.5 * density, r * 0.0012)
        canvas.drawCircle(cx, cy, r * 0.978, white)
        for dayIndex in 0..<days {
            let date = LocalDate.ofYearDay(year, dayIndex + 1)
            // Unity's sun sprocket gives every Sunday a medium tick.
            drawDayTick(canvas, cx, cy, r, annualAngle(Double(dayIndex) / Double(days)),
                        date.day == 1,
                        sundays && date.dayOfWeek == 7)
        }
        text.textSize = label(r * 0.039, 8)
        for month in 1...12 {
            let date = LocalDate(year, month, 15)
            let fraction = (Double(date.dayOfYear) - 0.5) / Double(days)
            drawRotatedText(canvas, date.monthAbbreviation, cx, cy, r * 0.915, annualAngle(fraction), text, true)
        }
    }

    func drawDayTick(_ canvas: Canvas, _ cx: Double, _ cy: Double, _ r: Double, _ angle: Double,
                     _ monthStart: Bool, _ week: Bool) {
        let length: Double
        if monthStart {
            length = r * 0.062
        } else if week {
            length = r * 0.036
        } else {
            length = r * 0.019
        }
        white.color = withAlpha(instrumentColor, monthStart ? 255 : week ? 205 : 145)
        white.strokeWidth = monthStart ? r * 0.003 : r * 0.0017
        drawRadialLine(canvas, cx, cy, r - length, r * 0.995, angle, white)
    }

    /// Today's line across the month names, ending in a diamond on the rim.
    func drawYearMarker(_ canvas: Canvas, _ cx: Double, _ cy: Double, _ r: Double, _ angle: Double) {
        var marker = Paint()
        marker.color = withAlpha(instrumentColor, 210)
        marker.strokeWidth = r * 0.004
        drawRadialLine(canvas, cx, cy, r * 0.77, r * 1.015, angle, marker)
        let nowPoint = point(cx, cy, r * 1.015, angle)
        fill.color = instrumentColor
        canvas.save()
        canvas.rotate(angle + 45.0, nowPoint.x, nowPoint.y)
        canvas.drawRect(nowPoint.x - r * 0.008, nowPoint.y - r * 0.008,
                        nowPoint.x + r * 0.008, nowPoint.y + r * 0.008, fill)
        canvas.restore()
    }

    func drawSeasonCross(_ canvas: Canvas, _ cx: Double, _ cy: Double, _ r: Double) {
        // Unity: dotted solstice and equinox lines spanning the full dial, 45 dots per diameter.
        var dotPaint = Paint()
        dotPaint.color = withAlpha(instrumentColor, 128)
        let spacing = 2 * r / 45
        let size = max(0.9 * density, r * 0.0028)
        for i in -22...22 {
            canvas.drawCircle(cx, cy + Double(i) * spacing, size, dotPaint)
            canvas.drawCircle(cx + Double(i) * spacing, cy, size, dotPaint)
        }
    }

    /// Brass Watch aesthetic: the annual dial engraved into a polished brass face inside a turned
    /// bezel. It is drawn in the Sun's frame, so the Earth camera flies across the same face.
    ///
    /// Android caches the face's shaders by FaceKey(cx, cy, r); here they are plain values, built
    /// each frame, and the bezel's sweep gradient is drawn by Canvas.fillSweep.
    func drawDialFace(_ canvas: Canvas, _ cx: Double, _ cy: Double, _ r: Double) {
        // A lit brass disc would defeat an always-on display's black background.
        if !brass || ambient { return }
        var faceShadow = Paint()
        faceShadow.shader = .radial(center: Point(cx + r * 0.03, cy + r * 0.06), radius: r * 1.2,
                                    colors: [0xB000_0000, 0x7000_0000, Colors.transparent], stops: [0, 0.88, 1])
        var facePaint = Paint()
        facePaint.shader = .radial(center: Point(cx - r * 0.38, cy - r * 0.46), radius: r * 1.95,
                                   colors: [0xFFFF_F6D6, 0xFFF2_D98F, 0xFFDD_B764, 0xFFBE_9240, 0xFF9A_6F28],
                                   stops: [0, 0.2, 0.46, 0.76, 1])
        let bezelColors: [ARGB] = [0xFFF7_E3A2, 0xFFA5_762B, 0xFFFF_F2C6, 0xFF8C_6220,
                                   0xFFF1_D68B, 0xFFAE_7F32, 0xFFF7_E3A2]
        var bezelShade = Paint(style: .stroke)
        bezelShade.shader = .radial(center: Point(cx, cy), radius: r * 1.07,
                                    colors: [Colors.transparent, 0x50FF_FFFF, Colors.transparent, 0x7000_0000],
                                    stops: [0.93, 0.965, 0.985, 1])
        canvas.drawCircle(cx, cy, r * 1.2, faceShadow)
        // The bezel: Android strokes a circle of radius r * 1.032, r * .07 wide, with the sweep.
        let bezelStrokeWidth = r * 0.07
        canvas.fillSweep(center: Point(cx, cy), innerRadius: r * 1.032 - bezelStrokeWidth / 2,
                         outerRadius: r * 1.032 + bezelStrokeWidth / 2, colors: bezelColors, positions: nil,
                         inMotion: cameraInMotion)
        bezelShade.strokeWidth = r * 0.07
        canvas.drawCircle(cx, cy, r * 1.032, bezelShade)
        canvas.drawCircle(cx, cy, r, facePaint)
        // Faint turned rings in the metal, and a milled edge where face meets bezel.
        white.color = withAlpha(instrumentColor, 10)
        white.strokeWidth = max(devicePixels(0.5), r * 0.0015)
        var ring = r * 0.1
        while ring < r * 0.99 {
            canvas.drawCircle(cx, cy, ring, white)
            ring += r * 0.045
        }
        white.color = withAlpha(instrumentColor, 95)
        white.strokeWidth = max(devicePixels(0.5), r * 0.0022)
        for i in 0..<240 { drawRadialLine(canvas, cx, cy, r * 1.002, r * 1.012, Double(i) * 1.5, white) }
        white.color = withAlpha(instrumentColor, 150)
        white.strokeWidth = max(devicePixels(0.6), r * 0.003)
        canvas.drawCircle(cx, cy, r * 1.066, white)
    }

    func drawOrbitPaths(_ canvas: Canvas, _ cx: Double, _ cy: Double, _ r: Double) {
        for body in [Astronomy.Body.mars, Astronomy.Body.venus, Astronomy.Body.mercury, Astronomy.Body.earth] {
            let angle: Double
            if body == .earth {
                // The Unity Earth hand is the civil calendar hand: it must agree with the annual dial.
                angle = currentEarthAngle()
            } else {
                angle = eclipticAngle(Astronomy.heliocentricPosition(body, selectedInstant).longitudeDegrees)
            }
            drawOrbit(canvas, body, cx, cy, r, angle)
            let point = self.point(cx, cy, r * orbitRatio(body), angle)
            if body == .earth {
                drawEarthSubdial(canvas, point.x, point.y, r, cx, cy)
                earthPoint = point
            } else {
                drawPlanetMarker(canvas, body, point.x, point.y, r, cx, cy)
            }
        }
    }

    func orbitRatio(_ body: Astronomy.Body) -> Double {
        switch body {
        case .mercury: return DialGeometry.mercuryOrbit
        case .venus: return DialGeometry.venusOrbit
        case .earth: return DialGeometry.earthOrbit
        case .mars: return DialGeometry.marsOrbit
        }
    }

    /// A planet's trail and its hand from the Sun, with the planet at [angle].
    func drawOrbit(_ canvas: Canvas, _ body: Astronomy.Body, _ cx: Double, _ cy: Double, _ r: Double, _ angle: Double) {
        let orbitR = r * orbitRatio(body)
        let isEarth = body == .earth
        drawOrbitTrail(
            canvas, cx, cy, orbitR, angle,
            isEarth ? 0.833 : 0.33,
            isEarth ? max(1.4 * density, r * 0.0045) : max(1 * density, r * 0.003),
            isEarth ? 235 : 128)
        // Unity's translucent planet hands; the Earth hand is the solid one.
        let handColor: ARGB
        switch body {
        case .mercury: handColor = Colors.argb(77, 102, 128, 153)
        case .venus: handColor = Colors.argb(77, 247, 247, 217)
        case .earth: handColor = brass ? instrumentColor : Colors.white
        case .mars: handColor = Colors.argb(77, 230, 51, 77)
        }
        drawDialTriangle(canvas, cx, cy, orbitR, angle, isEarth ? r * 0.01665 : r * 0.00665, handColor)
    }

    /// Unity drew each orbit as a trail behind the planet (a third of the orbit, five sixths for
    /// Earth) that thins to nothing at its tail, rather than a full circle.
    func drawOrbitTrail(_ canvas: Canvas, _ cx: Double, _ cy: Double, _ radius: Double, _ headAngle: Double,
                        _ sweepFraction: Double, _ headWidth: Double, _ alpha: Int) {
        let segments = 72
        // Planets advance counter-clockwise in the north view, so the trail lies clockwise of them.
        let direction: Double = north ? 1 : -1
        let sweep = 360 * sweepFraction / Double(segments)
        let bounds = Rect(cx - radius, cy - radius, cx + radius, cy + radius)
        var trail = Paint()
        trail.style = .stroke
        trail.strokeCap = .butt
        for i in 0..<segments {
            let t = Double(i) / Double(segments)
            trail.strokeWidth = max(headWidth * (1 - t), 0.35 * density)
            trail.color = withAlpha(instrumentColor, Int(Double(alpha) * (1 - 0.55 * t)))
            canvas.drawArc(bounds, headAngle + direction * Double(i) * sweep, direction * sweep * 1.04, false, trail)
        }
    }

    /// Astronomy mode shows each planet as a small world; astrology mode engraves the classical
    /// symbols instead (☿ ♀ ⊕ ♂), like the hands of an astrological watch.
    func drawPlanetMarker(_ canvas: Canvas, _ body: Astronomy.Body, _ x: Double, _ y: Double, _ r: Double,
                          _ sunX: Double, _ sunY: Double) {
        if !zodiacProfile.enabled {
            drawPlanetGlyph(canvas, body, x, y, r, sunX, sunY)
            return
        }
        let tint: ARGB
        if brass {
            tint = instrumentColor
        } else if body == .mercury {
            tint = 0xFFD3_DEE6
        } else if body == .venus {
            tint = 0xFFFF_E2A6
        } else if body == .mars {
            tint = 0xFFFF_9A7E
        } else {
            tint = 0xFFB5_E6FF
        }
        // A pearl where the hand ends, as on the watch, and the symbol riding just beyond it.
        fill.color = brass ? 0xFFF4_F1E8 : withAlpha(tint, 235)
        canvas.drawCircle(x, y, r * 0.011, fill)
        symbolPaint.color = tint
        // setShadowLayer(0, 0, 0, 0) on Brass Watch: a zero radius removes the shadow on Android.
        symbolPaint.shadow = brass ? nil : Shadow(radius: r * 0.01, dx: 0, dy: 0, color: 0xB000_0000)
        symbols.draw(canvas, body, x, y - r * 0.056, r * 0.036, symbolPaint)
    }

    /// Where the Moon sits on the Earth's subdial: the Earth view's lunar hand, turned into this view.
    func subdialMoonPoint(_ x: Double, _ y: Double, _ r: Double, _ sunX: Double, _ sunY: Double) -> Point {
        let turn = atan2(sunY - y, sunX - x) * 180 / .pi + 90.0
        let angle = DialGeometry.moonAngle(Astronomy.moonPhaseDegrees(selectedInstant), north) + turn
        return point(x, y, r * DialGeometry.subdialMoonTrack, angle)
    }

    /// The Earth's own small dial in the solar view, like the silver gear on an astrological watch:
    /// a 24-hour sprocket ring with noon toward the Sun and an enlarged Moon on its lunar track.
    /// It is the Earth view in miniature, so the camera flight simply grows it into that view.
    func drawEarthSubdial(_ canvas: Canvas, _ x: Double, _ y: Double, _ r: Double, _ sunX: Double, _ sunY: Double) {
        let turn = atan2(sunY - y, sunX - x) * 180 / .pi + 90.0
        drawSubdialGear(canvas, x, y, r, turn)
        let moon = subdialMoonPoint(x, y, r, sunX, sunY)
        drawSubdialMoonHand(canvas, x, y, r, atan2(moon.y - y, moon.x - x) * 180 / .pi)
        drawSubdialMoon(canvas, moon.x, moon.y, r, sunX, sunY)
        if zodiacProfile.enabled {
            drawSubdialEnamel(canvas, x, y, r)
            drawSubdialEarthSymbol(canvas, x, y, r)
        } else {
            drawEarthSeal(canvas, x, y, r * DialGeometry.heliocentricEarthRadius, sunX, sunY, false)
        }
    }

    var subdialMetal: ARGB {
        if brass { return 0xFFF1_F0EA }
        if zodiacProfile.enabled { return 0xFFE3_E6EA }
        return instrumentColor
    }

    /// The Earth's 24-hour gear and lunar track; [turn] puts noon toward the Sun.
    func drawSubdialGear(_ canvas: Canvas, _ x: Double, _ y: Double, _ r: Double, _ turn: Double) {
        let gearR = r * DialGeometry.subdialGear
        let metal = subdialMetal
        if brass && !ambient {
            // Polished steel gear set into the brass: a dark seat, then the bright ring.
            white.color = withAlpha(instrumentColor, 120)
            white.strokeWidth = r * 0.02
            canvas.drawCircle(x, y, gearR + r * 0.004, white)
        }
        white.color = withAlpha(instrumentColor, brass ? 120 : 110)
        white.strokeWidth = r * 0.0026
        canvas.drawCircle(x, y, r * DialGeometry.subdialMoonTrack, white)
        white.color = metal
        white.strokeWidth = r * 0.006
        canvas.drawCircle(x, y, gearR, white)
        polygon.color = metal
        for hour in 0..<24 {
            drawSprocketTooth(canvas, x, y, gearR, gearR + r * (hour % 6 == 0 ? 0.017 : 0.011),
                              hourAngle(Double(hour)) + turn, r * 0.0048, r * 0.0008, polygon)
        }
    }

    func drawSubdialMoonHand(_ canvas: Canvas, _ x: Double, _ y: Double, _ r: Double, _ angle: Double) {
        drawAnnularPointer(canvas, x, y, r * (DialGeometry.subdialGear + 0.012), r * DialGeometry.subdialMoonTrack,
                           angle, r * 0.006, withAlpha(subdialMetal, 200))
    }

    func drawSubdialMoon(_ canvas: Canvas, _ x: Double, _ y: Double, _ r: Double, _ sunX: Double, _ sunY: Double) {
        if zodiacProfile.enabled {
            fill.color = brass ? instrumentColor : 0xFFFF_EAB5
            symbols.drawCrescent(canvas, x, y, r * 0.05, atan2(sunY - y, sunX - x) * 180 / .pi, fill)
        } else {
            drawMoonGlyph(canvas, x, y, r * 0.027, sunX, sunY)
        }
    }

    /// Astrology mode: the enamel disc in the middle of the gear, which carries the ⊕.
    func drawSubdialEnamel(_ canvas: Canvas, _ x: Double, _ y: Double, _ r: Double) {
        // Brass Watch's white enamel would be a bright blob on the always-on display.
        if brass && ambient { return }
        fill.color = brass ? 0xFFE9_E7DF : withAlpha(0xFF0D_1B2A, 200)
        canvas.drawCircle(x, y, r * DialGeometry.subdialGear * 0.82, fill)
    }

    /// ⊕ engraved in the middle of the gear, as on the watch.
    func drawSubdialEarthSymbol(_ canvas: Canvas, _ x: Double, _ y: Double, _ r: Double) {
        symbolPaint.color = brass ? instrumentColor : subdialMetal
        symbolPaint.shadow = nil
        symbols.draw(canvas, .earth, x, y, r * DialGeometry.subdialGear * 1.25, symbolPaint)
    }

    func drawPlanetGlyph(_ canvas: Canvas, _ body: Astronomy.Body, _ x: Double, _ y: Double, _ r: Double,
                         _ sunX: Double, _ sunY: Double) {
        let radius: Double
        switch body {
        case .mercury: radius = r * 0.017
        case .venus: radius = r * 0.026
        case .earth: radius = r * 0.025
        case .mars: radius = r * 0.021
        }
        let color: ARGB
        switch body {
        case .mercury: color = Colors.rgb(150, 163, 174)
        case .venus: color = Colors.rgb(255, 218, 147)
        case .earth: color = Colors.rgb(78, 190, 235)
        case .mars: color = Colors.rgb(231, 82, 62)
        }
        if brass {
            // Set into metal rather than glowing in space: a small cast shadow instead of an aura.
            fill.color = 0x5500_0000
            canvas.drawCircle(x + radius * 0.18, y + radius * 0.24, radius * 1.08, fill)
        } else {
            var aura = Paint()
            aura.shader = .radial(center: Point(x, y), radius: radius * 3.2,
                                  colors: [withAlpha(color, 125), withAlpha(color, 45), Colors.transparent],
                                  stops: [0, 0.38, 1])
            canvas.drawCircle(x, y, radius * 3.2, aura)
        }
        fill.color = color
        canvas.drawCircle(x, y, radius, fill)
        switch body {
        case .mercury:
            var facet = Paint()
            facet.color = 0xFFDC_E4E8
            var path = Path()
            path.moveTo(x, y - radius * 0.8); path.lineTo(x + radius * 0.62, y)
            path.lineTo(x, y + radius * 0.5); path.lineTo(x - radius * 0.48, y); path.close()
            canvas.drawPath(path, facet)
            white.color = 0xAAFF_FFFF; white.strokeWidth = r * 0.0013
            canvas.drawCircle(x, y, radius * 1.35, white)
        case .venus:
            // Venus is an opaque cloud pearl, deliberately distinct from the phase-rendered Moon.
            var cloud = Paint()
            cloud.color = 0xA6FF_F0C1
            cloud.style = .stroke
            cloud.strokeWidth = radius * 0.18
            cloud.strokeCap = .round
            canvas.drawArc(Rect(x - radius * 0.78, y - radius * 0.5, x + radius * 0.72, y + radius * 0.08),
                           16, 148, false, cloud)
            cloud.color = 0x80C9_9457
            cloud.strokeWidth = radius * 0.13
            canvas.drawArc(Rect(x - radius * 0.72, y - radius * 0.02, x + radius * 0.8, y + radius * 0.62),
                           188, 150, false, cloud)
            white.color = 0x99FF_E0A3; white.strokeWidth = r * 0.0015
            canvas.drawCircle(x, y, radius * 1.12, white)
        case .earth:
            drawEarthSeal(canvas, x, y, radius * 1.42, sunX, sunY, false)
        case .mars:
            fill.color = 0xFF71_291F
            canvas.drawCircle(x - radius * 0.2, y - radius * 0.14, radius * 0.24, fill)
            var slash = Paint()
            slash.color = 0xCCFF_B089; slash.strokeWidth = radius * 0.2; slash.strokeCap = .round
            canvas.drawLine(x - radius * 0.55, y + radius * 0.45, x + radius * 0.58, y - radius * 0.5, slash)
            white.color = 0x99FF_866F; white.strokeWidth = r * 0.0015
            canvas.drawCircle(x, y, radius * 1.18, white)
        }
    }
}

/// Astrology hands from the Earth to each body and on to its sign. On Android the Wear OS watch
/// face (WatchFaceLayer.kt, not ported) shares them and draws them as lines.
public enum ZodiacHand: CaseIterable, Sendable {
    case sun, moon, mercury, venus, mars

    /// Kotlin's enum constructor arguments: color, alpha, strokeRatio, dashRatio, gapRatio.
    private var parameters: (color: ARGB, alpha: Int, strokeRatio: Double, dashRatio: Double, gapRatio: Double) {
        switch self {
        case .sun: return (0xFFFF_D17A, 135, 0.0021, 0.010, 0.011)
        case .moon: return (0xFFFF_EAB5, 135, 0.0021, 0.010, 0.011)
        case .mercury: return (0xFF8E_A5B8, 145, 0.0022, 0.012, 0.010)
        case .venus: return (0xFFFF_CE7A, 145, 0.0022, 0.012, 0.010)
        case .mars: return (0xFFE8_735C, 145, 0.0022, 0.012, 0.010)
        }
    }

    private var color: ARGB { parameters.color }
    public var alpha: Int { parameters.alpha }
    public var strokeRatio: Double { parameters.strokeRatio }
    public var dashRatio: Double { parameters.dashRatio }
    public var gapRatio: Double { parameters.gapRatio }

    /// Brass Watch engraves every hand in its ink.
    public func colorIn(_ style: CelestialStyle) -> ARGB { style.brassFace ? style.instrumentColor : color }
}
