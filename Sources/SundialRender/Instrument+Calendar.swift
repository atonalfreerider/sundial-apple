import Foundation

// Calendar events on the dials: day-or-longer events as bands on the annual dial, shorter ones on
// the Earth view's hour dial, each titled along its arc; the long-press inspection card, and the
// hit testing that finds the events under a finger. Ported from SundialView.kt.
extension Instrument {
    /// Event titles on the dials never drop below a readable size, whatever Unity's proportions.
    func yearEventLabelSize(_ r: Double) -> Double { max(r * 0.036, 12.5 * density) }
    func dayEventLabelSize(_ hourR: Double) -> Double { max(hourR * 0.048, 13 * density) }

    func yearBand(_ r: Double, _ calendarId: Int64) -> DialGeometry.EventBand {
        DialGeometry.yearEventBand(r, calendarIndex(calendarId), minThickness: yearEventLabelSize(r) * 1.3)
    }

    func dayBand(_ hourR: Double, _ calendarId: Int64) -> DialGeometry.EventBand {
        DialGeometry.dayEventBand(hourR, calendarIndex(calendarId), minThickness: dayEventLabelSize(hourR) * 1.3)
    }

    public func yearEventBandForTest(_ calendarId: Int64) -> DialGeometry.EventBand { yearBand(geometry().r, calendarId) }

    func drawCalendarYearEvents(_ canvas: Canvas, _ cx: Double, _ cy: Double, _ r: Double) {
        let year = displayedYear
        var band = Paint()
        band.style = .stroke
        arcLabel.textSize = yearEventLabelSize(r)
        let annual = occurrences.filter(\.isYearRingEvent)
        let holidays = annual.filter { holidayCalendarIds.contains($0.calendarId) }
        let events = annual.filter { !holidayCalendarIds.contains($0.calendarId) }
        var labels: [ArcLabel] = []
        for event in events {
            guard let segment = CalendarIntervals.inYear(event, year, zone) else { continue }
            let eventBand = yearBand(r, event.calendarId)
            band.color = withAlpha(event.color, 145)
            band.strokeWidth = eventBand.thickness
            let arcBounds = Rect(cx - eventBand.centerRadius, cy - eventBand.centerRadius,
                                 cx + eventBand.centerRadius, cy + eventBand.centerRadius)
            canvas.drawArc(arcBounds, annualAngle(segment.startFraction),
                           (north ? -360.0 : 360.0) * segment.sweepFraction, false, band)
            labels.append(ArcLabel(event.title, eventBand.centerRadius,
                                   annualAngle(segment.startFraction + segment.sweepFraction / 2.0),
                                   max(segment.sweepFraction * 360.0, Instrument.minYearLabelDegrees),
                                   segment.sweepFraction))
        }
        let occupied = drawHolidayIcons(canvas, cx, cy, r, holidays, year)
        drawArcLabelsWithoutOverlap(canvas, cx, cy, labels, occupied)
    }

    func drawCalendarDayEvents(_ canvas: Canvas, _ cx: Double, _ cy: Double, _ hourR: Double) {
        let day = ZonedDateTime(selectedInstant, zone).date
        var band = Paint()
        band.style = .stroke
        arcLabel.textSize = dayEventLabelSize(hourR)
        var labels: [ArcLabel] = []
        for event in occurrences where !event.isYearRingEvent {
            guard let segment = CalendarIntervals.inDay(event, day, zone) else { continue }
            let eventBand = dayBand(hourR, event.calendarId)
            let minutes = max(segment.endMinuteExclusive - segment.startMinute, 1.0)
            band.color = withAlpha(event.color, 160)
            band.strokeWidth = eventBand.thickness
            let arcBounds = Rect(cx - eventBand.centerRadius, cy - eventBand.centerRadius,
                                 cx + eventBand.centerRadius, cy + eventBand.centerRadius)
            canvas.drawArc(arcBounds, hourAngle(segment.startMinute / 60.0),
                           (north ? -1.0 : 1.0) * minutes / 4.0, false, band)
            labels.append(ArcLabel(event.title, eventBand.centerRadius,
                                   hourAngle((segment.startMinute + segment.endMinuteExclusive) / 120.0),
                                   max(minutes / 4.0, Instrument.minDayLabelDegrees), minutes))
        }
        drawArcLabelsWithoutOverlap(canvas, cx, cy, labels, [])
    }

    struct ArcLabel {
        let title: String, radius: Double, midAngle: Double, maxSweep: Double, weight: Double
        init(_ title: String, _ radius: Double, _ midAngle: Double, _ maxSweep: Double, _ weight: Double) {
            self.title = title; self.radius = radius; self.midAngle = midAngle
            self.maxSweep = maxSweep; self.weight = weight
        }
    }

