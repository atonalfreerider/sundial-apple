// Lock Screen widgets. Accessory widgets are drawn by the system in one tint (vibrant on the iOS
// Lock Screen, accented or full colour elsewhere), so nothing here is an image: the annual dial,
// the Earth, the Sun and the Moon are SwiftUI shapes laid out with SundialCore's DialGeometry and
// Astronomy, the same geometry the instrument draws with.
//
//   accessoryCircular     the annual dial: a ring with a tick at every month, today's line, the
//                         Earth on its orbit by the civil date, and the Sun at the centre
//   accessoryRectangular  the Moon's phase as a glyph, its name, and the season (and the Sun's
//                         sign when astrology is on)
//   accessoryInline       the phase and season in one short line

import SundialCore
import SwiftUI
import WidgetKit

// MARK: - Timeline

/// One moment on the Lock Screen and what the widgets show for it.
struct SkyEntry: TimelineEntry {
    let date: Date
    let zone: TimeZone
    let north: Bool
    let astrology: Bool
    let style: CelestialStyle

    /// The Earth's place on the annual dial: the fraction of the civil year gone, as the
    /// instrument's Earth hand and year marker (currentEarthAngle) place it.
    let yearFraction: Double
    /// Where each month begins on the annual dial, January first.
    let monthStartFractions: [Double]
    /// Moon–Sun elongation in degrees: 0 new, 90 first quarter, 180 full, 270 last quarter.
    let moonPhaseDegrees: Double
    let season: Zodiac.Season
    /// The Sun's sign today, the sign the instrument's zodiac ring lights.
    let sign: Zodiac.Sign

    init(date: Date, zone: TimeZone, north: Bool, astrology: Bool, style: CelestialStyle) {
        self.date = date
        self.zone = zone
        self.north = north
        self.astrology = astrology
        self.style = style
        let local = ZonedDateTime(date, zone)
        yearFraction = Astronomy.civilYearFraction(local)
        // As drawAnnualScale spaces its day ticks: day index over the days in the year.
        let days = Double(Astronomy.daysInYear(local.year))
        monthStartFractions = (1...12).map { Double(LocalDate(local.year, $0, 1).dayOfYear - 1) / days }
        moonPhaseDegrees = Astronomy.moonPhaseDegrees(date)
        season = Zodiac.seasonFor(local.date, north)
        sign = Zodiac.signFor(local.date)
    }

    init(date: Date, settings: WidgetSettings, zone: TimeZone = .current) {
        self.init(date: date, zone: zone, north: settings.north, astrology: settings.zodiac.enabled,
                  style: settings.style)
    }

    // MARK: Words

    /// The season as the instrument's season ring names it (Season.name: "SPRING" … "FALL").
    var seasonName: String { String(describing: season).uppercased() }

    var signName: String { "\(sign.symbol) \(sign.displayName.uppercased())" }

    /// The phase's common name, in eight equal parts of the synodic month centred on the new,
    /// quarter and full Moons.
    var moonPhaseName: String {
        let names = ["NEW MOON", "WAXING CRESCENT", "FIRST QUARTER", "WAXING GIBBOUS",
                     "FULL MOON", "WANING GIBBOUS", "LAST QUARTER", "WANING CRESCENT"]
        let index = Int(((Astronomy.normalizeDegrees(moonPhaseDegrees) + 22.5) / 45).rounded(.down)) % 8
        return names[index]
    }

    /// The lit fraction of the Moon's disc, 0 new to 1 full.
    var moonIllumination: Double { (1 - cos(moonPhaseDegrees * .pi / 180)) / 2 }

    /// The season, with the Sun's sign when astrology is on (astronomy mode shows no signs).
    var seasonLine: String { astrology ? "\(seasonName) · \(signName)" : seasonName }
}

struct SkyProvider: TimelineProvider {
    func placeholder(in context: Context) -> SkyEntry {
        SkyEntry(date: Date(), zone: .current, north: true, astrology: false, style: .voidBlack)
    }

    func getSnapshot(in context: Context, completion: @escaping (SkyEntry) -> Void) {
        completion(SkyEntry(date: Date(), settings: WidgetSettings.load()))
    }

    /// Six hours of quarter-hour entries: the Earth moves along the dial, the Moon waxes or wanes,
    /// and the season and sign turn over at local midnight. These are cheap, text and shapes only.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SkyEntry>) -> Void) {
        let settings = WidgetSettings.load()
        let entries = WidgetSchedule.quarterHours(from: Date(), hours: 6).map {
            SkyEntry(date: $0, settings: settings)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Widget

struct SundialLockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SundialWidgetKind.lockScreen, provider: SkyProvider()) { entry in
            SundialLockScreenView(entry: entry)
        }
        .configurationDisplayName("Sundial")
        .description("The year dial with the Earth on its orbit, the Moon's phase and the season.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct SundialLockScreenView: View {
    let entry: SkyEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            AnnualDialAccessory(entry: entry)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
                .widgetURL(SundialDeepLink.solar)
        case .accessoryRectangular:
            MoonPhaseAccessory(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(SundialDeepLink.earth)
        default:
            InlineAccessory(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(SundialDeepLink.earth)
        }
    }
}

/// Colours for the accessory widgets. The Lock Screen draws them vibrant and a tinted face
/// accented, keeping only each shape's opacity, so there they are white; in full colour (where a
/// host shows them so) they take the chosen aesthetic's light ink, a gold Sun and a blue Earth.
struct AccessoryPalette {
    let ink: Color
    let sun: Color
    let earth: Color

