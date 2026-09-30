import Foundation

// Touch handling: Android's onTouchEvent split into one method per MotionEvent action, the long
// press, the crown / bezel scrub and the reset to now. Ported from SundialView.kt.
//
// Android's parent?.requestDisallowInterceptTouchEvent, performClick and performHapticFeedback
// have no equivalent inside the instrument: they are dropped (marked where they were), and the
// host handles gesture arbitration and haptics.

extension Instrument {
    func finishInteraction() {
        if dragMode == .event {
            inspectedEvent = nil
            inspectedCandidates = []
            inspectedCandidateIndex = 0
        }
        dragMode = .none
        dragStarted = false
        // parent?.requestDisallowInterceptTouchEvent(false) is dropped.
        invalidate()
    }

    /// MotionEvent.ACTION_DOWN. Like onTouchEvent, it always consumes the touch (returns true).
    @discardableResult
    public func pointerDown(x: Double, y: Double) -> Bool {
        let (cx, cy, r) = geometry()
        if transitionFrom != nil { return true }
        let nowTapped = layout.isWatch ? watchNowPill().inset(-8 * density, -8 * density).contains(x, y)
            : (y > height - 75 * density && x >= width * 0.2 && x <= width * 0.8)
        if !realtime && nowTapped {
            resetNow(); return true
        }
        longPressFired = false
        longPressX = x
        longPressY = y
        if horoscopeCards.contains(where: { $0.contains(x, y) }) {
            onHoroscopeTapped?(); return true
        }
        if beginEventInspection(x, y) { return true }
        let radiusFromCenter = distance(x, y, cx, cy)
        if state == .heliocentric &&
            distance(x, y, earthPoint.x, earthPoint.y) < reach(r * 0.09, 22) {
            dragMode = .year
            dragStartX = x
            dragStartY = y
            dragStarted = false
            // parent?.requestDisallowInterceptTouchEvent(true) is dropped.
            armLongPress()
            return true
        }
        if state == .heliocentric && radiusFromCenter < reach(r * 0.13, 26) {
            switchToState(.geocentric); return true
        }
        if state == .geocentric &&
            distance(x, y, moonPoint.x, moonPoint.y) < reach(r * 0.09, 22) {
            dragMode = .moon
            dragStartX = x
            dragStartY = y
            dragStarted = false
            // parent?.requestDisallowInterceptTouchEvent(true) is dropped.
            armLongPress()
            return true
        }
        if state == .galactic {
            // Drag anywhere to slide the ribbon of years; a tap returns to the Sun view.
            dragMode = .galaxy
            dragStartX = x
            dragStartY = y
            dragStartYear = GalacticGeometry.continuousYear(selectedInstant, zone)
            dragStarted = false
            // parent?.requestDisallowInterceptTouchEvent(true) is dropped.
            armLongPress()
            return true
        }
        if state == .geocentric && radiusFromCenter >= r * 0.53 && radiusFromCenter <= r * 0.75 {
            let touchAngle = atan2(y - cy, x - cx) * 180 / .pi
            let selected = TimeZoneDial.nearestSpoke(TimeZoneDial.spokes(selectedInstant, north: north), touchAngle)
            selectedTimeZoneOffsetMinutes = selected.offsetHours * 60
            selectedTimeZoneIsLocal = false
            invalidate()
            // performClick() is dropped.
            return true
        }
        if state == .geocentric && radiusFromCenter < r * 0.48 {
            switchToState(.heliocentric); return true
        }
        // Nothing under the finger: a long press here opens the host's settings.
        armLongPress()
        return true
    }

    /// MotionEvent.ACTION_MOVE.
    public func pointerMove(x: Double, y: Double) {
        // removeCallbacks(longPress)
        if distance(x, y, longPressX, longPressY) >= 8 * density { longPressDeadline = nil }
        switch dragMode {
        case .year:
            if dragStarted || distance(x, y, dragStartX, dragStartY) >= 8 * density {
                dragStarted = true
                realtime = false
                updateYearDrag(x, y)
            }
        case .moon:
            if dragStarted || distance(x, y, dragStartX, dragStartY) >= 8 * density {
                dragStarted = true
                realtime = false
                updateMoonDrag(x, y)
            }
        case .galaxy:
            if dragStarted || distance(x, y, dragStartX, dragStartY) >= 8 * density {
                dragStarted = true
                realtime = false
                updateGalacticDrag(x, y)
            }
        case .event: updateEventInspection(x, y)
        case .none: break
        }
    }

    /// MotionEvent.ACTION_UP.
    public func pointerUp(x: Double, y: Double) {
        longPressDeadline = nil  // removeCallbacks(longPress)
        if longPressFired { return }
        let galacticTap = dragMode == .galaxy && !dragStarted
        finishInteraction()
        if galacticTap { switchToState(.heliocentric) }
        // performClick() is dropped.
    }

