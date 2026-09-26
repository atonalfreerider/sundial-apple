# Porting Sundial from Android to Swift

The Swift code is a faithful port of the Android app in `../sundial-android-native`. Port
behaviour exactly — every constant, angle, alpha, colour and branch — so the instrument looks
and behaves the same. Improve nothing while porting; note anything that looks wrong instead.

## Building on Linux

```bash
export PATH=~/swift/swift-6.4.0-RELEASE-ubuntu26.04/usr/bin:$PATH
swift build                       # the package (SundialCoreGraphics compiles to nothing here)
swift test                        # XCTest suites
swiftc -parse path/to/File.swift  # syntax only, for files that cannot build yet
```

SundialCoreGraphics and the apps in `Apps/` need Apple SDKs and cannot compile on Linux; write
them against the documented Apple APIs and syntax-check them with `swiftc -parse`.

## Conventions

- **Names follow the Kotlin.** Types, functions and properties keep their Kotlin names, so a call
  in one file finds its definition in another. Kotlin `object`s become `public enum` namespaces
  with `static` members. SCREAMING_CASE constants become lowerCamelCase
  (`EARTH_ORBIT` → `earthOrbit`, `LOCAL_WHEEL_RED_TOOTH` → `localWheelRedTooth`).
- **Enum cases are lowerCamelCase**: `Astronomy.Body.mercury`, `Zodiac.Sign.aries`,
  `Zodiac.Season.spring`, `CelestialStyle.voidBlack`, `InstrumentLayout.watchRound`,
  `Instrument.ViewState.geocentric`. Enums that Kotlin iterates or indexes are `Int`-backed and
  `CaseIterable` in declaration order: `Sign.entries` → `Sign.allCases`, `sign.ordinal` →
  `sign.ordinal` (declare `public var ordinal: Int { rawValue }`).
- **Parameters.** A Kotlin parameter without a default becomes unlabelled (`_`); one with a
  default keeps its Kotlin name as the label. So `annualAngle(fraction, north)` is
  `DialGeometry.annualAngle(fraction, north)` and
  `yearEventBand(r, index, minThickness = t)` is `DialGeometry.yearEventBand(r, index, minThickness: t)`.
  Kotlin calls that name non-default arguments pass them positionally in Swift.
- **Data classes** become `public struct`s (`Equatable`, `Hashable` when used as keys); Kotlin
  `Pair`s of coordinates become `Point` or a tuple; `Triple` becomes a labelled tuple.
- **Comments** carry over (KDoc to `///`), adjusted only where the platform differs.
- Everything used across modules is `public`.

## Types

| Kotlin / Android | Swift |
|---|---|
| `Float` (geometry) | `Double` |
| `Int` colour, `0xFF123456.toInt()` | `ARGB` (`UInt32`), `0xFF12_3456` |
| `Color.argb/rgb/alpha/red…` | `Colors.argb/rgb/alpha/red…` |
| `Long` ids | `Int64` |
| `Instant` | `Date` |
| `Instant.now()` | `currentDate()` (Instrument) or a `now: Date` parameter |
| `SystemClock.uptimeMillis()` | `uptime()` (seconds, Instrument) |
| `ZoneId` / `ZoneOffset.ofTotalSeconds(s)` | `TimeZone` / `TimeZone.offset(seconds: s)` |
| `LocalDate`, `LocalTime` | `LocalDate`, `LocalTime` (Sources/SundialCore/CivilTime.swift) |
| `ZonedDateTime`, `instant.atZone(z)` | `ZonedDateTime(instant, z)` |
| `zdt.toLocalDate()` | `zdt.date` |
| `date.dayOfMonth`, `monthValue` | `date.day`, `date.month` |
| `date.dayOfWeek == SUNDAY` | `date.dayOfWeek == 7` (ISO, Monday 1) |
| `date.month.name.take(3)` | `date.monthAbbreviation` (`"JAN"`) |
| `dayOfWeek.name.take(3)` | `date.weekdayAbbreviation` (`"MON"`) |
| `date.atStartOfDay(zone)` | `date.atStartOfDay(zone)` (a `Date`) |
| `instant.atOffset(ZoneOffset.ofHours(12)).toLocalDate()` | `LocalDate.of(instant, .offset(seconds: 43_200))` |
| `DateTimeFormatter.ofPattern(p)` + `format` | `CivilFormat.format(instant, p, zone)` |
| `Duration.between(a, b).seconds` | `Int64(b.timeIntervalSince(a))` (truncates like Kotlin) |
| `plusSeconds / plusMillis / plusNanos` | `addingTimeInterval(seconds)` |
| `RectF(l, t, r, b)` | `Rect(l, t, r, b)` |
| `Path()` | `var path = Path()` (a struct) |
| `Paint(Paint.ANTI_ALIAS_FLAG).apply { … }` | `var p = Paint(); p.… = …` |
| `Paint(text).apply { … }` (a copy) | `var p = text; p.… = …` |
| `android.graphics.Bitmap` | `PixelImage` |