    init(_ mode: WidgetRenderingMode, _ style: CelestialStyle) {
        if mode == .fullColor {
            // chromeColor is the light ink every aesthetic draws off the dial face.
            ink = WidgetLook.color(style.chromeColor)
            sun = WidgetLook.color(0xFFFF_D37A)
            earth = WidgetLook.color(0xFF8E_D9FF)
        } else {
            ink = .white
            sun = .white
            earth = .white
        }
    }
}

// MARK: - accessoryCircular: the annual dial

struct AnnualDialAccessory: View {
    let entry: SkyEntry
    @Environment(\.widgetRenderingMode) var renderingMode

    var body: some View {
        let palette = AccessoryPalette(renderingMode, entry.style)
        // The dial's rim as a fraction of the widget's radius, leaving room for its stroke.
        let rim = 0.86
        let earthAngle = DialGeometry.annualAngle(entry.yearFraction, entry.north)
        let monthAngles = entry.monthStartFractions.map { DialGeometry.annualAngle($0, entry.north) }
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                // The annual dial: its rim and a tick where every month begins.
                PolarRing(radius: rim)
                    .stroke(palette.ink, lineWidth: side * 0.035)
                PolarTicks(angles: monthAngles, inner: rim * 0.78, outer: rim)
                    .stroke(palette.ink.opacity(0.85), style: StrokeStyle(lineWidth: side * 0.028, lineCap: .butt))
                // The Earth's orbit.
                PolarRing(radius: rim * DialGeometry.earthOrbit)
                    .stroke(palette.ink.opacity(0.4), lineWidth: side * 0.016)
                // Today's line across the months, ending in a diamond on the rim (drawYearMarker).
                Group {
                    PolarTicks(angles: [earthAngle], inner: rim * 0.66, outer: rim)
                        .stroke(palette.earth, style: StrokeStyle(lineWidth: side * 0.03, lineCap: .butt))
                    PolarDiamond(angle: earthAngle, radius: rim, halfSize: 0.075)
                        .fill(palette.earth)
                    // The Earth on its orbit at today's civil date.
                    PolarDisc(angle: earthAngle, radius: rim * DialGeometry.earthOrbit, discRadius: 0.1)
                        .fill(palette.earth)
                }
                .widgetAccentable()
                // The Sun at the centre, with its rays.
                Group {
                    PolarDisc(angle: 0, radius: 0, discRadius: 0.15)
                        .fill(palette.sun)
                    PolarTicks(angles: Array(stride(from: 0.0, to: 360.0, by: 45.0)), inner: 0.2, outer: 0.28)
                        .stroke(palette.sun, style: StrokeStyle(lineWidth: side * 0.03, lineCap: .round))
                }
                .widgetAccentable()
            }
            .frame(width: side, height: side)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    var accessibilityText: String {
        let day = CivilFormat.format(entry.date, "MMMM d", entry.zone)
        return "Sundial year dial: the Earth at \(day), \(entry.seasonName.lowercased())."
    }
}

// MARK: - accessoryRectangular: the Moon

struct MoonPhaseAccessory: View {
    let entry: SkyEntry
    @Environment(\.widgetRenderingMode) var renderingMode

    var body: some View {
        let palette = AccessoryPalette(renderingMode, entry.style)
        HStack(spacing: 8) {
            MoonPhaseGlyph(phaseDegrees: entry.moonPhaseDegrees, north: entry.north, ink: palette.ink)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 44, maxHeight: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.moonPhaseName)
                    .font(WidgetLook.condensed(17, relativeTo: .headline))
                    .widgetAccentable()
                Text(entry.seasonLine)
                    .font(WidgetLook.condensed(14, relativeTo: .subheadline))
                Text(verbatim: "\(Int((entry.moonIllumination * 100).rounded()))% LIT")
                    .font(WidgetLook.condensed(13, relativeTo: .caption))
                    .opacity(0.72)
            }
            .foregroundStyle(palette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(entry.moonPhaseName.capitalized), \(entry.seasonLine.capitalized)"))
    }
}

/// The Moon as it looks tonight: the lit part solid, the dark part faint, in the hemisphere's
/// orientation (the waxing Moon lit on the right in the north, on the left in the south).
struct MoonPhaseGlyph: View {
    let phaseDegrees: Double
    let north: Bool
    let ink: Color

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                PolarDisc(angle: 0, radius: 0, discRadius: 0.94)
                    .fill(ink.opacity(0.22))
                MoonLitShape(phaseDegrees: phaseDegrees, north: north, radius: 0.94)
                    .fill(ink)
                    .widgetAccentable()
                PolarRing(radius: 0.94)
                    .stroke(ink.opacity(0.6), lineWidth: max(1, side * 0.03))
            }
            .frame(width: side, height: side)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }
}

