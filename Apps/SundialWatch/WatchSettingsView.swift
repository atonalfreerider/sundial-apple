// Watch settings, reached by a long press on the dial: a port of the Wear OS app's
// WatchSettingsActivity (wear/…/WatchSettingsActivity.kt) with the look of the Android
// InstrumentControls (instrument type in capitals, brass switches, outlined actions).
//
// Settings are saved as the Wear app saves them, through SundialCore's SettingsStore on the App
// Group (clock and hemisphere in WatchPreferences, the aesthetic in CelestialStylePreferences,
// astrology in ZodiacPreferences). The Wear app's one-shot requests (WatchPreferences.request,
// picked up by the dial when it resumes) become direct calls here: GALACTIC VIEW and RETURN TO NOW
// act on the instrument through [onGalactic] and [onReturnToNow], then close the settings as
// Android's finish() does. Every change is applied to the dial at once through [onChange], and
// the complications are reloaded so they follow the new aesthetic, hemisphere or astrology mode.

import SundialCore
import SundialCoreGraphics
import SwiftUI
import WidgetKit

struct WatchSettingsView: View {
    let settings: SettingsStore
    /// A setting was saved: the dial applies the saved settings (WatchActivity.applySettings).
    let onChange: () -> Void
    /// Shows or leaves the galactic view (WatchPreferences.Request.GALACTIC).
    let onGalactic: () -> Void
    /// Resets the instrument to the current time (WatchPreferences.Request.NOW).
    let onReturnToNow: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var clock: Bool
    @State private var astrology: Bool
    @State private var southern: Bool
    @State private var style: CelestialStyle

    init(settings: SettingsStore, onChange: @escaping () -> Void, onGalactic: @escaping () -> Void,
         onReturnToNow: @escaping () -> Void) {
        self.settings = settings
        self.onChange = onChange
        self.onGalactic = onGalactic
        self.onReturnToNow = onReturnToNow
        _clock = State(initialValue: settings.watch.showClock())
        _astrology = State(initialValue: settings.zodiac.get().enabled)
        _southern = State(initialValue: settings.watch.southern())
        _style = State(initialValue: settings.celestialStyle.get())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                WatchControls.label("SUN:DIAL", 20, WatchControls.white)
                    .tracking(20 * 0.12)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)
                WatchControls.label("LONG-PRESS THE DIAL FOR SETTINGS · TURN THE CROWN TO MOVE TIME", 9, WatchControls.dim)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
                    .padding(.bottom, 8)
                WatchSwitchRow(title: "CLOCK", isOn: $clock)
                WatchSwitchRow(title: "ASTROLOGY", isOn: $astrology)
                WatchSwitchRow(title: "SOUTHERN", isOn: $southern)
                WatchActionRow(title: "GALACTIC VIEW", description: "Show or leave the galactic view") {
                    onGalactic()
                    dismiss()
                }
                WatchActionRow(title: "RETURN TO NOW", description: "Reset the instrument to the current time") {
                    onReturnToNow()
                    dismiss()
                }
                WatchControls.section("AESTHETIC")
                ForEach(CelestialStyle.pickableCases, id: \.self) { option in
                    WatchActionRow(title: "\(option == style ? "◆" : "◇")  \(option.displayName.uppercased())",
                                   description: "Use \(option.displayName)",
                                   selected: option == style) {
                        settings.celestialStyle.set(option)
                        style = option
                        saved()
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
        }
        .background(.black)
        .onChange(of: clock) { _, checked in
            settings.watch.setShowClock(checked)
            saved()
        }
        .onChange(of: astrology) { _, checked in
            var profile = settings.zodiac.get()
            profile.enabled = checked
            settings.zodiac.set(profile)
            saved()
        }
        .onChange(of: southern) { _, checked in
            settings.watch.setSouthern(checked)
            saved()
        }
    }

    private func saved() {
        onChange()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - The Android InstrumentControls, in SwiftUI

/// Sundial's native control look (core/…/ui/InstrumentControls.kt): Sundial Condensed in
/// capitals, brass switches and hairline-outlined actions. Sizes are Android's sp, taken as points.
@MainActor
enum WatchControls {
    /// InstrumentControls.BRASS.
    static let brass = color(0xFFFF_B34A)
    static let white = Color.white
    /// 0x99FFFFFF, the subtitle and section colour.
    static let dim = color(0x99FF_FFFF)

    static func color(_ argb: ARGB) -> Color {
        Color(.sRGB,
              red: Double(Colors.red(argb)) / 255,
              green: Double(Colors.green(argb)) / 255,
              blue: Double(Colors.blue(argb)) / 255,
              opacity: Double(Colors.alpha(argb)) / 255)
    }

    /// The label face (Sundial Condensed) at an Android text size, growing with Dynamic Type as sp
    /// grows with the font scale.
    static func font(_ size: CGFloat) -> Font {
        .custom(FontLibrary.condensedPostScriptName, size: size)
    }

    /// InstrumentControls.label.
    static func label(_ value: String, _ size: CGFloat, _ color: Color) -> Text {
        Text(value)
            .font(font(size))
            .foregroundStyle(color)
    }

    /// InstrumentControls.section: a dim heading with wide letter spacing.
    static func section(_ title: String) -> some View {
        label(title, 12, dim)
            .tracking(12 * 0.16)
            .padding(.leading, 2)
            .padding(.top, 18)
            .padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

/// InstrumentControls.switch: a 50-point row with the title on the left and a brass switch.
struct WatchSwitchRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            WatchControls.label(title, 16, WatchControls.white)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .tint(WatchControls.brass)
        .padding(.leading, 2)
        .padding(.trailing, 4)
        .frame(minHeight: 50)
    }
}

/// InstrumentControls.action: a full-width, 50-point outlined button with its title on the left
/// and a spoken description in place of the title (Android's contentDescription).
struct WatchActionRow: View {
    let title: String
    let description: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            WatchControls.label(title, 16, WatchControls.white)
                .lineLimit(1)
                .padding(.leading, 16)
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 50)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(WatchControls.color(0x1200_0000))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(WatchControls.color(0x45FF_FFFF), lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .accessibilityLabel(Text(description))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