    struct ArcOccupation { let radius: Double, angle: Double, halfWidth: Double }

    func drawHolidayIcons(_ canvas: Canvas, _ cx: Double, _ cy: Double, _ r: Double,
                          _ holidays: [CalendarOccurrence], _ year: Int) -> [ArcOccupation] {
        if holidays.isEmpty { return [] }
        let size = yearEventLabelSize(r) * 1.05
        var iconPaint = Paint()
        iconPaint.textSize = size
        iconPaint.textAlign = .center
        var tick = Paint(style: .stroke)
        tick.strokeWidth = max(density, r * 0.004)
        var shown: [String: Double] = [:]
        var rows: [[Double]] = []
        var occupied: [ArcOccupation] = []
        let ordered = holidays.compactMap { event -> (CalendarOccurrence, YearSegment)? in
            CalendarIntervals.inYear(event, year, zone).map { (event, $0) }
        }.sorted { $0.1.startFraction < $1.1.startFraction }
        for (event, segment) in ordered {
            let icon = HolidayIcons.icon(for: event.title)
            if let previous = shown[icon], abs(previous - segment.startFraction) < 5.0 / 365.0 { continue }
            shown[icon] = segment.startFraction
            let eventBand = yearBand(r, event.calendarId)
            let angle = annualAngle(segment.startFraction + min(segment.sweepFraction, 1.0 / 365.0) / 2)
            tick.color = withAlpha(event.color, 220)
            drawRadialLine(canvas, cx, cy, eventBand.centerRadius - eventBand.thickness / 2,
                           eventBand.centerRadius + eventBand.thickness / 2, angle, tick)
            func rowRadius(_ row: Int) -> Double { eventBand.centerRadius - Double(row) * size * 1.15 }
            var row = 0
            while row < rows.count && rows[row].contains(where: {
                angularGap($0, angle) * .pi / 180 * rowRadius(row) < size * 1.05
            }) { row += 1 }
            if row > 2 { continue }
            if row == rows.count { rows.append([]) }
            rows[row].append(angle)
            let radius = rowRadius(row)
            occupied.append(ArcOccupation(radius: radius, angle: angle,
                                           halfWidth: (size * 0.55 / radius) * 180 / .pi))
            let p = point(cx, cy, radius, angle)
            canvas.save()
            canvas.rotate(-textScreenRotation, p.x, p.y)
            let metrics = canvas.fontMetrics(iconPaint)
            canvas.drawText(icon, p.x, p.y - (metrics.ascent + metrics.descent) / 2, iconPaint)
            canvas.restore()
        }
        return occupied
    }

    func drawArcLabelsWithoutOverlap(_ canvas: Canvas, _ cx: Double, _ cy: Double,
                                     _ labels: [ArcLabel], _ initial: [ArcOccupation]) {
        var placed = initial
        for label in labels.sorted(by: { $0.weight > $1.weight }) {
            guard let fitted = fitArcLabel(canvas, label.title, label.radius, label.maxSweep) else { continue }
            let half = (canvas.measureText(fitted, arcLabel) / label.radius) * 180 / .pi / 2
            let gap = (arcLabel.textSize * 0.6 / label.radius) * 180 / .pi
            if placed.contains(where: {
                abs($0.radius - label.radius) < arcLabel.textSize * 1.15 &&
                    angularGap($0.angle, label.midAngle) < half + $0.halfWidth + gap
            }) { continue }
            placed.append(ArcOccupation(radius: label.radius, angle: label.midAngle, halfWidth: half))
            drawArcLabel(canvas, fitted, cx, cy, label.radius, label.midAngle, label.maxSweep)
        }
    }

    func fitArcLabel(_ canvas: Canvas, _ value: String, _ radius: Double, _ maxSweep: Double) -> String? {
        let available = radius * (maxSweep * .pi / 180) * 0.92
        if available < arcLabel.textSize * 1.2 { return nil }
        let label = canvas.ellipsize(value, arcLabel, available)
        return label.allSatisfy(\.isWhitespace) ? nil : label
    }

    func angularGap(_ a: Double, _ b: Double) -> Double { abs(Astronomy.normalizeSignedDegrees(a - b)) }