// MARK: - accessoryInline

struct InlineAccessory: View {
    let entry: SkyEntry

    var body: some View {
        // The Lock Screen's inline slot is short and set in the system font: the longest line that fits.
        ViewThatFits {
            Text(verbatim: "\(entry.moonPhaseName) · \(entry.seasonLine)")
            Text(verbatim: "\(entry.moonPhaseName) · \(entry.seasonName)")
            Text(entry.moonPhaseName)
        }
    }
}

// MARK: - Shapes

/// A shape's frame as a dial: its centre, and a radius of half the shorter side. Angles are canvas
/// angles as DialGeometry gives them, in degrees clockwise from three o'clock on a y-down screen,
/// which is SwiftUI's orientation too; radii are fractions of the dial's radius.
struct DialFrame {
    let center: CGPoint
    let radius: CGFloat

    init(_ rect: CGRect) {
        center = CGPoint(x: rect.midX, y: rect.midY)
        radius = min(rect.width, rect.height) / 2
    }

    func point(_ angleDegrees: Double, _ fraction: Double) -> CGPoint {
        let a = angleDegrees * .pi / 180
        return CGPoint(x: center.x + CGFloat(cos(a) * fraction) * radius,
                       y: center.y + CGFloat(sin(a) * fraction) * radius)
    }
}

/// A circle about the centre.
struct PolarRing: Shape {
    let radius: Double

    func path(in rect: CGRect) -> Path {
        let dial = DialFrame(rect)
        let r = dial.radius * CGFloat(radius)
        return Path(ellipseIn: CGRect(x: dial.center.x - r, y: dial.center.y - r, width: 2 * r, height: 2 * r))
    }
}

/// Radial lines from [inner] to [outer] at each angle.
struct PolarTicks: Shape {
    let angles: [Double]
    let inner: Double
    let outer: Double

    func path(in rect: CGRect) -> Path {
        let dial = DialFrame(rect)
        var path = Path()
        for angle in angles {
            path.move(to: dial.point(angle, inner))
            path.addLine(to: dial.point(angle, outer))
        }
        return path
    }
}

/// A disc of [discRadius] centred [radius] out from the centre at [angle].
struct PolarDisc: Shape {
    let angle: Double
    let radius: Double
    let discRadius: Double

    func path(in rect: CGRect) -> Path {
        let dial = DialFrame(rect)
        let c = dial.point(angle, radius)
        let r = dial.radius * CGFloat(discRadius)
        return Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }
}

/// A square turned to point along [angle], centred on the dial at [radius]: the year marker's
/// diamond.
struct PolarDiamond: Shape {
    let angle: Double
    let radius: Double
    let halfSize: Double

    func path(in rect: CGRect) -> Path {
        let dial = DialFrame(rect)
        let c = dial.point(angle, radius)
        let h = dial.radius * CGFloat(halfSize)
        let a = angle * .pi / 180
        let along = CGPoint(x: CGFloat(cos(a)) * h, y: CGFloat(sin(a)) * h)
        let across = CGPoint(x: -along.y, y: along.x)
        var path = Path()
        path.move(to: CGPoint(x: c.x + along.x, y: c.y + along.y))
        path.addLine(to: CGPoint(x: c.x + across.x, y: c.y + across.y))
        path.addLine(to: CGPoint(x: c.x - along.x, y: c.y - along.y))
        path.addLine(to: CGPoint(x: c.x - across.x, y: c.y - across.y))
        path.closeSubpath()
        return path
    }
}

/// The sunlit part of the Moon's disc: bounded by the lit limb (a half circle) and the
/// terminator (a half ellipse, x = ±cos(phase) of the limb's). Built from points, so it does not
/// depend on arc directions in SwiftUI's flipped coordinates.
struct MoonLitShape: Shape {
    let phaseDegrees: Double
    let north: Bool
    let radius: Double

    func path(in rect: CGRect) -> Path {
        let dial = DialFrame(rect)
        let r = dial.radius * CGFloat(radius)
        let phase = Astronomy.normalizeDegrees(phaseDegrees)
        // Waxing: lit on the Sun's side of the evening sky, the right from the north; waning, the left.
        let side: CGFloat = (phase < 180 ? 1 : -1) * (north ? 1 : -1)
        let terminator = CGFloat(cos(phase * .pi / 180))
        let steps = 48
        var path = Path()
        // Down the lit limb from the top of the disc to the bottom…
        for i in 0...steps {
            let phi = -Double.pi / 2 + Double.pi * Double(i) / Double(steps)
            let point = CGPoint(x: dial.center.x + side * r * CGFloat(cos(phi)),
                                y: dial.center.y + r * CGFloat(sin(phi)))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        // …and back up along the terminator.
        for i in 0...steps {
            let phi = Double.pi / 2 - Double.pi * Double(i) / Double(steps)
            path.addLine(to: CGPoint(x: dial.center.x + side * r * CGFloat(cos(phi)) * terminator,
                                     y: dial.center.y + r * CGFloat(sin(phi))))
        }
        path.closeSubpath()
        return path
    }
}
