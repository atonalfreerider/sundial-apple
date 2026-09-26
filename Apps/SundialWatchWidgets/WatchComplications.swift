// The watchOS complications: Sundial's replacement for the Wear OS watch face (watchface/). Apple
// has no custom watch faces, so the instrument comes to any face as WidgetKit complications,
// drawn with SwiftUI shapes from SundialCore's DialGeometry rather than rendered as images:
//
//   accessoryCircular     the year dial: the season band with today's season lit, the dotted
//                         season cross, the month ticks, the Earth on its orbit around the Sun
//                         and today's marker on the rim
//   accessoryCorner       the Moon's phase, with the season as the curved label
//   accessoryRectangular  a small instrument summary: the year dial beside the season, the
//                         Moon's phase and the Sun's sign (the date when astrology is off)
//   accessoryInline       the same in words
//
// Settings (aesthetic, hemisphere, astrology) come from the App Group the watch app writes through
// SundialCore's SettingsStore; the watch app reloads these timelines when they change. Timelines
// hold an entry every quarter hour, as the Android watch face and wallpaper redrew. On tinted faces
// the Sun, the Earth, today's marker, the lit season and the Moon's light take the face's accent
// colour (widgetAccentable). Nothing here uses UIKit.

import SundialCore
import SundialCoreGraphics
import SwiftUI
import WidgetKit

// MARK: - Bundle

@main
struct SundialWatchWidgets: WidgetBundle {
    var body: some Widget {
        SundialYearDialComplication()
        SundialMoonComplication()
        SundialSummaryComplication()
        SundialInlineComplication()
    }
}

/// The complication kinds, for WidgetCenter.reloadTimelines(ofKind:).
enum SundialComplicationKind {
    static let yearDial = "SundialYearDial"
    static let moon = "SundialMoon"
    static let summary = "SundialSummary"
    static let inline = "SundialInline"
}

struct SundialYearDialComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SundialComplicationKind.yearDial, provider: SundialComplicationProvider()) { entry in
            ComplicationYearDialView(entry: entry)
        }
        .configurationDisplayName("Year Dial")
        .description("The Earth on its orbit around the Sun, with today's season lit.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct SundialMoonComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SundialComplicationKind.moon, provider: SundialComplicationProvider()) { entry in
            ComplicationMoonCornerView(entry: entry)
        }
        .configurationDisplayName("Moon and Season")
        .description("The Moon's phase, with the season along the corner.")
        .supportedFamilies([.accessoryCorner])
    }
}

struct SundialSummaryComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SundialComplicationKind.summary, provider: SundialComplicationProvider()) { entry in
            ComplicationSummaryView(entry: entry)
        }
        .configurationDisplayName("Instrument")
        .description("The year dial, the season, the Moon's phase and the Sun's sign.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct SundialInlineComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SundialComplicationKind.inline, provider: SundialComplicationProvider()) { entry in
            ComplicationInlineView(entry: entry)
        }
        .configurationDisplayName("Season and Moon")
        .description("The season and the Moon's phase in words.")
        .supportedFamilies([.accessoryInline])
    }
}

// MARK: - Timeline

struct SundialComplicationEntry: TimelineEntry {
    let date: Date
    let settings: ComplicationSettings
}

