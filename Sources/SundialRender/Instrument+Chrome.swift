import Foundation

// Everything drawn over the instrument rather than on it: the clock, the reset pill, the zone
// caption's ink, the watch's time and NOW pill, the always-on time and the horoscope cards.
// Ported from SundialView.kt.

extension Instrument {
    func drawChrome(_ canvas: Canvas) {
        horoscopeCards.removeAll()
        if layout.isWatch {
            drawWatchChrome(canvas)
            return
        }
        // In the Earth view the brass face fills the top of the screen, so text there is engraved.
        useInk(brass && state == .geocentric && transitionFrom == nil)
        if showClock {
            text.textSize = 24 * density
            canvas.drawText(CivilFormat.format(selectedInstant, "dd/MM/yy   HH : mm : ss", zone), width / 2, 33 * density, text)
        }
        if !realtime {
            fill.color = Colors.argb(220, 15, 15, 15)
            let rect = Rect(width * 0.27, height - 60 * density, width * 0.73, height - 14 * density)
            canvas.drawRoundRect(rect, 18 * density, 18 * density, fill)
            white.color = backgroundStyle.chromeColor; white.strokeWidth = density
            canvas.drawRoundRect(rect, 18 * density, 18 * density, white)
            var label = text
            label.textSize = 15 * density
            label.color = backgroundStyle.chromeColor
            canvas.drawText("RESET CURRENT TIME", width / 2, height - 29 * density, label)
        }
        if state == .geocentric && transitionFrom == nil { drawSelectedZoneCaption(canvas) }
        useInk(false)
        if zodiacProfile.enabled, let horoscope = horoscopeText { drawHoroscopeCard(canvas, horoscope, false) }
    }

    /// A watch shows the time and, after scrubbing, a small NOW pill. There is no room for readings,
    /// captions or event cards; the Sun view's title already shows the time when the clock is on.
    func drawWatchChrome(_ canvas: Canvas) {
        let (cx, cy, r) = geometry()
        // The Sun view's title carries the time; a round Earth view has no free edge for it, and its
        // hour dial already shows the time. A rectangular face uses the strip below the dial.
        if showClock && state != .heliocentric && layout == .watchRect {
            var time = text
            time.textSize = 15 * density
            time.color = backgroundStyle.chromeColor
            time.shadow = Shadow(radius: 3 * density, dx: 0, dy: 0, color: Colors.black)
            let metrics = canvas.fontMetrics(time)
            let y = (cy + r * 1.1 + height) / 2 - (metrics.ascent + metrics.descent) / 2
            // The NOW pill takes the middle of the strip once time has been scrubbed.
            let x = realtime ? cx : width * 0.17
            canvas.drawText(CivilFormat.format(selectedInstant, "HH:mm", zone), x, y, time)
        }
        if !realtime {
            let rect = watchNowPill()
            fill.color = Colors.argb(225, 15, 15, 15)
            canvas.drawRoundRect(rect, rect.height / 2, rect.height / 2, fill)
            white.color = backgroundStyle.chromeColor; white.strokeWidth = density
            canvas.drawRoundRect(rect, rect.height / 2, rect.height / 2, white)
            var now = text
            now.textSize = 12 * density; now.color = backgroundStyle.chromeColor; now.letterSpacing = 0.12
            let metrics = canvas.fontMetrics(now)
            canvas.drawText("NOW", rect.centerX, rect.centerY - (metrics.ascent + metrics.descent) / 2, now)
        }
    }

    /// The time stays the brightest thing on an always-on watch face: plain grey, no halo.
    func drawAmbientTime(_ canvas: Canvas) {
        if !layout.isWatch || !showClock { return }
        let (cx, cy, r) = geometry()
        var time = text
        time.color = 0xFFC8_C8C8
        let y: Double
        if state == .heliocentric {
            time.textSize = r * 0.17; y = cy - r * 0.5
        } else if layout == .watchRect {
            time.textSize = 15 * density
            let metrics = canvas.fontMetrics(time)
            y = (cy + r * 1.1 + height) / 2 - (metrics.ascent + metrics.descent) / 2
        } else {
            return
        }
        canvas.drawText(CivilFormat.format(selectedInstant, "HH:mm", zone), cx, y, time)
    }

