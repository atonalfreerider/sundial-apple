// The Home Screen widgets: the instrument as Android's celestial wallpaper drew it
// (DailyWallpaper.kt → SundialView.renderWallpaperBitmap: frozen at one moment, without the app's
// chrome, in the saved aesthetic and astrology mode, with today's reading when there is one).
// Android drew the Sun-centred view to the Home wallpaper once a day and the Earth view to the
// Lock wallpaper every 15 minutes; here both are widgets (Sundial, and Sundial Earth View) on the
// Lock wallpaper's cadence, with an entry every quarter hour for the next three hours.
//
// Widget extensions have little memory (iOS stops one at about 30 MB), so each entry is drawn when
// WidgetKit asks for its view, at no more than 2 pixels per point, by one Instrument at a time
// (it uses the half-size Earth texture and is let go after every image).

import SundialRender
import SwiftUI
import WidgetKit

// MARK: - Timeline

/// One moment and the settings to draw it with. The hemisphere is always the northern one, as
/// the Android wallpaper draws it (SundialView's north = true; the phone never saves it).
struct InstrumentEntry: TimelineEntry {
    let date: Date
    let zone: TimeZone
    let style: CelestialStyle
    let zodiac: ZodiacProfile
    /// Today's reading (astrology only), for the widgets with room for it beside the dial.
    let horoscope: String?

    init(date: Date, zone: TimeZone, style: CelestialStyle, zodiac: ZodiacProfile, horoscope: String?) {
        self.date = date
        self.zone = zone
        self.style = style
        self.zodiac = zodiac
        self.horoscope = horoscope
    }

    init(date: Date, settings: WidgetSettings, zone: TimeZone = .current) {
        self.init(date: date, zone: zone, style: settings.style, zodiac: settings.zodiac,
                  horoscope: settings.horoscope(on: date, zone))
    }
}

struct InstrumentProvider: TimelineProvider {
    func placeholder(in context: Context) -> InstrumentEntry {
        InstrumentEntry(date: Date(), zone: .current, style: .voidBlack, zodiac: ZodiacProfile(), horoscope: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (InstrumentEntry) -> Void) {
        completion(InstrumentEntry(date: Date(), settings: WidgetSettings.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<InstrumentEntry>) -> Void) {
        let settings = WidgetSettings.load()
        // Entries hold only settings and a moment; the image is drawn per entry by the view.
        let entries = WidgetSchedule.quarterHours(from: Date(), hours: 3).map {
            InstrumentEntry(date: $0, settings: settings)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Widgets

/// The Sun-centred instrument (Android's Home wallpaper).
struct InstrumentWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SundialWidgetKind.instrument, provider: InstrumentProvider()) { entry in
            InstrumentWidgetView(entry: entry, state: .heliocentric)
        }
        .configurationDisplayName("Sundial")
        .description("The Sun-centred instrument: the year dial, the planets and the Earth, redrawn every 15 minutes.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        // The instrument draws its own sky to the edges, as the wallpaper filled the screen.
        .contentMarginsDisabled()
    }
}

/// The Earth-centred instrument (Android's Lock wallpaper).
struct EarthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SundialWidgetKind.earth, provider: InstrumentProvider()) { entry in
            InstrumentWidgetView(entry: entry, state: .geocentric)
        }
        .configurationDisplayName("Sundial Earth View")
        .description("The Earth-centred instrument: the lunar dial and the Moon around the Earth, redrawn every 15 minutes.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        .contentMarginsDisabled()
    }
}

struct InstrumentWidgetView: View {
    let entry: InstrumentEntry
    /// The view drawn: heliocentric (Sundial) or geocentric (Sundial Earth View).
    let state: Instrument.ViewState
    @Environment(\.displayScale) var displayScale

    var body: some View {
        // At most 2 pixels per point: the full-scale bitmap and the instrument's caches for it
        // would not fit in the extension's memory on a 3× iPhone.
        let renderScale = min(displayScale, InstrumentWidgetRenderer.maximumScale)
        GeometryReader { geometry in
            if let image = InstrumentWidgetRenderer.render(entry, size: geometry.size, scale: renderScale,
                                                           state: state) {
                Image(decorative: image, scale: renderScale, orientation: .up)
                    .resizable()
                    .frame(width: geometry.size.width, height: geometry.size.height)
            } else {
                WidgetLook.color(entry.style.baseColor)
            }
        }
        // The sky's base colour behind the image; the system removes it where it draws widgets
        // without their backgrounds (StandBy, tinted Home Screens), and the image keeps its own sky.
        .containerBackground(for: .widget) { WidgetLook.color(entry.style.baseColor) }
        .widgetURL(state == .geocentric ? SundialDeepLink.earth : SundialDeepLink.solar)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: InstrumentWidgetRenderer.accessibilityDescription(entry, state)))
    }
}

