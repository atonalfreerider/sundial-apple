import Foundation

/// The Sundial instrument: a port of the Android app's SundialView, drawn on any Canvas.
///
/// This file holds the state, the public API, the frame driver and the small drawing helpers.
/// The drawing itself is split by area into extensions (Instrument+Sky, +Transition, +Solar,
/// +Earth, +Sun, +Galactic, +Calendar, +Chrome, +Interaction), each porting the matching
/// functions of SundialView.kt with the same names. [layout] fits it to a phone or to a round or
/// rectangular watch. Not thread-safe: use it from the main thread, like an Android view.
public final class Instrument {
    public enum ViewState: Sendable { case heliocentric, geocentric, galactic }

    enum DragMode { case none, year, moon, galaxy, event }

    public let layout: InstrumentLayout
    /// Canvas units per Android dp: 1 when the host draws in iOS points, the screen density when
    /// it draws in pixels (as the Android reference renders do).
    public let density: Double
    /// Android's TextPaint.density alias; the same value.
    var screenDensity: Double { density }
    /// The zone the instrument's civil calendar and clock follow. Android reads
    /// ZoneId.systemDefault() on every access, so a change of the device's zone shows on the next
    /// frame; the auto-updating zone does the same here. Screenshots pin a fixed zone.
    public var zone: TimeZone = .autoupdatingCurrent
    /// The canvas size of the frame being drawn (or last drawn).
    public private(set) var width: Double = 0
    public private(set) var height: Double = 0
    /// Device pixels per canvas unit when the frame began, before any camera transform: Android
    /// draws on a pixel canvas, so its bare pixel literals (hairline floors) go through
    /// devicePixels(_:).
    var pixelsPerUnit = 1.0
    /// True while the Earth camera flight draws: its zoom changes every frame, so rasterised sweep
    /// gradients reuse a cached image instead of rendering one per zoom step (Canvas.fillSweep).
    var cameraInMotion = false

    /// The current time and a monotonic clock in seconds, for animation. Tests replace them.
    public var currentDate: () -> Date = { Date() }
    public var uptime: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

    // MARK: Callbacks (the Android view's listeners)

    public var onCalendarSelectionChanged: ((Set<Int64>) -> Void)?
    public var onControlsChanged: (() -> Void)?
    /// Tapping a horoscope card opens the report sheet for the AI-written reading.
    public var onHoroscopeTapped: (() -> Void)?
    /// Set by a host that opens settings on a long press (the watch app).
    public var onLongPress: (() -> Void)?
    /// The instrument changed and wants a redraw (View.invalidate).
    public var onRedrawRequested: (() -> Void)?

    // MARK: Paints and renderers

    var white = Paint(color: Colors.white, style: .stroke)
    var fill = Paint(color: Colors.white, style: .fill)
    var text: Paint = {
        var p = Paint(color: Colors.white)
        p.textAlign = .center
        p.font = .sundialCondensed
        return p
    }()
    var dimText: Paint = {
        var p = Paint(color: Colors.argb(150, 255, 255, 255))
        p.textAlign = .center
        p.font = .sundialCondensed
        return p
    }()
    /// Curved event titles; they are laid from the arc's start, so left aligned.
    var arcLabel: Paint = {
        var p = Paint()
        p.font = .sundialCondensed
        return p
    }()
    var polygon = Paint(style: .fill)
    var sunRay: Paint = {
        var p = Paint(style: .stroke)
        p.strokeCap = .round
        return p
    }()
    var skyPaint: Paint = {
        var p = Paint()
        p.strokeCap = .round
        return p
    }()
    var constellationPaint = Paint(style: .stroke)
    var symbolPaint = Paint()
    var zodiacGlyphPaint: Paint = {
        var p = Paint()
        p.textAlign = .center
        p.font = .serif
        return p
    }()
    let earthRenderer: EarthSphereRenderer
    let moonRenderer = MoonSphereRenderer()
    let symbols = PlanetSymbols()

    // MARK: The fixed sky

    struct AmbientStar {
        let xFraction: Double
        let yFraction: Double
        let radiusDp: Double
        let alpha: Int
        var flare = false
    }