    /// Draws [value] curved along a circle of [radius], centred on [midAngle] and ellipsized to fit
    /// [maxSweepDegrees] of arc. The path runs clockwise on the upper half of the screen and
    /// anticlockwise on the lower half, so the title always reads left to right.
    func drawArcLabel(_ canvas: Canvas, _ value: String, _ cx: Double, _ cy: Double, _ radius: Double,
                      _ midAngle: Double, _ maxSweepDegrees: Double) {
        guard let label = fitArcLabel(canvas, value, radius, maxSweepDegrees) else { return }
        // Light text with a soft dark halo reads on any calendar colour, on sky or brass.
        arcLabel.color = brass ? Colors.white : instrumentColor
        arcLabel.shadow = Shadow(radius: 2.5 * density, dx: 0, dy: 0, color: 0xD000_0000)
        let sweep = (canvas.measureText(label, arcLabel) / radius) * 180 / .pi
        let screenAngle = Astronomy.normalizeDegrees(midAngle + textScreenRotation)
        let lowerHalf = screenAngle > 0 && screenAngle < 180
        // Android adds the arc to a path and draws the text from the path's start.
        let startAngle: Double
        let clockwise: Bool
        if lowerHalf {
            // arcPath.addArc(arcBounds, midAngle + sweep / 2, -sweep)
            startAngle = midAngle + sweep / 2
            clockwise = false
        } else {
            // arcPath.addArc(arcBounds, midAngle - sweep / 2, sweep)
            startAngle = midAngle - sweep / 2
            clockwise = true
        }
        let metrics = canvas.fontMetrics(arcLabel)
        canvas.drawTextOnArc(label, cx: cx, cy: cy, radius: radius, startAngle: startAngle, clockwise: clockwise,
                             vOffset: -(metrics.ascent + metrics.descent) / 2, arcLabel)
    }

    func calendarIndex(_ calendarId: Int64) -> Int {
        let selectedIndex = selectedCalendarIds.firstIndex(of: calendarId) ?? -1
        if selectedIndex >= 0 { return selectedIndex }
        var seen = Set<Int64>()
        let distinctIds = occurrences.map { $0.calendarId }.filter { seen.insert($0).inserted }
        return max(distinctIds.firstIndex(of: calendarId) ?? -1, 0)
    }

    func drawEventInspectionOverlay(_ canvas: Canvas, _ event: CalendarOccurrence) {
        let cardWidth = min(width - 32 * density, 460 * density)
        let padding = 22 * density
        var titlePaint = Paint()
        titlePaint.color = instrumentColor
        titlePaint.textSize = 30 * screenDensity
        titlePaint.font = .sundialCondensed
        // StaticLayout takes a width in whole view pixels: truncate in device pixels (the overlay
        // draws untransformed, so pixelsPerUnit is the canvas's scale).
        let wrapWidth = Double(Int((cardWidth - 2 * padding) * pixelsPerUnit)) / pixelsPerUnit
        let titleLayout = canvas.layoutText(event.title, titlePaint, width: wrapWidth,
                                            maxLines: 3, alignment: .center)
        var timingPaint = text
        timingPaint.color = withAlpha(instrumentColor, 225)
        timingPaint.textSize = 19 * screenDensity
        let timing = canvas.ellipsize(eventTimingLabel(event), timingPaint, cardWidth - 2 * padding)
        let eyebrowHeight = 44 * density
        let cardHeight = eyebrowHeight + titleLayout.height + 18 * density + canvas.fontMetrics(timingPaint).fontSpacing +
            padding
        let bounds = Rect(
            (width - cardWidth) / 2,
            (height - cardHeight) / 2,
            (width + cardWidth) / 2,
            (height + cardHeight) / 2
        )
        var panel = Paint()
        panel.shader = .radial(
            center: Point(bounds.centerX, bounds.centerY), radius: bounds.width * 0.72,
            colors: [withAlpha(backgroundStyle.haloColor, 248), withAlpha(backgroundStyle.baseColor, 248)],
            stops: [0, 1]
        )
        canvas.drawRoundRect(bounds, 22 * density, 22 * density, panel)
        white.color = withAlpha(event.color, 245)
        white.strokeWidth = 2 * density
        canvas.drawRoundRect(bounds, 22 * density, 22 * density, white)

        let countLabel: String
        if inspectedCandidates.count > 1 {
            countLabel = "EVENT \(inspectedCandidateIndex + 1) OF \(inspectedCandidates.count) · DRAG TO CYCLE"
        } else {
            countLabel = "CALENDAR EVENT"
        }
        var eyebrow = text
        eyebrow.color = withAlpha(event.color, 255)
        eyebrow.textSize = 15 * density
        eyebrow.letterSpacing = 0.10
        canvas.drawText(countLabel, bounds.centerX, bounds.top + 30 * density, eyebrow)

        canvas.save()
        canvas.translate(bounds.left + padding, bounds.top + eyebrowHeight)
        canvas.drawTextBlock(titleLayout, 0, 0)
        canvas.restore()

        canvas.drawText(timing, bounds.centerX, bounds.bottom - padding - canvas.fontMetrics(timingPaint).descent,
                        timingPaint)
    }