    /// Sits inside the bottom of a round face, where the circle is still wide enough for it.
    func watchNowPill() -> Rect {
        let bottom = height - 14 * density
        return Rect(width * 0.34, bottom - 26 * density, width * 0.66, bottom)
    }

    func drawHoroscopeCard(_ canvas: Canvas, _ value: String, _ forWallpaper: Bool) {
        let (_, cy, r) = geometry()
        let cardWidth = min(width - 32 * density, 430 * density)
        let left = (width - cardWidth) / 2
        let right = left + cardWidth
        // The Earth view keeps the Sun above the lunar dial and the annual dial arcing below it.
        let geocentric = state == .geocentric
        let dialTop = cy - r * (geocentric ? 1.14 : 1.08)
        let dialBottom = cy + r * (geocentric ? 1.16 : 1.08)
        // In the app, keep clear of the tuck-menu buttons in three corners.
        let topBounds = Rect(left, (forWallpaper ? 66 : 80) * density, right, dialTop - 10 * density)
        let bottomLimit = height - (forWallpaper ? 16 : 84) * density
        let bottomBounds = Rect(left, dialBottom + 10 * density, right, bottomLimit)
        let minimumPanelHeight = 92 * density
        let sign = zodiacProfile.resolvedSign()

        // Landscape tablets and foldables (Android 16 ignores the portrait lock there): the dial
        // fills the height, so the reading sits in the free space either side of it instead.
        let (dialCx, _, _) = geometry()
        let sideWidth = min(dialCx - r * 1.1 - 28 * density, 360 * density)
        if sideWidth >= 150 * density && topBounds.height < minimumPanelHeight {
            let (first, second) = splitHoroscope(value)
            let top = (forWallpaper ? 24 : 80) * density
            let bottom = height - (forWallpaper ? 24 : 84) * density
            let cardHeight = min(bottom - top, 380 * density)
            let cardTop = top + (bottom - top - cardHeight) / 2
            drawHoroscopePanel(canvas, Rect(16 * density, cardTop, 16 * density + sideWidth, cardTop + cardHeight),
                               "\(sign.symbol)  \(sign.displayName.uppercased()) · TODAY'S ORACLE", first)
            drawHoroscopePanel(canvas, Rect(width - 16 * density - sideWidth, cardTop, width - 16 * density, cardTop + cardHeight),
                               forWallpaper ? "CONTINUED · CELESTIAL WALLPAPER" : "WRITTEN BY ON-DEVICE AI · TAP TO REPORT", second)
            return
        }

        if topBounds.height >= minimumPanelHeight && bottomBounds.height >= minimumPanelHeight {
            let (first, second) = splitHoroscope(value)
            drawHoroscopePanel(
                canvas,
                topBounds,
                "\(sign.symbol)  \(sign.displayName.uppercased()) · TODAY'S ORACLE",
                first
            )
            drawHoroscopePanel(
                canvas,
                bottomBounds,
                forWallpaper ? "CONTINUED · CELESTIAL WALLPAPER" : "WRITTEN BY ON-DEVICE AI · TAP TO REPORT",
                second
            )
            return
        }

        let fallbackHeight = min(height * 0.30, 250 * density)
        var fallbackTop = max(bottomLimit - fallbackHeight, dialBottom + 8 * density)
        // No free band below the dial either: lay the card over the dial's lower edge rather than
        // lose the reading.
        if bottomLimit - fallbackTop < 120 * density { fallbackTop = bottomLimit - min(fallbackHeight, 170 * density) }
        drawHoroscopePanel(
            canvas,
            Rect(left, fallbackTop, right, bottomLimit),
            "\(sign.symbol)  \(sign.displayName.uppercased()) · TODAY'S ORACLE",
            value
        )
    }