    /// Distant stars on a unit disc around the dial centre rather than on the screen rectangle, so
    /// the sky still fills the screen when the Earth camera rolls and zooms through it.
    let ambientStars: [AmbientStar] = {
        var random = KotlinRandom(seed: 0x51A7_D1A1)
        return (0..<170).map { index in
            let radius = random.nextFloat().squareRoot()
            // Kotlin's PI.toFloat() rounds to nearest, one ulp above Swift's Float.pi, and its
            // Float cos/sin go through Double (Math.cos): both matter for a bit-exact sky.
            let angle = random.nextFloat() * 2 * Float(Double.pi)
            let big = index % 11 == 0
            let radiusDp = 0.28 + random.nextFloat() * (big ? 1.12 : 0.63)
            let alpha = 30 + Int(random.nextInt(big ? 100 : 64))
            let cosine = Float(cos(Double(angle))), sine = Float(sin(Double(angle)))
            return AmbientStar(xFraction: Double(radius * cosine), yFraction: Double(radius * sine),
                               radiusDp: Double(radiusDp), alpha: alpha, flare: index % 17 == 0)
        }
    }()

    let dustLaneStars: [AmbientStar] = {
        var random = KotlinRandom(seed: 0x0B1_7A5E)
        return (0..<64).map { _ in
            let x = random.nextFloat()
            let y = min(max(0.10 + x * 0.78 + (random.nextFloat() - 0.5) * 0.13, 0.02), 0.98)
            let radiusDp = 0.20 + random.nextFloat() * 0.42
            let alpha = 12 + Int(random.nextInt(34))
            return AmbientStar(xFraction: Double(x), yFraction: Double(y), radiusDp: Double(radiusDp), alpha: alpha)
        }
    }()

    let constellationPaths: [[(Double, Double)]] = [
        [(0.70, 0.075), (0.76, 0.105), (0.82, 0.072), (0.88, 0.128), (0.93, 0.095)],
        [(0.055, 0.76), (0.11, 0.79), (0.15, 0.845), (0.22, 0.82), (0.27, 0.875)],
        [(0.69, 0.84), (0.76, 0.80), (0.82, 0.855), (0.89, 0.82), (0.94, 0.91)],
    ]

    // MARK: State

    var state = ViewState.heliocentric
    var showClock = false
    var north = true
    var realtime = true
    var running = true
    var wallpaperMode = false
    var backgroundStyle: CelestialStyle
    var zodiacProfile: ZodiacProfile
    var horoscopeText: String?
    var selectedInstant: Date
    var dragMode = DragMode.none
    /// Selected calendars in the order they were chosen (a LinkedHashSet on Android).
    var selectedCalendarIds: [Int64] = []
    var occurrences: [CalendarOccurrence] = []
    var lastReportedCalendarYear = 0
    var earthPoint = Point(0, 0)
    var moonPoint = Point(0, 0)
    var sunPoint = Point(0, 0)
    var selectedTimeZoneOffsetMinutes: Int?
    var selectedTimeZoneIsLocal = true
    var transitionFrom: ViewState?
    /// uptime() when the current camera move began, in seconds.
    var transitionStartedAt: TimeInterval = 0
    var transitionEarthPoint = Point(0, 0)
    var transitionCameraRotation = 0.0
    /// Rotation applied by an enclosing camera transform, so rotated labels still read upright.
    var textScreenRotation = 0.0
    var dragStartX = 0.0
    var dragStartY = 0.0
    var dragStarted = false
    var dragStartYear = 0.0
    var galacticTrails: GalacticTrails?
    var inspectedEvent: CalendarOccurrence?
    var inspectedCandidates: [CalendarOccurrence] = []
    var inspectedCandidateIndex = 0
    var eventCycleAnchorX = 0.0
    var eventCycleAnchorY = 0.0
    var horoscopeCards: [Rect] = []
    /// True while drawing on the dial face: Brass Watch engraves it in dark ink, everything else
    /// is light.
    var onFace = true
    var ambient = false
    var ambientBurnIn = false
    var longPressFired = false
    var longPressX = 0.0
    var longPressY = 0.0
    /// When set, the host should call longPressElapsed() at this uptime if the finger is still down.
    public internal(set) var longPressDeadline: TimeInterval?
    /// How soon the host should draw again: nil when nothing moves (paused or a wallpaper).
    public internal(set) var nextRedrawDelay: TimeInterval?
    /// The instrument, in words, for VoiceOver (TalkBack's content description on Android).
    public private(set) var accessibilityDescription = ""