### Canvas and Paint (Sources/SundialRender/Canvas.swift)

Canvas methods keep Android's argument order: `canvas.drawCircle(cx, cy, r, paint)`,
`drawLine`, `drawArc(oval, start, sweep, useCenter, paint)`, `drawRoundRect(rect, rx, ry, paint)`,
`drawOval`, `drawRect`, `drawPath`, `drawText(text, x, y, paint)`, `save`, `restore`,
`restore(toCount:)`, `rotate(deg)` / `rotate(deg, px, py)`, `scale(sx, sy)` /
`scale(sx, sy, px, py)`, `translate`, `concat(AffineTransform)`, `clip(path)`, `drawColor`.

| Android | Swift |
|---|---|
| `canvas.saveLayerAlpha(…, a255)` | `canvas.saveLayer(alpha: Double(a255) / 255)` |
| `canvas.saveLayer(null, ambientPaint)` (ColorMatrix) | draw through `ColorFilterCanvas(canvas, filter: .ambientGrey)` |
| `canvas.drawBitmap(b, null, rect, paint)` | `canvas.drawImage(image, rect, alpha: 1)` |
| `Matrix.setValues([sx,kx,tx, ky,sy,ty, 0,0,1])` + `concat` | `canvas.concat(AffineTransform(a: sx, b: ky, c: kx, d: sy, tx: tx, ty: ty))` |
| `paint.ascent()`, `descent()`, `fontSpacing` | `canvas.fontMetrics(paint).ascent` / `.descent` / `.fontSpacing` |
| `paint.measureText(s)` | `canvas.measureText(s, paint)` |
| `setShadowLayer(r, dx, dy, c)` / `clearShadowLayer()` | `paint.shadow = Shadow(radius: r, dx: dx, dy: dy, color: c)` / `paint.shadow = nil` |
| `RadialGradient(x, y, r, colors, stops, CLAMP)` | `paint.shader = .radial(center: Point(x, y), radius: r, colors: [...], stops: [...])` |
| `LinearGradient(...)` | `.linear(start:end:colors:stops:)` |
| `SweepGradient(cx, cy, colors, positions)` on a circle | `canvas.fillSweep(center:innerRadius:outerRadius:colors:positions:)` (a filled disc has inner radius 0; a stroked ring spans radius ± strokeWidth/2) |
| `DashPathEffect([on, off], 0)` | `paint.dash = [on, off]` |
| `Paint.Style.FILL / STROKE`, `Cap.ROUND` … | `.fill / .stroke`, `.round` … |
| `typeface = resources.getFont(R.font.sundial_condensed)` / `labelFont` | `font = .sundialCondensed` |
| `Typeface.create(Typeface.SERIF, …)` | `font = .serif` |
| `TextUtils.ellipsize(s, paint, w, END)` | `canvas.ellipsize(s, paint, w)` |
| `StaticLayout` (wrapped, centred, maxLines, ellipsized) | `canvas.layoutText(…)` then `canvas.drawTextBlock(…)` |
| `canvas.drawTextOnPath(label, arcPath, 0, vOffset, paint)` on an arc | `canvas.drawTextOnArc(…)` |

The text helpers are in Sources/SundialRender/TextLayout.swift:

```swift
public struct TextBlock {                       // a laid-out StaticLayout
    public enum Alignment { case left, center, right }
    public let lines: [String]
    public let paint: Paint
    public let width: Double                     // the wrap width
    public let lineHeight: Double                // fontSpacing + lineSpacingExtra
    public let alignment: Alignment
    public var height: Double { … }              // lines.count * lineHeight − lineSpacingExtra
}
extension Canvas {
    func ellipsize(_ text: String, _ paint: Paint, _ availableWidth: Double) -> String
    func layoutText(_ text: String, _ paint: Paint, width: Double, lineSpacingExtra: Double = 0,
                    maxLines: Int = .max, alignment: TextBlock.Alignment = .center) -> TextBlock
    /// Draws the block with its top-left at (x, y), as StaticLayout.draw after translate(x, y).
    func drawTextBlock(_ block: TextBlock, _ x: Double, _ y: Double)
    /// drawTextOnPath along a circle of [radius] about (cx, cy), starting at [startAngle] and
    /// running clockwise on screen when [clockwise] (the direction the Kotlin arc path was added
    /// in). Like Android, a positive [vOffset] moves the text to the right of the direction of
    /// travel (inward on a clockwise arc).
    func drawTextOnArc(_ text: String, cx: Double, cy: Double, radius: Double, startAngle: Double,
                       clockwise: Bool, vOffset: Double, _ paint: Paint)
}
```