    func drawHoroscopePanel(_ canvas: Canvas, _ bounds: Rect, _ title: String, _ value: String) {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || bounds.height < 64 * density { return }
        horoscopeCards.append(bounds)
        var bodyPaint = Paint()
        bodyPaint.color = withAlpha(instrumentColor, 225)
        bodyPaint.textSize = 13 * screenDensity
        bodyPaint.font = .sundialCondensed
        let bodyTop = bounds.top + 38 * density
        let availableBodyHeight = max(bounds.bottom - bodyTop - 9 * density, 1)
        let lineHeight = canvas.fontMetrics(bodyPaint).fontSpacing + 2 * density
        let maxLines = max(Int(availableBodyHeight / lineHeight), 1)
        // StaticLayout: centred, no font padding, 2dp extra line spacing, ellipsized at maxLines.
        // Its width is an Int, so the wrap width is truncated as on Android.
        let layout = canvas.layoutText(value, bodyPaint, width: Double(Int(bounds.width - 38 * density)),
                                       lineSpacingExtra: 2 * density, maxLines: maxLines, alignment: .center)
        var card = Paint()
        card.shader = .radial(center: Point(bounds.centerX, bounds.top), radius: bounds.width * 0.78,
                              colors: [withAlpha(backgroundStyle.haloColor, 224), withAlpha(backgroundStyle.baseColor, 234)],
                              stops: [0, 1])
        canvas.drawRoundRect(bounds, 18 * density, 18 * density, card)
        white.color = withAlpha(backgroundStyle.accentColor, 165)
        white.strokeWidth = density
        canvas.drawRoundRect(bounds, 18 * density, 18 * density, white)

        var titlePaint = text
        titlePaint.color = backgroundStyle.accentColor
        titlePaint.textSize = 17 * screenDensity
        titlePaint.letterSpacing = 0.09
        // Narrow cards (beside the dial on landscape tablets) shrink the title, then shorten it.
        let titleWidth = bounds.width - 24 * density
        while canvas.measureText(title, titlePaint) > titleWidth && titlePaint.textSize > 11 * density {
            titlePaint.textSize -= density
        }
        let fittedTitle = canvas.ellipsize(title, titlePaint, titleWidth)
        canvas.drawText(fittedTitle, bounds.centerX, bounds.top + 23 * density, titlePaint)
        canvas.save()
        canvas.translate(bounds.left + 19 * density, bodyTop)
        canvas.drawTextBlock(layout, 0, 0)
        canvas.restore()
    }

    func splitHoroscope(_ value: String) -> (String, String) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        // Kotlin strings are indexed in UTF-16 code units, so the lengths and split points are too.
        let units = Array(normalized.utf16)
        if units.count < 48 { return (normalized, "Reflect on this guidance as the day unfolds.") }
        let midpoint = units.count / 2
        let sentenceMarks: [UInt16] = [UInt16(UInt8(ascii: ".")), UInt16(UInt8(ascii: "!")), UInt16(UInt8(ascii: "?"))]
        let sentenceBreaks = units.indices.filter { sentenceMarks.contains(units[$0]) }
        let sentenceBreak = sentenceBreaks.min(by: { abs($0 - midpoint) < abs($1 - midpoint) })
            .flatMap { Double(abs($0 - midpoint)) < Double(units.count) * 0.24 ? $0 : nil }
            .map { $0 + 1 }
        // String.lastIndexOf(' ', midpoint): the last space at or before midpoint.
        let wordBreak = units[...midpoint].lastIndex(of: UInt16(UInt8(ascii: " "))).flatMap { $0 > 0 ? $0 : nil } ?? midpoint
        let splitAt = sentenceBreak ?? wordBreak
        return (String(decoding: units[..<splitAt], as: UTF16.self).trimmingCharacters(in: .whitespacesAndNewlines),
                String(decoding: units[splitAt...], as: UTF16.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