    // Season gradients (SweepGradient on Android), rebuilt when the season or style changes.
    struct SeasonShaderKey: Equatable {
        let year: Int
        let active: Zodiac.Season
        let north: Bool
        let style: CelestialStyle
    }
    var seasonShaderKey: SeasonShaderKey?
    var seasonWashColors: [ARGB] = []
    var seasonBandColors: [ARGB] = []
    var seasonPositions: [Double] = []

    /// Planet helices in ribbon coordinates (x along travel from [baseYear], y to the side). They
    /// only depend on the years in view, so they are built once and slid under the Sun each frame.
    final class GalacticTrails {
        let baseYear: Int
        let endYear: Int
        let pitch: Double
        let paths: [Astronomy.Body: Path]
        init(baseYear: Int, endYear: Int, pitch: Double, paths: [Astronomy.Body: Path]) {
            self.baseYear = baseYear; self.endYear = endYear; self.pitch = pitch; self.paths = paths
        }
    }

    // MARK: Constants (SundialView's companion object)

    static let transitionDuration: TimeInterval = 1.0
    static let localToothRed: ARGB = 0xFFE3_262E
    static let brassEnamelRed: ARGB = 0xFF7A_1E12
    static let galacticStepsPerYear = 180
    /// Short events still get this much arc (about four weeks / three hours) for their title.
    static let minYearLabelDegrees = 28.0
    static let minDayLabelDegrees = 45.0

    // MARK: Init

    /// [earthTexture] is the equirectangular satellite map (earth_texture.png), already scaled
    /// down for a watch if wanted (Android decodes it at half size there).
    public init(layout: InstrumentLayout = .phone, density: Double = 1, earthTexture: PixelImage,
                style: CelestialStyle = .voidBlack, zodiacProfile: ZodiacProfile = ZodiacProfile(),
                horoscope: String? = nil, zone: TimeZone = .autoupdatingCurrent, now: Date = Date()) {
        self.layout = layout
        self.density = density
        self.zone = zone
        backgroundStyle = style
        self.zodiacProfile = zodiacProfile
        horoscopeText = horoscope
        selectedInstant = now
        // A watch globe is small: a smaller render keeps memory and CPU down.
        earthRenderer = EarthSphereRenderer(source: earthTexture,
                                            size: layout.isWatch ? 320 : EarthSphereRenderer.defaultSize)
        lastReportedCalendarYear = displayedYear
    }

    // MARK: Public API

    public var displayedYear: Int { LocalDate.of(selectedInstant, zone).year }
    public var isClockVisible: Bool { showClock }
    public var isGalacticVisible: Bool { state == .galactic }
    public var isSouthernHemisphere: Bool { !north }
    public var isRealtime: Bool { realtime }
    public var viewState: ViewState { state }
    public var instant: Date { selectedInstant }
    public var style: CelestialStyle { backgroundStyle }
    public var earthPointForTest: Point { earthPoint }
    public var sunPointForTest: Point { sunPoint }
    public var inspectedEventTitleForTest: String? { inspectedEvent?.title }

    public func setCalendarOccurrences(_ value: [CalendarOccurrence]) {
        occurrences = value
        invalidate()
    }

    public func resumeClock() { running = true; invalidate() }
    public func pauseClock() { running = false }
    public func setClockVisible(_ value: Bool) { showClock = value; invalidate() }

    public func setGalacticVisible(_ value: Bool) {
        state = value ? .galactic : .heliocentric
        transitionFrom = nil
        onControlsChanged?()
        invalidate()
    }

    /// The host saves the choice; the instrument only draws it.
    public func setBackgroundStyle(_ value: CelestialStyle) {
        backgroundStyle = value
        invalidate()
    }

    /// Freezes the instrument in one moment, style and view for screenshots; nothing is saved.
    public func freezeForCapture(instant: Date, state captureState: ViewState, style: CelestialStyle) {
        pauseClock()
        backgroundStyle = style
        state = captureState
        transitionFrom = nil
        selectedInstant = instant
        invalidate()
    }

    public func setZodiacProfile(_ value: ZodiacProfile, horoscope: String?) {
        zodiacProfile = value
        horoscopeText = horoscope
        invalidate()
    }

