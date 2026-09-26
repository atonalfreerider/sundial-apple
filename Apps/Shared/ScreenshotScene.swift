// Screenshot mode, shared by the iOS app and the watch app: the launch arguments the App Store
// screenshots are taken with (SundialUITests/ScreenshotTests on iPhone and iPad; `simctl launch`
// on the watch, in .github/workflows/apple.yml), read from the argument domain of
// UserDefaults.standard:
//
//     -screenshotScene <view>-<style>-<zodiac>   heliocentric|geocentric|galactic,
//                                                void|crimson|blue|violet|bronze|brass,
//                                                astrology|astronomy
//     -screenshotMenu settings|calendars|astrology   (iOS: that tuck menu open)
//     -screenshotInstant 2026-09-26T03:30:00Z
//     -screenshotZone America/Los_Angeles
//     -screenshotClock off                        (watch: the time readout hidden; on by default)
//
// In this mode the instrument is frozen at one moment with the sample data of Android's
// StoreAssetsCapture.kt (phone and tablet) and WatchStoreCapture.kt (watch), and nothing of the
// device's own: no permission prompts, no EventKit, no Foundation Models, no network, and nothing
// saved to settings.

import Foundation
import SundialRender

nonisolated public struct ScreenshotScene {
    public let state: Instrument.ViewState
    public let style: CelestialStyle
    public let astrology: Bool
    /// -screenshotMenu as given: "settings", "calendars" or "astrology" (the iOS tuck menus).
    public let menu: String?
    public let instant: Date
    public let zone: TimeZone
    /// Whether the watch instrument shows its clock (-screenshotClock off hides it). The store's
    /// watch set shows it in at most one scene, so the listing shows an orrery, not a watch face.
    public let clock: Bool

    public init(state: Instrument.ViewState, style: CelestialStyle, astrology: Bool, menu: String?,
                instant: Date, zone: TimeZone, clock: Bool = true) {
        self.state = state
        self.style = style
        self.astrology = astrology
        self.menu = menu
        self.instant = instant
        self.zone = zone
        self.clock = clock
    }

    /// The scene the app was launched to capture, or nil when -screenshotScene is absent or not
    /// of the form view-style-zodiac.
    public static func fromLaunchArguments(_ defaults: UserDefaults = .standard) -> ScreenshotScene? {
        guard let scene = defaults.string(forKey: "screenshotScene") else { return nil }
        let parts = scene.lowercased().split(separator: "-").map(String.init)
        guard parts.count == 3 else { return nil }
        let state: Instrument.ViewState
        switch parts[0] {
        case "geocentric": state = .geocentric
        case "galactic": state = .galactic
        default: state = .heliocentric
        }
        let style: CelestialStyle
        switch parts[1] {
        case "crimson": style = .crimsonNebula
        case "blue": style = .deepSpaceBlue
        case "violet": style = .cosmicViolet
        case "bronze": style = .solarBronze
        case "brass": style = .brassWatch
        default: style = .voidBlack
        }
        let instant = defaults.string(forKey: "screenshotInstant")
            .flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
        let zone = defaults.string(forKey: "screenshotZone").flatMap { TimeZone(identifier: $0) } ?? TimeZone.current
        let clock = defaults.string(forKey: "screenshotClock")?.lowercased() != "off"
        return ScreenshotScene(state: state, style: style, astrology: parts[2] == "astrology",
                               menu: defaults.string(forKey: "screenshotMenu"), instant: instant, zone: zone,
                               clock: clock)
    }

    // MARK: StoreAssetsCapture.kt (iPhone and iPad)

    /// The sample reader: an Aries born 1990-04-18 at 06:45.
    public static let sampleProfile = ZodiacProfile(enabled: true, birthDate: LocalDate(1990, 4, 18),
                                                    birthTime: LocalTime(6, 45))

    public static let sampleReading = "The brass gears of the heavens turn in your favour today, Aries. With the Sun " +
        "in Libra across from your own sign, partnerships ask for patience and a generous ear. The Moon " +
        "brightens your curiosity; follow a question you have been saving. Venus lends grace to a " +
        "difficult conversation, and by evening a small kindness returns to you twice over."

    /// The calendar menu's calendars; 1 and 2 are selected.
    public static let calendars = [
        DeviceCalendar(1, "Personal", "you@example.com", "com.google", 0xFF4C_AF50),
        DeviceCalendar(2, "Work", "you@example.com", "com.google", 0xFFE0_40FB),
        DeviceCalendar(3, "Holidays", "you@example.com", "com.google", 0xFF42_A5F5),
    ]
    public static let selectedCalendarIds: [Int64] = [1, 2]

    public var calendars: [DeviceCalendar] { ScreenshotScene.calendars }

    /// StoreAssetsCapture.events(): four long events around the year and four today.
    public func events() -> [CalendarOccurrence] {
        let zone = self.zone
        let today = LocalDate.of(instant, zone)
        func allDay(_ id: Int64, _ calendar: Int64, _ title: String, _ start: LocalDate, _ days: Int,
                    _ color: ARGB) -> CalendarOccurrence {
            let end = start.plusDays(days)
            return CalendarOccurrence(id, calendar, title, ZonedDateTime(start.atStartOfDay(zone), zone),
                                      ZonedDateTime(end.atStartOfDay(zone), zone), start, end, color)
        }
        func timed(_ id: Int64, _ calendar: Int64, _ title: String, _ hour: Int, _ minutes: Int,
                   _ color: ARGB) -> CalendarOccurrence {
            let start = ZonedDateTime.instant(today, LocalTime(hour, 0), zone)
            return CalendarOccurrence(id, calendar, title, ZonedDateTime(start, zone),
                                      ZonedDateTime(start.addingTimeInterval(Double(minutes * 60)), zone),
                                      nil, nil, color)
        }
        return [
            allDay(1, 1, "Harvest festival", LocalDate(2026, 9, 26), 3, 0xFFE8_A33D),
            allDay(2, 1, "Autumn road trip", LocalDate(2026, 10, 30), 9, 0xFF4C_AF50),
            allDay(3, 2, "Winter break", LocalDate(2026, 12, 19), 14, 0xFF42_A5F5),
            allDay(4, 2, "Spring term", LocalDate(2027, 1, 20), 30, 0xFFB3_88FF),
            timed(5, 1, "Morning run", 7, 45, 0xFF4C_AF50),
            timed(6, 2, "Design review", 10, 90, 0xFFE0_40FB),
            timed(7, 1, "Lunch with Sam", 12, 60, 0xFFE8_A33D),
            timed(8, 2, "Piano lesson", 17, 60, 0xFF42_A5F5),
        ]
    }

    // MARK: WatchStoreCapture.kt (Apple Watch)

    /// The watch scene as WatchStoreCapture renders it: the watch instrument with the clock on
    /// (unless -screenshotClock off), the sample birthday (no birth time, no reading) when astrology
    /// is on, frozen at [instant]. Apple Watch screens are rounded rectangles, so the layout is
    /// watchRect.
    public func makeWatchInstrument(texture: PixelImage) -> Instrument {
        let instrument = Instrument(layout: .watchRect, density: 1, earthTexture: texture, style: style,
                                    zone: zone, now: instant)
        instrument.setZodiacProfile(ZodiacProfile(enabled: astrology, birthDate: LocalDate(1990, 4, 18)),
                                    horoscope: nil)
        instrument.setClockVisible(clock)
        instrument.freezeForCapture(instant: instant, state: state, style: style)
        return instrument
    }
}
