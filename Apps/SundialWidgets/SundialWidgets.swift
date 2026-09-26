// The iOS widget extension: Sundial's replacement for the Android celestial wallpaper
// (wallpaper/DailyWallpaper.kt). Android drew the Sun-centred view to the Home wallpaper once a day
// and the Earth view to the Lock wallpaper every 15 minutes. iOS cannot set the wallpaper, so both
// views come to the Home Screen (and StandBy) as widgets, Sundial and Sundial Earth View, redrawn
// every quarter hour; the Lock Screen gets tinted accessory widgets drawn with SwiftUI shapes.
//
// Settings come from the App Group the app writes (SundialCore's SettingsStore), so a change of
// aesthetic or astrology in the app shows here once the app reloads the timelines
// (WidgetCenter.shared.reloadAllTimelines(), where Android called refreshWallpapers()). Like the
// wallpaper, every widget draws the northern hemisphere.

import SundialCore
import SwiftUI
import WidgetKit

@main
struct SundialWidgets: WidgetBundle {
    var body: some Widget {
        InstrumentWidget()
        EarthWidget()
        SundialLockScreenWidget()
    }
}

/// The widget kinds, for WidgetCenter.reloadTimelines(ofKind:).
enum SundialWidgetKind {
    static let instrument = "SundialInstrument"
    static let earth = "SundialEarth"
    static let lockScreen = "SundialLockScreen"
}

/// Links a tap on a widget opens: the app with the Sun-centred instrument, or flying to its Earth
/// view (the lunar dial). The app registers the `sundial` URL scheme (AppModel.openURL).
enum SundialDeepLink {
    static let solar = URL(string: "sundial://view/heliocentric")!
    static let earth = URL(string: "sundial://view/geocentric")!
}

// MARK: - Settings

/// The settings a widget draws with, read once per timeline from the App Group's SettingsStore
/// (SundialResources.settings(), on the group.com.metavirtuoso.sundial suite).
struct WidgetSettings {
    let style: CelestialStyle
    let zodiac: ZodiacProfile
    let store: SettingsStore

    /// Always the northern hemisphere, as DailyWallpaper draws it: Android's phone app keeps its
    /// hemisphere switch in the view only (SundialView's north = true) and never saves it.
    var north: Bool { true }

    static func load() -> WidgetSettings {
        let store = SundialResources.settings()
        return WidgetSettings(style: store.celestialStyle.get(),
                              zodiac: store.zodiac.get(),
                              store: store)
    }

    /// Today's reading for [date], as SundialView reads it for the wallpaper
    /// (ZodiacPreferences.getCurrentHoroscope with LocalDate.now()): nil unless astrology is on
    /// and the app wrote a reading for this profile and this day.
    func horoscope(on date: Date, _ zone: TimeZone) -> String? {
        guard zodiac.enabled else { return nil }
        return store.zodiac.getCurrentHoroscope(zodiac, LocalDate.of(date, zone))
    }
}

// MARK: - Schedule

enum WidgetSchedule {
    /// Android's WorkManager redraws the celestial Lock wallpaper every 15 minutes.
    static let interval: TimeInterval = 15 * 60

    /// [now], then every quarter hour on the clock (:00, :15, :30, :45) for [hours] hours. Every
    /// time zone's offset is a whole number of quarter hours, so local midnight is always one of them.
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

// MARK: - Look

/// The widgets' type and colours, namespaced so they cannot clash with helpers in Apps/Shared.
enum WidgetLook {
    /// Sundial Condensed, the instrument's and the panels' label face. The widget
    /// extension bundles sundial_condensed.ttf and lists it under UIAppFonts, and it is registered
    /// for this process too; SwiftUI falls back to the system font if it is missing.
    static func condensed(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        SundialResources.registerFonts()
        return .custom(SundialResources.condensedPostScriptName, size: size, relativeTo: style)
    }

    /// A SundialCore colour (0xAARRGGBB).
    static func color(_ argb: ARGB) -> Color {
        Color(.sRGB,
              red: Double(Colors.red(argb)) / 255,
              green: Double(Colors.green(argb)) / 255,
              blue: Double(Colors.blue(argb)) / 255,
              opacity: Double(Colors.alpha(argb)) / 255)
    }
}