struct SundialComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> SundialComplicationEntry {
        SundialComplicationEntry(date: Date(), settings: .fallback)
    }

    func getSnapshot(in context: Context, completion: @escaping (SundialComplicationEntry) -> Void) {
        completion(SundialComplicationEntry(date: Date(), settings: ComplicationSettings.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SundialComplicationEntry>) -> Void) {
        let settings = ComplicationSettings.load()
        let entries = ComplicationSchedule.quarterHours(from: Date(), hours: 4).map { date in
            SundialComplicationEntry(date: date, settings: settings)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

enum ComplicationSchedule {
    /// The Android watch face and wallpaper redraw every 15 minutes.
    static let interval: TimeInterval = 15 * 60

    /// [now], then every quarter hour on the clock (:00, :15, :30, :45) for [hours] hours.
    static func quarterHours(from now: Date, hours: Double) -> [Date] {
        let start = now.timeIntervalSince1970
        let end = start + hours * 3_600
        var dates = [now]
        var next = ((start / interval).rounded(.down) + 1) * interval
        while next <= end {
            dates.append(Date(timeIntervalSince1970: next))
            next += interval
        }
        return dates
    }
}

// MARK: - Settings

/// The settings a complication draws with, read once per timeline from the App Group.
struct ComplicationSettings {
    let style: CelestialStyle
    /// WatchPreferences' southern hemisphere switch, inverted.
    let north: Bool
    /// The astrology opt-in (ZodiacPreferences): the Sun's sign is shown only when it is on.
    let astrology: Bool

    /// SettingsStore's defaults, for placeholders.
    static let fallback = ComplicationSettings(style: .voidBlack, north: true, astrology: false)

    static func load() -> ComplicationSettings {
        // The App Group the watch app writes (Shared/SundialResources.swift).
        let store = SundialResources.settings()
        return ComplicationSettings(style: store.celestialStyle.get(),
                                    north: !store.watch.southern(),
                                    astrology: store.zodiac.get().enabled)
    }
}

// MARK: - The sky at an entry's date

/// Everything the complications show, for one moment and hemisphere.
struct ComplicationSky {
    /// One season's stretch of the annual dial, from its start to the next season's.
    struct SeasonArc: Identifiable {
        let id: Int
        let start: Double
        let end: Double
        /// The season's northern name, which picks its colour as on the instrument's season band.
        let northernSeason: Zodiac.Season
        /// Today falls in it.
        let lit: Bool
    }

    let date: Date
    let zone: TimeZone
    let north: Bool
    /// Where the Earth is on the annual dial: the fraction of the civil year gone.
    let yearFraction: Double
    /// The year fractions at which each month begins.
    let monthStarts: [Double]
    let seasonArcs: [SeasonArc]
    /// Today's season as the chosen hemisphere names it.
    let season: Zodiac.Season
    /// The Sun's sign today (the sign the instrument's zodiac ring lights).
    let sunSign: Zodiac.Sign
    /// The Moon–Sun elongation in degrees: 0 new, 90 first quarter, 180 full, 270 last quarter.
    let moonPhase: Double

    init(_ date: Date, north: Bool, zone: TimeZone = .current) {
        self.date = date
        self.zone = zone
        self.north = north
        let local = ZonedDateTime(date, zone)
        let year = local.year
        let days = Double(Astronomy.daysInYear(year))
        yearFraction = Astronomy.civilYearFraction(local)
        monthStarts = (1...12).map { month in Double(LocalDate(year, month, 1).dayOfYear - 1) / days }
        let starts = SeasonBands.starts(year)
        let northernToday = Zodiac.seasonFor(local.date, true)
        seasonArcs = starts.indices.map { index in
            // Winter runs on past New Year to the next spring.
            let end = index + 1 < starts.count ? starts[index + 1].0 : starts[0].0 + 1
            return SeasonArc(id: index, start: starts[index].0, end: end,
                             northernSeason: starts[index].1, lit: starts[index].1 == northernToday)
        }
        season = Zodiac.seasonFor(local.date, north)
        sunSign = Zodiac.signFor(local.date)
        moonPhase = Astronomy.moonPhaseDegrees(date)
    }

    /// The Moon's phase among the eight named phases: 0 new, 2 first quarter, 4 full, 6 last quarter.
    var moonPhaseIndex: Int { Int((moonPhase + 22.5) / 45) % 8 }

    /// The lit fraction of the Moon's disc, 0 to 1.
    var moonIllumination: Double { (1 - cos(moonPhase * Double.pi / 180)) / 2 }

    /// The SF Symbol that looks like tonight's Moon. The symbols are drawn as the northern
    /// hemisphere sees the Moon; the southern sky shows it mirrored, which is the opposite phase's
    /// symbol (a southern waxing crescent looks like a northern waning one).
    var moonSymbolName: String {
        let names = ["moonphase.new.moon", "moonphase.waxing.crescent", "moonphase.first.quarter",
                     "moonphase.waxing.gibbous", "moonphase.full.moon", "moonphase.waning.gibbous",
                     "moonphase.last.quarter", "moonphase.waning.crescent"]
        return names[north ? moonPhaseIndex : (8 - moonPhaseIndex) % 8]
    }
}

// MARK: - Words

enum ComplicationText {
    /// Kotlin's Season.name, as the instrument's season band prints it.
    static func season(_ season: Zodiac.Season) -> String {
        switch season {
        case .spring: return "SPRING"
        case .summer: return "SUMMER"
        case .fall: return "FALL"
        case .winter: return "WINTER"
        }
    }

    static func moonPhase(_ sky: ComplicationSky) -> String {
        ["NEW MOON", "WAXING CRESCENT", "FIRST QUARTER", "WAXING GIBBOUS",
         "FULL MOON", "WANING GIBBOUS", "LAST QUARTER", "WANING CRESCENT"][sky.moonPhaseIndex]
    }

    static func illumination(_ sky: ComplicationSky) -> String {
        "\(Int((sky.moonIllumination * 100).rounded()))%"
    }

    /// The sign as the horoscope card titles it: glyph, then name in capitals.
    static func sign(_ sign: Zodiac.Sign) -> String {
        "\(sign.symbol) \(sign.displayName.uppercased())"
    }

    /// "SAT 26 SEP", in the instrument's capitals.
    static func day(_ sky: ComplicationSky) -> String {
        CivilFormat.format(sky.date, "EEE d MMM", sky.zone).uppercased()
    }

    /// What VoiceOver reads for the dial.
    static func spokenDial(_ sky: ComplicationSky) -> String {
        "Sundial year dial. \(season(sky.season).capitalized), \(CivilFormat.format(sky.date, "EEEE, MMMM d", sky.zone))."
    }

    static func spokenMoon(_ sky: ComplicationSky) -> String {
        "\(moonPhase(sky).capitalized), \(illumination(sky)) lit. \(season(sky.season).capitalized)."
    }
}

// MARK: - Look

/// Sundial Condensed, the instrument's label face. The extension bundles
/// sundial_condensed.ttf and lists it under UIAppFonts (project.yml), and registers it for its
/// process as well, in case UIAppFonts is not honoured in an extension; SwiftUI falls back to the
/// system font if it is missing. (The curved corner label and the inline text are set by the
/// system in its own face.)
enum ComplicationFonts {
    /// A fixed size: complications have no room to grow with Dynamic Type.
    static func condensed(_ size: CGFloat) -> Font {
        SundialResources.registerFonts()
        return .custom(FontLibrary.condensedPostScriptName, fixedSize: size)
    }
}

/// The instrument's colours for a complication. A tinted face keeps only each colour's opacity
/// (and whether it is accented), so there everything is white at the instrument's alphas.
struct ComplicationPalette {
    let style: CelestialStyle
    let fullColor: Bool

    init(_ style: CelestialStyle, _ renderingMode: WidgetRenderingMode) {
        self.style = style
        fullColor = renderingMode == .fullColor
    }

    /// A SundialCore colour (0xAARRGGBB).
    static func color(_ argb: ARGB) -> Color {
        Color(.sRGB,
              red: Double(Colors.red(argb)) / 255,
              green: Double(Colors.green(argb)) / 255,
              blue: Double(Colors.blue(argb)) / 255,
              opacity: Double(Colors.alpha(argb)) / 255)
    }

    private func tone(_ argb: ARGB, _ alpha: Int) -> Color {
        fullColor
            ? ComplicationPalette.color(Colors.argb(alpha, Colors.red(argb), Colors.green(argb), Colors.blue(argb)))
            : Color.white.opacity(Double(alpha) / 255)
    }

    /// The instrument's ink off the dial face: Brass Watch's light chrome, every other style's own
    /// instrument colour (a complication has no brass face to engrave).
    func ink(_ alpha: Int = 255) -> Color { tone(style.chromeColor, alpha) }

    var accent: Color { tone(style.accentColor, 255) }

    /// The season band's metals (Instrument.updateSeasonShaders): today's season bright, the rest
    /// faint. Dimmed for the always-on display.
    func season(_ northernSeason: Zodiac.Season, lit: Bool, dimmed: Bool) -> Color {
        let metals: [ARGB] = [0xFFDC_A247, 0xFFB3_6A32, 0xFF8D_553B, 0xFF9B_B8C6]
        let alpha = lit ? 215 : 72
        return tone(metals[northernSeason.ordinal], dimmed ? alpha / 2 : alpha)
    }

    /// The astrology instrument's Earth tint.
    var earth: Color { tone(0xFFB5_E6FF, 255) }
    /// The Moon's aura colour.
    var moonLight: Color { tone(0xFFFF_FCE5, 255) }
    var moonShadow: Color { tone(style.chromeColor, 40) }

    /// The style's night sky, as Instrument.drawBackground's atmosphere: its halo in the middle
    /// fading to its base colour.
    var skyGradient: Gradient {
        let halo = style.haloColor
        let base = style.baseColor
        func mix(_ a: Int, _ b: Int) -> Int { Int(Double(a) + Double(b - a) * 0.58) }
        let between = Colors.rgb(mix(Colors.red(halo), Colors.red(base)), mix(Colors.green(halo), Colors.green(base)),
                                 mix(Colors.blue(halo), Colors.blue(base)))
        return Gradient(stops: [
            Gradient.Stop(color: ComplicationPalette.color(halo), location: 0),
            Gradient.Stop(color: ComplicationPalette.color(between), location: 0.58),
            Gradient.Stop(color: ComplicationPalette.color(base), location: 1),
        ])
    }

    /// Instrument.drawSunBloom's haze.
    static let sunHaze = Gradient(stops: [
        Gradient.Stop(color: ComplicationPalette.color(0xF5FF_FDF0), location: 0),
        Gradient.Stop(color: ComplicationPalette.color(0xD8FF_D37A), location: 0.10),
        Gradient.Stop(color: ComplicationPalette.color(0x52F2_8B32), location: 0.27),
        Gradient.Stop(color: ComplicationPalette.color(0x16C8_5022), location: 0.56),
        Gradient.Stop(color: ComplicationPalette.color(0x0000_0000), location: 1),
    ])

    /// Instrument.drawSunBloom's core.
    static let sunCore = Gradient(stops: [
        Gradient.Stop(color: ComplicationPalette.color(0xFFFF_FFFF), location: 0),
        Gradient.Stop(color: ComplicationPalette.color(0xFFFF_F7D2), location: 0.58),
        Gradient.Stop(color: ComplicationPalette.color(0xFFFF_C65A), location: 1),
    ])
}

// MARK: - Views

/// accessoryCircular: the year dial on the style's sky (or the system's backdrop on a tinted face).
struct ComplicationYearDialView: View {
    let entry: SundialComplicationEntry
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        let sky = ComplicationSky(entry.date, north: entry.settings.north)
        let palette = ComplicationPalette(entry.settings.style, renderingMode)
        ZStack {
            // A tinted face gets the system's backdrop; full colour gets the style's sky.
            if !palette.fullColor {
                AccessoryWidgetBackground()
            }
            ComplicationYearDial(sky: sky, palette: palette, backdrop: true, dimmed: isLuminanceReduced)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(ComplicationText.spokenDial(sky)))
        .containerBackground(for: .widget) { Color.clear }
    }
}

/// accessoryCorner: the Moon, with the season curving along the corner.
struct ComplicationMoonCornerView: View {
    let entry: SundialComplicationEntry
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let sky = ComplicationSky(entry.date, north: entry.settings.north)
        let palette = ComplicationPalette(entry.settings.style, renderingMode)
        ComplicationMoonDisc(phase: sky.moonPhase, north: sky.north, palette: palette)
            .padding(2)
            .widgetLabel {
                Text(ComplicationText.season(sky.season))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(ComplicationText.spokenMoon(sky)))
            .containerBackground(for: .widget) { Color.clear }
    }
}

/// accessoryRectangular: the year dial beside the season, the Moon's phase and the Sun's sign.
struct ComplicationSummaryView: View {
    let entry: SundialComplicationEntry
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        let sky = ComplicationSky(entry.date, north: entry.settings.north)
        let palette = ComplicationPalette(entry.settings.style, renderingMode)
        let lastLine = entry.settings.astrology ? ComplicationText.sign(sky.sunSign) : ComplicationText.day(sky)
        let spoken = ComplicationText.spokenDial(sky) + " " + ComplicationText.spokenMoon(sky)
            + (entry.settings.astrology ? " The Sun is in \(sky.sunSign.displayName)." : "")
        HStack(spacing: 6) {
            ComplicationYearDial(sky: sky, palette: palette, backdrop: true, dimmed: isLuminanceReduced)
                .aspectRatio(1, contentMode: .fit)
            VStack(alignment: .leading, spacing: 1) {
                Text(ComplicationText.season(sky.season))
                    .font(ComplicationFonts.condensed(18))
                    .tracking(18 * 0.12)
                    .foregroundStyle(palette.accent)
                    .widgetAccentable()
                HStack(spacing: 4) {
                    ComplicationMoonDisc(phase: sky.moonPhase, north: sky.north, palette: palette)
                        .frame(width: 11, height: 11)
                    Text(ComplicationText.moonPhase(sky))
                        .font(ComplicationFonts.condensed(13))
                        .tracking(13 * 0.06)
                }
                Text(lastLine)
                    .font(ComplicationFonts.condensed(13))
                    .tracking(13 * 0.06)
            }
            .foregroundStyle(palette.ink(230))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spoken))
        .containerBackground(for: .widget) {
            LinearGradient(gradient: palette.skyGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

/// accessoryInline: the season and the Moon in words, shortened to fit the face.
struct ComplicationInlineView: View {
    let entry: SundialComplicationEntry

    var body: some View {
        let sky = ComplicationSky(entry.date, north: entry.settings.north)
        let season = ComplicationText.season(sky.season)
        let sign = ComplicationText.sign(sky.sunSign)
        let phase = ComplicationText.moonPhase(sky)
        let astrology = entry.settings.astrology
        let long: String = astrology ? "\(season) · \(sign) · \(phase)" : "\(season) · \(phase)"
        let short: String = astrology ? "\(season) · \(sign)" : "\(season) · \(ComplicationText.illumination(sky))"
        ViewThatFits(in: .horizontal) {
            Label(long, systemImage: sky.moonSymbolName)
            Label(short, systemImage: sky.moonSymbolName)
            Text(season)
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

/// The year dial in SwiftUI shapes: DialGeometry's annual angles, radii in half-sizes of the view.
/// The instrument's proportions are kept where they read at this size (the Earth's orbit at
/// DialGeometry.earthOrbit of the dial, today's line from 0.77 of it to the rim); the season band,
/// the Sun and the Earth are drawn larger than on the instrument so they read on a wrist.
struct ComplicationYearDial: View {
    let sky: ComplicationSky
    let palette: ComplicationPalette
    /// Lays the style's sky behind the dial in full colour.
    var backdrop = false
    /// The always-on display: no Sun haze, a fainter season band.
    var dimmed = false

    /// The annual dial's radius; the season band lies just outside it.
    private var dial: Double { 0.80 }

    var body: some View {
        GeometryReader { proxy in
            let half = Double(min(proxy.size.width, proxy.size.height)) / 2
            let hairline = CGFloat(max(0.6, half * 0.025))
            let line = CGFloat(max(0.8, half * 0.04))
            ZStack {
                if backdrop && palette.fullColor {
                    ComplicationCircle(radius: 1)
                        .fill(RadialGradient(gradient: palette.skyGradient, center: .center,
                                             startRadius: 0, endRadius: CGFloat(half)))
                }
                // The season band, today's season lit.
                ForEach(sky.seasonArcs) { arc in
                    ComplicationAnnulusArc(startFraction: arc.start, endFraction: arc.end,
                                           inner: dial * 1.06, outer: dial * 1.24, north: sky.north)
                        .fill(palette.season(arc.northernSeason, lit: arc.lit, dimmed: dimmed))
                        .widgetAccentable(arc.lit)
                }
                // Unity's dotted solstice and equinox lines across the dial.
                ComplicationSeasonCross(radius: dial * 0.97)
                    .stroke(palette.ink(128), style: StrokeStyle(lineWidth: hairline, lineCap: .round,
                                                                 dash: [0.01, CGFloat(half * 0.09)]))
                // The annual dial's rim and its month ticks.
                ComplicationCircle(radius: dial)
                    .stroke(palette.ink(), lineWidth: line)
                ComplicationTicks(fractions: sky.monthStarts, inner: dial * 0.84, outer: dial, north: sky.north)
                    .stroke(palette.ink(), lineWidth: hairline)
                // The Earth's orbit.
                ComplicationCircle(radius: dial * DialGeometry.earthOrbit)
                    .stroke(palette.ink(90), lineWidth: hairline)
                // Today's line across the month names (Instrument.drawYearMarker).
                ComplicationTicks(fractions: [sky.yearFraction], inner: dial * 0.77, outer: dial * 1.06, north: sky.north)
                    .stroke(palette.ink(210), lineWidth: hairline)
                // The Earth hand from the Sun (Instrument.drawOrbit's dial triangle).
                ComplicationDialHand(fraction: sky.yearFraction, length: dial * DialGeometry.earthOrbit,
                                     halfBase: dial * 0.06, north: sky.north)
                    .fill(palette.ink())
                // The Sun.
                if !dimmed {
                    ComplicationCircle(radius: 0.36)
                        .fill(RadialGradient(gradient: ComplicationPalette.sunHaze, center: .center,
                                             startRadius: 0, endRadius: CGFloat(half * 0.36)))
                }
                ComplicationCircle(radius: 0.13)
                    .fill(RadialGradient(gradient: ComplicationPalette.sunCore, center: UnitPoint(x: 0.48, y: 0.48),
                                         startRadius: 0, endRadius: CGFloat(half * 0.17)))
                    .widgetAccentable()
                // The Earth on its orbit.
                ComplicationOrbitBody(fraction: sky.yearFraction, orbit: dial * DialGeometry.earthOrbit,
                                      radius: 0.1, north: sky.north)
                    .fill(palette.earth)
                    .widgetAccentable()
                ComplicationOrbitBody(fraction: sky.yearFraction, orbit: dial * DialGeometry.earthOrbit,
                                      radius: 0.1, north: sky.north)
                    .stroke(palette.ink(200), lineWidth: hairline)
                // Today's diamond, on the season band.
                ComplicationDiamond(fraction: sky.yearFraction, radius: dial * 1.15, size: 0.08, north: sky.north)
                    .fill(palette.ink())
                    .widgetAccentable()
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

/// The Moon's disc: its night side faint, its lit side accented, and the instrument's rim.
struct ComplicationMoonDisc: View {
    let phase: Double
    let north: Bool
    let palette: ComplicationPalette

    var body: some View {
        ZStack {
            Circle()
                .fill(palette.moonShadow)
            ComplicationMoonLight(phase: phase, north: north)
                .fill(palette.moonLight)
                .widgetAccentable()
            Circle()
                .strokeBorder(palette.ink(184), lineWidth: 0.8)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Shapes

/// Points on a dial centred in a view: radii are in half-sizes of the view (the shorter side) and
/// angles are DialGeometry's canvas angles, degrees clockwise from three o'clock on a y-down screen,
/// as SwiftUI draws.
enum ComplicationGeometry {
    static func half(_ rect: CGRect) -> Double { Double(min(rect.width, rect.height)) / 2 }

    static func point(_ rect: CGRect, _ radius: Double, _ angleDegrees: Double) -> CGPoint {
        let distance = radius * half(rect)
        let angle = angleDegrees * Double.pi / 180
        return CGPoint(x: Double(rect.midX) + cos(angle) * distance, y: Double(rect.midY) + sin(angle) * distance)
    }
}

/// A circle about the centre.
struct ComplicationCircle: Shape {
    var radius: Double

    func path(in rect: CGRect) -> Path {
        let r = radius * ComplicationGeometry.half(rect)
        return Path(ellipseIn: CGRect(x: Double(rect.midX) - r, y: Double(rect.midY) - r, width: 2 * r, height: 2 * r))
    }
}

/// A band of the annual dial between two year fractions (the end may pass 1 to wrap New Year).
struct ComplicationAnnulusArc: Shape {
    var startFraction: Double
    var endFraction: Double
    var inner: Double
    var outer: Double
    var north: Bool

    func path(in rect: CGRect) -> Path {
        let steps = max(2, Int((abs(endFraction - startFraction) * 120).rounded(.up)))
        func angle(_ step: Int) -> Double {
            DialGeometry.annualAngle(startFraction + (endFraction - startFraction) * Double(step) / Double(steps), north)
        }
        var path = Path()
        path.move(to: ComplicationGeometry.point(rect, outer, angle(0)))
        for step in 1...steps {
            path.addLine(to: ComplicationGeometry.point(rect, outer, angle(step)))
        }
        for step in stride(from: steps, through: 0, by: -1) {
            path.addLine(to: ComplicationGeometry.point(rect, inner, angle(step)))
        }
        path.closeSubpath()
        return path
    }
}

/// Radial ticks at year fractions.
struct ComplicationTicks: Shape {
    var fractions: [Double]
    var inner: Double
    var outer: Double
    var north: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for fraction in fractions {
            let angle = DialGeometry.annualAngle(fraction, north)
            path.move(to: ComplicationGeometry.point(rect, inner, angle))
            path.addLine(to: ComplicationGeometry.point(rect, outer, angle))
        }
        return path
    }
}

/// The equinox (horizontal) and solstice (vertical) lines through the Sun.
struct ComplicationSeasonCross: Shape {
    var radius: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for angle in [0.0, 90.0] {
            path.move(to: ComplicationGeometry.point(rect, radius, angle))
            path.addLine(to: ComplicationGeometry.point(rect, radius, angle + 180))
        }
        return path
    }
}

/// A hand from the centre to [length] at a year fraction (Instrument.drawDialTriangle).
struct ComplicationDialHand: Shape {
    var fraction: Double
    var length: Double
    var halfBase: Double
    var north: Bool

    func path(in rect: CGRect) -> Path {
        let angle = DialGeometry.annualAngle(fraction, north)
        var path = Path()
        path.move(to: ComplicationGeometry.point(rect, halfBase, angle - 90))
        path.addLine(to: ComplicationGeometry.point(rect, length, angle))
        path.addLine(to: ComplicationGeometry.point(rect, halfBase, angle + 90))
        path.closeSubpath()
        return path
    }
}

/// A body of [radius] on an orbit of radius [orbit], at a year fraction.
struct ComplicationOrbitBody: Shape {
    var fraction: Double
    var orbit: Double
    var radius: Double
    var north: Bool

    func path(in rect: CGRect) -> Path {
        let center = ComplicationGeometry.point(rect, orbit, DialGeometry.annualAngle(fraction, north))
        let r = radius * ComplicationGeometry.half(rect)
        return Path(ellipseIn: CGRect(x: Double(center.x) - r, y: Double(center.y) - r, width: 2 * r, height: 2 * r))
    }
}

/// Today's diamond: a square turned to point along the radius (Instrument.drawYearMarker).
struct ComplicationDiamond: Shape {
    var fraction: Double
    var radius: Double
    var size: Double
    var north: Bool

    func path(in rect: CGRect) -> Path {
        let angleDegrees = DialGeometry.annualAngle(fraction, north)
        let center = ComplicationGeometry.point(rect, radius, angleDegrees)
        let reach = size * ComplicationGeometry.half(rect)
        let angle = angleDegrees * Double.pi / 180
        let x = Double(center.x)
        let y = Double(center.y)
        let ux = cos(angle) * reach
        let uy = sin(angle) * reach
        var path = Path()
        path.move(to: CGPoint(x: x + ux, y: y + uy))
        path.addLine(to: CGPoint(x: x - uy, y: y + ux))
        path.addLine(to: CGPoint(x: x - ux, y: y - uy))
        path.addLine(to: CGPoint(x: x + uy, y: y - ux))
        path.closeSubpath()
        return path
    }
}

/// The lit part of the Moon's disc for a Moon–Sun elongation [phase] in degrees. The lit limb faces
/// the Sun: on the right while waxing and on the left while waning as the northern hemisphere sees
/// it, mirrored in the south. The terminator is the half ellipse whose width is cos(phase) of the
/// radius: on the lit limb at new Moon, straight at the quarters, on the far limb at full Moon.
struct ComplicationMoonLight: Shape {
    var phase: Double
    var north: Bool

    func path(in rect: CGRect) -> Path {
        let r = ComplicationGeometry.half(rect)
        let cx = Double(rect.midX)
        let cy = Double(rect.midY)
        let waxing = Astronomy.normalizeDegrees(phase) < 180
        let side: Double = waxing == north ? 1 : -1
        let terminator = cos(phase * Double.pi / 180)
        let steps = 32
        var path = Path()
        // The lit limb, top to bottom.
        for step in 0...steps {
            let theta = -Double.pi / 2 + Double.pi * Double(step) / Double(steps)
            let point = CGPoint(x: cx + side * r * cos(theta), y: cy + r * sin(theta))
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        // The terminator, bottom to top.
        for step in 1...steps {
            let theta = Double.pi / 2 - Double.pi * Double(step) / Double(steps)
            path.addLine(to: CGPoint(x: cx + side * r * terminator * cos(theta), y: cy + r * sin(theta)))
        }
        path.closeSubpath()
        return path
    }
}