### Kotlin semantics to keep

- `Int / Int` and `%` truncate in both languages. `Double % Double` is
  `a.truncatingRemainder(dividingBy: b)`. `floorMod` / `floorDiv` need explicit floor
  arithmetic.
- `Float.toInt()` / `Double.toInt()` truncate toward zero: `Int(x)`. `roundToInt()` and
  `Math.round` round half up: `Int((x + 0.5).rounded(.down))`. `.coerceIn(a, b)` is
  `min(max(x, a), b)`.
- `minBy`, `sortedBy`, `firstOrNull`, `lastOrNull`, `associateWith` have direct Swift forms;
  `sortedBy` is stable, and so is Swift's `sorted(by:)`.
- `(a..b)` is `a...b`; `until` is `..<`; `step` is `stride`.

## Where things go

### SundialCore (Foundation only)

Already written: `CivilTime.swift` (LocalDate, LocalTime, ZonedDateTime, CivilFormat),
`Colors.swift` (ARGB). To port, one Swift file per Kotlin file, same name:

| Kotlin | Swift API (examples) |
|---|---|
| astronomy/Astronomy.kt | `Astronomy.Body`, `Astronomy.Vector3`, `heliocentricPosition(_ body, _ instant)`, `civilYearFraction(_ dateTime: ZonedDateTime)`, `instantAtYearFraction(_ year, _ fraction, _ zone)`, `synodicMonthDays` |
| astronomy/Zodiac.kt | `Zodiac.Sign` (`displayName`, `symbol`, `element`, `startMonth`, `startDay`), `Zodiac.Season`, `signFor(_ date: LocalDate)`, `seasonFor(_ date, _ northernHemisphere)`, `geocentricLongitude(_ body, _ instant)` |
| calendar/CalendarModels.kt | `DeviceCalendar`, `RawCalendarInstance`, `CalendarOccurrence` (`start`/`endExclusive: ZonedDateTime`), `CalendarNormalizer.normalize(_ raw, _ displayZone)` |
| calendar/CalendarIntervals.kt | `DaySegment`, `YearSegment`, `CalendarIntervals.inDay(_ event, _ day, _ zone)`, `inYear(_ event, _ year, _ zone)` |
| ui/DialGeometry.kt | `DialGeometry.earthOrbit`, `annualAngle(_ fraction, _ north)`, `EventBand`, `yearEventBand(_ annualRadius, _ calendarIndex, minThickness:)`, `EarthFlightFrame`, `earthFlightFrame(_ progress)` |
| ui/SeasonBands.kt | `SeasonBands.starts(_ year) -> [(Double, Zodiac.Season)]`, `Mix`, `mixAt(_ fraction, _ starts, _ daysInYear)` |
| ui/TimeZoneDial.kt | `TimeZoneDial.Spoke`, `spokes(_ instant, north:)`, `datelineHours(_ instant)`, `localOffsetMinutes(_ instant, _ zone)`, `angleForOffsetMinutes(_ instant, _ offsetMinutes, north:)`, `localName(_ zone, _ instant)`, `commonName(_ offsetHours)`, `nearestSpoke(_ spokes, _ angleDegrees)` |
| ui/GalacticGeometry.kt | `GalacticGeometry.travelX/travelY/sideX/sideY`, `yearPitch`, `minYear`, `maxYear`, `continuousYear(_ instant, _ zone)`, `instantAt(_ continuousYear, _ zone)`, `monthStart(_ year, _ month)`, `orbitOffset(_ longitudeDegrees, _ orbitRadius) -> (Double, Double)` |
| ui/EarthOrientation.kt | `EarthOrientation.obliquityDegrees`, `projectedGeographicPole(_ north, _ sunLongitudeDegrees) -> (Double, Double)`, `screenToEquatorial(…)` |
| ui/CalendarHitTesting.kt | `CalendarHitTesting.containsYearFraction(…)`, `containsMinute(…)` |
| ui/CelestialStyle.kt | `CelestialStyle` (`displayName`, colours as ARGB, `brassFace`), `CaseIterable`; its preferences move to SettingsStore |
| ui/ZodiacPreferences.kt | `ZodiacProfile`; the preferences part moves to SettingsStore |
| ui/InstrumentLayout.kt | `InstrumentLayout` (`phone`, `watchRound`, `watchRect`, `isWatch`) |
| app …/BirthDateInput.kt, BirthTimeInput.kt | the parsing and formatting logic, UI-free |
| app …/horoscope/HoroscopeGenerator.kt | prompt building and output clean-up, model-free (the apps call Apple's on-device model) |
| app …/horoscope/ReadingReporter.kt | the report form body, network-free |
| SharedPreferences (CelestialStylePreferences, ZodiacPreferences, WatchPreferences) | `SettingsStore` on `UserDefaults` (an App Group suite in the apps) |

### SundialRender

| File | Ports |
|---|---|
| `Canvas.swift`, `KotlinRandom.swift`, `Instrument.swift` | written: the API, the seeded Random, the instrument's state, public API, frame driver (`onDraw`) and helpers (`geometry`, `label`, `reach`, `useInk`, `point`, `withAlpha`, `blendArgb`, `blendColor`, `annualAngle`, `eclipticAngle`, `zodiacAngle`, `hourAngle`, `currentEarthAngle`, `drawRadialLine`, `drawDialTriangle`, `drawAnnularPointer`, `drawSprocketTooth`, `drawRotatedText`, `withTextScreenRotation`) |
| `Instrument+Sky.swift` | `drawBackground`, `skyCamera`, `drawAmbientStars` |
| `Instrument+Transition.swift` | `isEarthFlight`, `earthCameraRotation`, `drawTransition`, `drawEarthCameraFlight`, `drawTransformedState`, `smoothStep`, `switchToState` |
| `Instrument+Solar.swift` | `drawHeliocentric` through `drawPlanetGlyph`: annual backdrop, Earth spike, heliocentric foreground, season shaders/shading/ring, zodiac ring/sector/glyph, zodiac hands, sign marker, annual dial/scale/day tick/year marker, season cross, dial face, orbit paths/trail/orbit, planet marker/glyph, Earth subdial and its parts, `subdialMoonPoint`, `orbitRatio`, `displayedSeason` |
| `Instrument+Earth.swift` | `drawGeocentric`, `drawHourSprocket`, `drawLunarDial`, `drawLocalWheel`, `selectedTimeZoneOffset`, `drawSelectedZoneCaption`, `drawEarthSeal`, `drawEarthSealRim`, `drawMoonGlyph`, `drawByzantineMoonSeal` |
| `Instrument+Sun.swift` | `drawSun`, `drawBrassSun`, `drawSunBloom`, `drawByzantineSunSeal` |
| `Instrument+Galactic.swift` | `drawGalactic`, `drawGalacticYearTicks`, `galacticOrbit`, `galacticTrails`, `DashedPathBuilder`, `drawGalacticTrails`, `drawDirectionArrow`, `drawOrthonormalPlane`, `drawGalacticEvents` |
| `Instrument+Calendar.swift` | `yearEventLabelSize`, `dayEventLabelSize`, `yearBand`, `dayBand`, `drawCalendarYearEvents`, `drawCalendarDayEvents`, `drawArcLabel`, `calendarIndex`, `drawEventInspectionOverlay`, `eventTimingLabel`, `calendarEventsAt`, `beginEventInspection`, `updateEventInspection`; plus `yearEventBandForTest` |
| `Instrument+Chrome.swift` | `drawChrome`, `drawWatchChrome`, `drawAmbientTime`, `watchNowPill`, `drawHoroscopeCard`, `drawHoroscopePanel`, `splitHoroscope` |
| `Instrument+Interaction.swift` | touch handling as `pointerDown/pointerMove/pointerUp/pointerCancel(x:y:)`, the long press (`armLongPress` sets `longPressDeadline`; the host calls `longPressElapsed()`), `finishInteraction`, `scrubBy`, `updateYearDrag`, `updateMoonDrag`, `updateGalacticDrag`, `resetNow` |
| `EarthSphereRenderer.swift`, `MoonSphereRenderer.swift`, `PlanetSymbols.swift` | the Kotlin classes, rendering into `PixelImage` / onto `Canvas` |
| `ColorFilterCanvas.swift` | a Canvas that forwards to another, passing every colour (paints, shaders, shadows, drawColor, image pixels) through a `ColorFilter`; `ColorFilter.ambientGrey` is Android's `ColorMatrix().setSaturation(0)` then `setScale(.55, .55, .55, 1)` |
| `TextLayout.swift` | the text helpers above |

`WatchFaceLayer` (the Wear OS watch face's asset export) is not ported: Apple has no custom
watch faces. `drawWatchFaceLayer` is left out.

`invalidate()` asks the host for a redraw; `postInvalidateOnAnimation` is `nextRedrawDelay = 0`.
Android's `parent?.requestDisallowInterceptTouchEvent`, `performClick` and haptics have no
equivalent inside the instrument: drop them (the host handles gestures and haptics).

### SundialCoreGraphics and SundialSVG

`CGCanvas` implements Canvas on a `CGContext` (y down, as UIKit and SwiftUI provide it) with
Core Text for text; wrap the whole file in `#if canImport(CoreGraphics)`. `SVGCanvas` writes
SVG, embeds images as PNG, and measures text with the bundled TTF's own metrics, so Linux renders
match the phone; `sundial-render` renders scenes with it for previews and comparisons.