    public func setHoroscope(_ value: String?) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        horoscopeText = (trimmed?.isEmpty ?? true) ? nil : trimmed
        invalidate()
    }

    public func setSouthernHemisphere(_ value: Bool) { north = !value; invalidate() }

    public func setSelectedCalendarIds(_ ids: [Int64]) {
        selectedCalendarIds = ids
        invalidate()
    }

    /// Always-on display on a watch: the same instrument, grey and dim on black, without the sky or
    /// the brass face, redrawn only when the host asks (once a minute).
    public func setAmbient(_ value: Bool, burnInProtection: Bool = false) {
        ambientBurnIn = burnInProtection
        guard ambient != value else { return }
        ambient = value
        transitionFrom = nil
        // Android keeps no filtered copies outside always-on (it filters one layer per frame).
        if !value { FilteredImages.removeAll() }
        invalidate()
    }

    /// Renders an instrument view without interactive chrome (Android's wallpaper; widgets here).
    public func drawWallpaper(_ canvas: Canvas, instant: Date, state wallpaperState: ViewState = .heliocentric) {
        state = wallpaperState
        transitionFrom = nil
        selectedInstant = instant
        realtime = false
        running = false
        wallpaperMode = true
        draw(canvas)
    }

    func invalidate() { onRedrawRequested?() }

    // MARK: Frame (onDraw)

    public func draw(_ canvas: Canvas) {
        width = canvas.width
        height = canvas.height
        pixelsPerUnit = canvas.pixelScale > 0 ? canvas.pixelScale : 1
        nextRedrawDelay = nil
        useInk(false)
        if ambient {
            if realtime { selectedInstant = currentDate() }
            canvas.drawColor(Colors.black)
            canvas.save()
            if ambientBurnIn {
                // Wander a few pixels each minute so no OLED pixel stays lit in one place.
                // Instant.epochSecond (floored) / 60 on a Long, which truncates toward zero: before
                // 1970 that is not the floor of the minute.
                let minute = Int(selectedInstant.epochSecond / 60)
                canvas.translate(Double(minute % 5 - 2) * 2 * density, Double((minute / 5) % 5 - 2) * 2 * density)
            }
            let grey = ColorFilterCanvas(canvas, filter: .ambientGrey)
            drawState(grey, state)
            useInk(false)
            drawChrome(grey)
            drawAmbientTime(canvas)
            canvas.restore()
            return
        }
        // Freeze astronomy while a camera flight is active so both views target the same Earth.
        if running && realtime && transitionFrom == nil { selectedInstant = currentDate() }
        if displayedYear != lastReportedCalendarYear && !selectedCalendarIds.isEmpty {
            lastReportedCalendarYear = displayedYear
            onCalendarSelectionChanged?(Set(selectedCalendarIds))
        }
        if transitionFrom != nil && uptime() - transitionStartedAt >= Instrument.transitionDuration { transitionFrom = nil }
        let from = transitionFrom
        let progress = from == nil ? 1.0 : smoothStep(min(max((uptime() - transitionStartedAt) / Instrument.transitionDuration, 0), 1))
        drawBackground(canvas, from, progress)
        if let from {
            useInk(true)
            drawTransition(canvas, from, state, progress)
            nextRedrawDelay = 0
        } else {
            drawState(canvas, state)
        }
        useInk(false)
        if wallpaperMode {
            if zodiacProfile.enabled && !layout.isWatch, let horoscope = horoscopeText {
                drawHoroscopeCard(canvas, horoscope, true)
            }
        } else {
            drawChrome(canvas)
            if let event = inspectedEvent { drawEventInspectionOverlay(canvas, event) }
            updateSpokenDescription()
        }
        if running && !wallpaperMode && nextRedrawDelay == nil { nextRedrawDelay = showClock ? 0.25 : 1.0 }
    }

    /// The instrument is drawn, not built from views, so VoiceOver reads this summary instead. It
    /// changes at most once a minute.
    func updateSpokenDescription() {
        let moment = CivilFormat.format(selectedInstant, "EEEE, MMMM d, yyyy, h:mm a", zone)
        switch state {
        case .heliocentric:
            accessibilityDescription = "Sundial solar view, \(moment). The year dial circles the Sun; " +
                "tap the Sun to fly to the Earth view, or drag the Earth to move through the year."
        case .geocentric:
            accessibilityDescription = "Sundial Earth view, \(moment). The day and lunar dials circle the Earth; " +
                "tap the Earth to return to the solar view, or drag the Moon to move through the month."
        case .galactic:
            accessibilityDescription = "Sundial galactic view, \(moment). The Sun carries the planets through space; " +
                "drag to move through the years, or tap to return."
        }
    }

    func useInk(_ face: Bool) {
        onFace = face
        white.color = instrumentColor
        text.color = instrumentColor
        dimText.color = withAlpha(instrumentColor, 150)
    }

    /// The always-on display drops the brass face, so its engraving would be dark ink on black.
    var instrumentColor: ARGB {
        onFace && !ambient ? backgroundStyle.instrumentColor : backgroundStyle.chromeColor
    }

    var brass: Bool { backgroundStyle.brassFace }

    func drawState(_ canvas: Canvas, _ requestedState: ViewState) {
        // The galactic view has no dial face under it.
        useInk(requestedState != .galactic)
        switch requestedState {
        case .heliocentric: drawHeliocentric(canvas)
        case .geocentric: drawGeocentric(canvas)
        case .galactic: drawGalactic(canvas)
        }
    }

    // MARK: Layout

    /// Centre x, centre y and radius of the annual dial.
    func geometry() -> (cx: Double, cy: Double, r: Double) {
        switch layout {
        case .phone:
            return (width / 2, height * (height > width * 1.25 ? 0.47 : 0.5), min(width * 0.47, height * 0.41))
        // The annual dial and its season band fill a round watch; the Earth view's Sun sits on the rim.
        case .watchRound:
            return (width / 2, height / 2, min(width, height) * 0.43)
        // A rectangular watch keeps a strip below the dial for the time.
        case .watchRect:
            return (width / 2, height * (height > width * 1.08 ? 0.45 : 0.5), min(width * 0.43, height * 0.40))
        }
    }

    public var dialGeometry: (cx: Double, cy: Double, r: Double) { geometry() }

    /// On a watch the instrument is small, so labels keep a readable minimum size.
    func label(_ scaled: Double, _ watchMinimumDp: Double) -> Double {
        layout.isWatch ? max(scaled, watchMinimumDp * density) : scaled
    }

    /// Touch targets on a watch are at least a fingertip wide.
    func reach(_ scaled: Double, _ watchMinimumDp: Double) -> Double {
        layout.isWatch ? max(scaled, watchMinimumDp * density) : scaled
    }

    // MARK: Angles

    func annualAngle(_ fraction: Double) -> Double { DialGeometry.annualAngle(fraction, north) }
    /// Heliocentric longitude → canvas angle, sharing the annual dial's frame.
    func eclipticAngle(_ longitudeDegrees: Double) -> Double { DialGeometry.eclipticAngle(longitudeDegrees, north) }
    func zodiacAngle(_ longitudeDegrees: Double) -> Double { eclipticAngle(longitudeDegrees) }
    func hourAngle(_ hours: Double) -> Double { DialGeometry.hourAngle(hours, north) }
    func currentEarthAngle() -> Double {
        annualAngle(Astronomy.civilYearFraction(ZonedDateTime(selectedInstant, zone)))
    }

    // MARK: Helpers

    func point(_ cx: Double, _ cy: Double, _ radius: Double, _ angleDegrees: Double) -> Point {
        let a = angleDegrees * .pi / 180
        return Point(cx + cos(a) * radius, cy + sin(a) * radius)
    }

    func lerp(_ start: Double, _ end: Double, _ progress: Double) -> Double { start + (end - start) * progress }

    /// A length Android gives in bare view pixels (such as `maxOf(.5f, r * .0015f)`), in canvas
    /// units: the same in the pixel-based reference renders, a fraction of a point on an iOS host
    /// that draws in points.
    func devicePixels(_ pixels: Double) -> Double { pixels / pixelsPerUnit }

    func distance(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double { hypot(x1 - x2, y1 - y2) }

    func withAlpha(_ color: ARGB, _ alpha: Int) -> ARGB {
        Colors.argb(alpha, Colors.red(color), Colors.green(color), Colors.blue(color))
    }

    /// Kotlin's Float.toInt() truncates toward zero, as Int(_:) does.
    func blendArgb(_ start: ARGB, _ end: ARGB, _ progress: Double) -> ARGB {
        Colors.argb(
            Int(lerp(Double(Colors.alpha(start)), Double(Colors.alpha(end)), progress)),
            Int(lerp(Double(Colors.red(start)), Double(Colors.red(end)), progress)),
            Int(lerp(Double(Colors.green(start)), Double(Colors.green(end)), progress)),
            Int(lerp(Double(Colors.blue(start)), Double(Colors.blue(end)), progress)))
    }

    func blendColor(_ start: ARGB, _ end: ARGB, _ progress: Double) -> ARGB {
        Colors.rgb(
            Int(lerp(Double(Colors.red(start)), Double(Colors.red(end)), progress)),
            Int(lerp(Double(Colors.green(start)), Double(Colors.green(end)), progress)),
            Int(lerp(Double(Colors.blue(start)), Double(Colors.blue(end)), progress)))
    }

    func withTextScreenRotation(_ rotation: Double, _ block: () -> Void) {
        let previous = textScreenRotation
        textScreenRotation = previous + rotation
        defer { textScreenRotation = previous }
        block()
    }

    func drawRadialLine(_ canvas: Canvas, _ cx: Double, _ cy: Double, _ inner: Double, _ outer: Double,
                        _ angleDegrees: Double, _ paint: Paint) {
        let a = angleDegrees * .pi / 180
        canvas.drawLine(cx + cos(a) * inner, cy + sin(a) * inner, cx + cos(a) * outer, cy + sin(a) * outer, paint)
    }

    func drawDialTriangle(_ canvas: Canvas, _ cx: Double, _ cy: Double, _ height: Double, _ angleDegrees: Double,
                          _ halfBase: Double, _ color: ARGB) {
        let tip = point(cx, cy, height, angleDegrees)
        let perpendicular = (angleDegrees + 90) * .pi / 180
        let dx = cos(perpendicular) * halfBase
        let dy = sin(perpendicular) * halfBase
        polygon.color = color
        var path = Path()
        path.moveTo(cx - dx, cy - dy)
        path.lineTo(tip.x, tip.y)
        path.lineTo(cx + dx, cy + dy)
        path.close()
        canvas.drawPath(path, polygon)
    }

    /// A dial hand whose base begins outside a central body rather than showing through it.
    func drawAnnularPointer(_ canvas: Canvas, _ cx: Double, _ cy: Double, _ innerRadius: Double, _ outerRadius: Double,
                            _ angleDegrees: Double, _ halfBase: Double, _ color: ARGB) {
        guard outerRadius > innerRadius else { return }
        let base = point(cx, cy, innerRadius, angleDegrees)
        let tip = point(cx, cy, outerRadius, angleDegrees)
        let perpendicular = (angleDegrees + 90) * .pi / 180
        let dx = cos(perpendicular) * halfBase
        let dy = sin(perpendicular) * halfBase
        polygon.color = color
        var path = Path()
        path.moveTo(base.x - dx, base.y - dy)
        path.lineTo(tip.x, tip.y)
        path.lineTo(base.x + dx, base.y + dy)
        path.close()
        canvas.drawPath(path, polygon)
    }

    func drawSprocketTooth(_ canvas: Canvas, _ cx: Double, _ cy: Double, _ baseRadius: Double, _ tipRadius: Double,
                           _ angleDegrees: Double, _ baseHalfWidth: Double, _ tipHalfWidth: Double, _ paint: Paint) {
        let base = point(cx, cy, baseRadius, angleDegrees)
        let tip = point(cx, cy, tipRadius, angleDegrees)
        let perpendicular = (angleDegrees + 90) * .pi / 180
        let px = cos(perpendicular)
        let py = sin(perpendicular)
        var path = Path()
        path.moveTo(base.x - px * baseHalfWidth, base.y - py * baseHalfWidth)
        path.lineTo(tip.x - px * tipHalfWidth, tip.y - py * tipHalfWidth)
        path.lineTo(tip.x + px * tipHalfWidth, tip.y + py * tipHalfWidth)
        path.lineTo(base.x + px * baseHalfWidth, base.y + py * baseHalfWidth)
        path.close()
        canvas.drawPath(path, paint)
    }

    func drawRotatedText(_ canvas: Canvas, _ value: String, _ cx: Double, _ cy: Double, _ radius: Double,
                         _ angleDegrees: Double, _ paint: Paint, _ upright: Bool) {
        let p = point(cx, cy, radius, angleDegrees)
        canvas.save()
        canvas.rotate(angleDegrees + 90, p.x, p.y)
        // Flip by where the label ends up on screen, including any camera rotation around it.
        let screenAngle = Astronomy.normalizeDegrees(angleDegrees + textScreenRotation)
        if upright && screenAngle > 0 && screenAngle < 180 { canvas.rotate(180, p.x, p.y) }
        let metrics = canvas.fontMetrics(paint)
        canvas.drawText(value, p.x, p.y - (metrics.ascent + metrics.descent) / 2, paint)
        canvas.restore()
    }
}