    func eventTimingLabel(_ event: CalendarOccurrence) -> String {
        if event.isAllDay {
            let start = event.allDayStart!
            let endExclusive = event.allDayEndExclusive!
            if endExclusive == start.plusDays(1) {
                return "ALL DAY · \(CivilFormat.format(start, "EEE, MMM d"))"
            } else {
                return "ALL DAY · \(CivilFormat.format(start, "MMM d")) – " +
                    CivilFormat.format(endExclusive.minusDays(1), "MMM d")
            }
        }
        let localStart = event.start.withZone(zone)
        let localEnd = event.endExclusive.withZone(zone)
        let sameDay = localStart.date == localEnd.date
        if sameDay {
            return CivilFormat.format(localStart.instant, "EEE, MMM d · h:mm a", zone) +
                " – " + CivilFormat.format(localEnd.instant, "h:mm a", zone)
        } else {
            return CivilFormat.format(localStart.instant, "MMM d, h:mm a", zone) +
                " – " + CivilFormat.format(localEnd.instant, "MMM d, h:mm a", zone)
        }
    }

    func calendarEventsAt(_ x: Double, _ y: Double) -> [CalendarOccurrence] {
        let (cx, cy, r) = geometry()
        let radius = distance(x, y, cx, cy)
        let angle = atan2(y - cy, x - cx) * 180 / .pi
        let touchPadding = 13 * density
        switch state {
        case .heliocentric:
            let fraction = DialGeometry.yearFractionFromAngle(angle, north)
            return occurrences
                .filter { $0.isYearRingEvent }
                .compactMap { event -> (CalendarOccurrence, Double)? in
                    guard let segment = CalendarIntervals.inYear(event, displayedYear, zone) else { return nil }
                    let band = yearBand(r, event.calendarId)
                    if abs(radius - band.centerRadius) > band.thickness / 2 + touchPadding {
                        return nil
                    }
                    let angularPadding = (atan2(touchPadding, band.centerRadius) * 180 / .pi) / 360.0
                    if !CalendarHitTesting.containsYearFraction(
                        fraction, segment.startFraction, segment.sweepFraction, angularPadding
                    ) { return nil }
                    return (event, abs(radius - band.centerRadius))
                }
                .sorted { $0.1 < $1.1 }
                .map { $0.0 }
        case .geocentric:
            let minute = DialGeometry.minuteFromHourAngle(angle, north)
            let hourR = r * DialGeometry.hourDial
            return occurrences
                .filter { !$0.isYearRingEvent }
                .compactMap { event -> (CalendarOccurrence, Double)? in
                    guard let segment = CalendarIntervals.inDay(
                        event, ZonedDateTime(selectedInstant, zone).date, zone
                    ) else { return nil }
                    let band = dayBand(hourR, event.calendarId)
                    if abs(radius - band.centerRadius) > band.thickness / 2 + touchPadding {
                        return nil
                    }
                    let minutePadding = (atan2(touchPadding, band.centerRadius) * 180 / .pi) * 4.0
                    if !CalendarHitTesting.containsMinute(
                        minute, segment.startMinute, segment.endMinuteExclusive, minutePadding
                    ) { return nil }
                    return (event, abs(radius - band.centerRadius))
                }
                .sorted { $0.1 < $1.1 }
                .map { $0.0 }
        case .galactic:
            return []
        }
    }

    func beginEventInspection(_ x: Double, _ y: Double) -> Bool {
        let hits = calendarEventsAt(x, y)
        if hits.isEmpty { return false }
        dragMode = .event
        inspectedCandidates = hits
        inspectedCandidateIndex = 0
        inspectedEvent = hits.first
        eventCycleAnchorX = x
        eventCycleAnchorY = y
        // Android's parent?.requestDisallowInterceptTouchEvent(true) is dropped: the host owns
        // the gestures.
        invalidate()
        return true
    }

    func updateEventInspection(_ x: Double, _ y: Double) {
        let hits = calendarEventsAt(x, y)
        if hits.isEmpty { return }
        if hits != inspectedCandidates {
            inspectedCandidates = hits
            inspectedCandidateIndex = 0
            inspectedEvent = hits.first
            eventCycleAnchorX = x
            eventCycleAnchorY = y
        } else if hits.count > 1 && distance(x, y, eventCycleAnchorX, eventCycleAnchorY) >= 18 * density {
            inspectedCandidateIndex = (inspectedCandidateIndex + 1) % hits.count
            inspectedEvent = hits[inspectedCandidateIndex]
            eventCycleAnchorX = x
            eventCycleAnchorY = y
        }
        invalidate()
    }
}