    /// MotionEvent.ACTION_CANCEL.
    public func pointerCancel() {
        longPressDeadline = nil  // removeCallbacks(longPress)
        finishInteraction()
    }

    /// The same, in the pointerDown/Move/Up form docs/PORTING.md lists; like ACTION_CANCEL it
    /// ignores where the pointer was.
    public func pointerCancel(x: Double, y: Double) { pointerCancel() }

    /// The Android longPress Runnable. The host calls this once [longPressDeadline] has passed while
    /// the finger is still down. Like a posted Runnable it runs once, and not after it was removed.
    public func longPressElapsed() {
        guard longPressDeadline != nil else { return }
        longPressDeadline = nil
        if dragStarted { return }
        longPressFired = true
        finishInteraction()
        // performHapticFeedback(HapticFeedbackConstants.LONG_PRESS) is dropped: the host plays it.
        onLongPress?()
    }

    func armLongPress() {
        if onLongPress == nil { return }
        // removeCallbacks(longPress), then postDelayed(longPress, ViewConfiguration.getLongPressTimeout()).
        // ViewConfiguration.getLongPressTimeout(): 400 ms by default since Android 12 (the watch
        // targets Wear OS 4+, Android 13), where UILongPressGestureRecognizer waits 500 ms.
        longPressDeadline = uptime() + 0.4
    }

    /// Moves the instrument through time by [detents] steps of a watch crown or bezel: a day per
    /// step in the Sun view, twenty minutes in the Earth view and a month in the galactic view.
    public func scrubBy(_ detents: Double) {
        if transitionFrom != nil || detents == 0 { return }
        let secondsPerDetent: Double
        switch state {
        case .heliocentric: secondsPerDetent = 86_400.0
        case .geocentric: secondsPerDetent = 1_200.0
        case .galactic: secondsPerDetent = Astronomy.synodicMonthDays * 86_400.0
        }
        realtime = false
        // plusMillis of a truncated Long.
        selectedInstant = selectedInstant.addingTimeInterval(Double(Int64(secondsPerDetent * detents * 1_000)) / 1_000)
        invalidate()
    }

    func updateYearDrag(_ x: Double, _ y: Double) {
        let (cx, cy, _) = geometry()
        let canvasAngle = atan2(y - cy, x - cx) * 180 / .pi
        let fraction = DialGeometry.yearFractionFromAngle(canvasAngle, north)
        // Like Unity's angle search from the last date, keep scrubbing continuous across New Year
        // instead of wrapping back to the start of the displayed year.
        let current = selectedInstant
        // abs(Duration.between(current, it).seconds): getSeconds() floors (a negative duration
        // keeps its nanos positive), so -100.6 s counts as 101 s.
        func seconds(_ candidate: Date) -> Int64 { abs(Int64(candidate.timeIntervalSince(current).rounded(.down))) }
        selectedInstant = ((displayedYear - 1)...(displayedYear + 1))
            .map { Astronomy.instantAtYearFraction($0, fraction, zone) }
            .min(by: { seconds($0) < seconds($1) })!
        invalidate()
    }

    func updateMoonDrag(_ x: Double, _ y: Double) {
        let (cx, cy, _) = geometry()
        let touchAngle = atan2(y - cy, x - cx) * 180 / .pi
        let targetPhase = DialGeometry.phaseFromMoonAngle(touchAngle, north)
        let currentPhase = Astronomy.moonPhaseDegrees(selectedInstant)
        let difference = Astronomy.normalizeSignedDegrees(targetPhase - currentPhase)
        // plusSeconds of a truncated Long.
        selectedInstant = selectedInstant.addingTimeInterval(
            Double(Int64(difference / 360.0 * Astronomy.synodicMonthDays * 86_400)))
        invalidate()
    }

    /// The ribbon follows the finger: pulling it back against the direction of travel moves time on.
    func updateGalacticDrag(_ x: Double, _ y: Double) {
        let (_, _, r) = geometry()
        let g = GalacticGeometry.self
        let along = (x - dragStartX) * g.travelX + (y - dragStartY) * g.travelY
        selectedInstant = g.instantAt(dragStartYear - along / (r * g.yearPitch), zone)
        invalidate()
    }

    public func resetNow() {
        selectedInstant = currentDate()
        transitionFrom = nil
        transitionStartedAt = 0
        dragMode = .none
        dragStarted = false
        inspectedEvent = nil
        inspectedCandidates = []
        let (cx, cy, r) = geometry()
        let earthAngle = annualAngle(Astronomy.civilYearFraction(ZonedDateTime(selectedInstant, zone)))
        earthPoint = point(cx, cy, r * DialGeometry.earthOrbit, earthAngle)
        transitionEarthPoint = earthPoint
        selectedTimeZoneOffsetMinutes = TimeZoneDial.localOffsetMinutes(selectedInstant, zone)
        selectedTimeZoneIsLocal = true
        realtime = true
        onCalendarSelectionChanged?(Set(selectedCalendarIds))
        invalidate()
    }
}
