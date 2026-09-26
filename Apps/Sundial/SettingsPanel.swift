import SundialCore
import SwiftUI

/// The upper-left tuck menu: display, aesthetic, widget and application settings. A port of
/// SettingsPanel.kt. iOS cannot set the wallpaper, so Android's WALLPAPER switches become a note
/// on adding Sundial's widgets; and iOS apps do not quit, so there is no QUIT.
struct SettingsPanel: View {
    @ObservedObject var model: AppModel
    @Environment(\.openURL) private var openURL

    static let privacyPolicyURL = URL(string: "https://primitive.io/legal/sundial-privacy/")!

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InstrumentControls.title("SUN:DIAL", "CELESTIAL INSTRUMENT")

            InstrumentControls.section("DISPLAY")
            InstrumentSwitch("CLOCK", isOn: Binding(
                get: { model.clockVisible },
                set: { model.setClockVisible($0) }))
            InstrumentSwitch("GALACTIC AXIS", isOn: Binding(
                get: { model.galacticVisible },
                set: { model.setGalacticVisible($0) }))
            InstrumentSwitch("SOUTHERN HEMISPHERE", isOn: Binding(
                get: { model.southernHemisphere },
                set: { model.setSouthernHemisphere($0) }))
            InstrumentAction("RETURN TO NOW", "Reset the instrument to the current date and time") {
                model.resetNow()
            }

            InstrumentControls.section("AESTHETIC")
            ForEach(CelestialStyle.allCases, id: \.self) { style in
                let selected = style == model.style
                InstrumentAction("\(selected ? "◆" : "◇")  \(style.displayName.uppercased())",
                                 "Use \(style.displayName) in Sundial and its widgets",
                                 accessibilityLabel: style.displayName,
                                 selected: selected) {
                    model.setBackgroundStyle(style)
                }
            }

            InstrumentControls.section("WIDGETS")
            InstrumentControls.label(Self.widgetsNote, 14, 0x99FF_FFFF)
                .padding(EdgeInsets(top: 2, leading: 2, bottom: 6, trailing: 2))

            InstrumentControls.section("APPLICATION")
            InstrumentAction("PRIVACY POLICY", "Open Sundial's privacy policy") {
                openURL(Self.privacyPolicyURL)
            }
        }
        .padding(EdgeInsets(top: 20, leading: 22, bottom: 18, trailing: 18))
    }

    /// In place of Android's "15-MIN CELESTIAL WALLPAPER" and "APPLY TO LOCK SCREEN" switches.
    /// The Home Screen steps follow the running system: iOS and iPadOS 18 add widgets through
    /// Edit → Add Widget, 17 through the + button of the jiggling Home Screen.
    static var widgetsNote: String {
        let homeSteps: String
        if #available(iOS 18.0, *) {
            homeSteps = "Touch and hold the Home Screen, tap Edit, then Add Widget, and choose Sundial. "
        } else {
            homeSteps = "Touch and hold the Home Screen until the apps jiggle, tap + at the top left, and choose Sundial. "
        }
        return "iOS keeps the wallpaper for itself, so Sundial comes to the Home Screen and Lock Screen as widgets. " +
            homeSteps +
            "For the Lock Screen, touch and hold it, tap Customize, then Lock Screen, and add Sundial. " +
            "Widgets redraw every 15 minutes in the aesthetic and astrology chosen here."
    }
}
