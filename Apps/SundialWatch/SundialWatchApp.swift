// The watchOS app: Sundial's Wear OS app (wear/) on Apple Watch. A single-target SwiftUI app that
// runs on its own, as the standalone Wear OS app does, with the instrument full screen
// (WatchContentView), settings on a long press (WatchSettingsView) and the complications in
// SundialWatchWidgets in place of the Wear OS watch face.
//
// Launch registers the bundled Sundial Condensed face (the Wear app's theme font, used by
// the instrument's Core Graphics labels and the settings screen) and opens the App Group's
// settings, which the complications read too. The Wear app's WatchPreferences, the aesthetic and
// the astrology profile are all in SundialCore's SettingsStore there, under Android's keys.

import SundialRender
import SwiftUI

@main
struct SundialWatchApp: App {
    /// The App Group's settings (WatchPreferences, CelestialStylePreferences and ZodiacPreferences
    /// on Android), shared with the complications.
    private let settings: SettingsStore

    init() {
        SundialResources.registerFonts()
        settings = SundialResources.settings()
    }

    var body: some Scene {
        WindowGroup {
            WatchContentView(settings: settings)
        }
    }
}