// MARK: - Rendering

/// Draws the entries with Apps/Shared's InstrumentImage, one image at a time (under [lock]), for
/// both widget kinds and every family. Each image gets a fresh Instrument, updated to the entry's
/// settings, which is let go before the next one starts: its Earth renderer (the sphere samples
/// and cached frames) is the largest part of the widget's memory, so it does not stay between
/// entries. The Earth texture stays decoded in SundialResources' cache.
enum InstrumentWidgetRenderer {
    /// The most pixels per point a widget is drawn at (a 3× screen scales the image up).
    static let maximumScale: CGFloat = 2

    private static let lock = NSLock()

    /// The entry's instrument in [state] at [size] points, rendered at [scale] pixels per point
    /// (the Instrument's density too); nil for an empty size or if the bitmap cannot be made.
    static func render(_ entry: InstrumentEntry, size: CGSize, scale: CGFloat,
                       state: Instrument.ViewState) -> CGImage? {
        guard size.width >= 1, size.height >= 1, scale > 0 else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return draw(entry, size: size, scale: scale, state: state)
    }

    /// One image from a new Instrument, released when this returns (still inside the lock).
    ///
    /// The Instrument draws in the bitmap's pixels (density = scale), as Android's wallpaper does,
    /// so its label halos come out at their Android size; the widget's Earth texture is the
    /// half-size one. drawWallpaper sets the view on every draw.
    private static func draw(_ entry: InstrumentEntry, size: CGSize, scale: CGFloat,
                             state: Instrument.ViewState) -> CGImage? {
        let instrument = SundialResources.makeInstrument(layout: .phone, density: Double(scale),
                                                         downsampledTexture: true, now: entry.date)
        instrument.zone = entry.zone
        instrument.setBackgroundStyle(entry.style)
        instrument.setSouthernHemisphere(false)
        instrument.setZodiacProfile(entry.zodiac, horoscope: horoscopeFits(size) ? entry.horoscope : nil)
        return InstrumentImage.wallpaper(instrument, size: size, scale: scale, instant: entry.date, state: state)
    }

    /// Whether drawHoroscopeCard (Instrument+Chrome) can lay the reading beside the dial or above
    /// and below it at this size (in points, on the phone layout's geometry), rather than over the
    /// dial. On the wallpaper it always had a phone screen's room; among the widgets only the
    /// iPad's extra large one has room beside the dial, so the smaller ones leave the reading out.
    static func horoscopeFits(_ size: CGSize) -> Bool {
        let width = Double(size.width)
        let height = Double(size.height)
        // Instrument.geometry() for InstrumentLayout.phone.
        let cx = width / 2
        let cy = height * (height > width * 1.25 ? 0.47 : 0.5)
        let r = min(width * 0.47, height * 0.41)
        // drawHoroscopeCard's wallpaper bounds.
        let dialTop = cy - r * 1.08
        let dialBottom = cy + r * 1.08
        let topHeight = dialTop - 10 - 66
        let bottomHeight = height - 16 - (dialBottom + 10)
        let minimumPanelHeight = 92.0
        let sideWidth = min(cx - r * 1.1 - 28, 360)
        let beside = sideWidth >= 150 && topHeight < minimumPanelHeight
        let aboveAndBelow = topHeight >= minimumPanelHeight && bottomHeight >= minimumPanelHeight
        return beside || aboveAndBelow
    }

    /// VoiceOver's description of the widget (the instrument's own summary is built only when it
    /// draws interactively).
    static func accessibilityDescription(_ entry: InstrumentEntry, _ state: Instrument.ViewState) -> String {
        let moment = CivilFormat.format(entry.date, "EEEE, MMMM d, yyyy, h:mm a", entry.zone)
        if state == .geocentric {
            return "Sundial Earth view, \(moment). The lunar dial circles the Earth, with the Moon in today's phase."
        }
        return "Sundial solar view, \(moment). The year dial circles the Sun, with the Earth at today's date."
    }
}
