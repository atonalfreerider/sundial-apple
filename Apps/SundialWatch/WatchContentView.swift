// Sundial on the wrist: a port of the Wear OS app's WatchActivity (wear/…/WatchActivity.kt). The
// full instrument fitted to the watch's screen; Apple Watch screens are rounded rectangles, so the
// instrument uses its rectangular watch layout (Wear OS picks round or rectangular from the
// screen). The Digital Crown moves through time and the always-on display shows a dim instrument
// updated every minute, both handled by the shared InstrumentView; a long press opens settings.
// Launched with -screenshotScene (see Shared/ScreenshotScene.swift), it shows a frozen store
// screenshot scene instead, as Android's WatchStoreCapture renders it, and saves nothing.

import SundialRender
import SwiftUI

struct WatchContentView: View {
    @StateObject private var model: InstrumentModel
    /// Set when the app is launched to capture a store screenshot (ScreenshotScene): the dial is
    /// frozen, and nothing is read from or saved to the settings.
    private let screenshot: ScreenshotScene?
    @State private var showingSettings = false
    /// Bumped when the settings close, so InstrumentView appears afresh and takes the Digital
    /// Crown's focus back from the settings list (it claims the crown when it appears).
    @State private var crownFocusGeneration = 0
    @Environment(\.scenePhase) private var scenePhase

    /// [settings] is the App Group's SettingsStore, shared with the complications.
    init(settings: SettingsStore) {
        let screenshot = ScreenshotScene.fromLaunchArguments()
        self.screenshot = screenshot
        if let screenshot {
            // (StateObject's argument is an autoclosure: the instrument is made once.)
            _model = StateObject(wrappedValue: InstrumentModel(
                instrument: screenshot.makeWatchInstrument(texture: SundialResources.earthTexture(downsampled: true)),
                settings: settings))
        } else {
            _model = StateObject(wrappedValue: InstrumentModel(layout: .watchRect, settings: settings))
        }
    }

    var body: some View {
        InstrumentView(model: model)
            .id(crownFocusGeneration)
            // Full screen, as the Wear app is: the dial fills the display under the safe areas.
            .ignoresSafeArea()
            // VoiceOver cannot long-press the drawn dial: offer settings as an action.
            .accessibilityAction(named: Text("Settings")) {
                if screenshot == nil { showingSettings = true }
            }
            .onAppear {
                if screenshot != nil { return }
                // onCreate: a long press opens settings (WatchSettingsActivity).
                model.onLongPress = { showingSettings = true }
                // onResume.
                model.applyWatchSettings()
                model.resumeClock()
            }
            .onChange(of: scenePhase) { _, phase in
                if screenshot != nil { return }
                switch phase {
                case .active:
                    // onResume, unless the settings are still open over the dial.
                    if !showingSettings {
                        model.applyWatchSettings()
                        model.resumeClock()
                    }
                case .background:
                    // onPause.
                    model.pauseClock()
                default:
                    // Inactive: the wrist is down (the always-on display, which InstrumentView
                    // draws once a minute) or a system overlay is up; the dial stays live.
                    break
                }
            }
            .onChange(of: showingSettings) { _, showing in
                // The settings cover the dial, as the Wear settings activity pauses WatchActivity.
                if showing { model.pauseClock() }
            }
            .sheet(isPresented: $showingSettings, onDismiss: settingsClosed) {
                WatchSettingsView(
                    settings: model.settings,
                    onChange: { model.applyWatchSettings() },
                    onGalactic: { model.setGalacticVisible(!model.isGalacticVisible) },
                    onReturnToNow: { model.resetNow() }
                )
            }
    }

    /// The settings closed: WatchActivity.onResume.
    private func settingsClosed() {
        model.applyWatchSettings()
        model.resumeClock()
        crownFocusGeneration &+= 1
    }
}
