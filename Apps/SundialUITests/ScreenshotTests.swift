import UIKit
import XCTest

/// App Store screenshots of the iPhone and iPad app, captured in the simulator. CI
/// (.github/workflows/apple.yml) runs this class on an iPhone 17 Pro Max and an iPad Pro 13-inch,
/// exports the attachments from the result bundles and uploads them as the
/// `app-store-screenshots` artifact. It is the Apple side of Android's StoreAssetsCapture: the
/// Play listing's scenes, with the same sample calendars and reading, frozen at one moment.
///
/// Screenshot mode is switched on by launch arguments, which SundialApp honours. They reach the
/// app through the argument domain, so `UserDefaults.standard.string(forKey: "screenshotScene")`
/// reads them (or scan `ProcessInfo.processInfo.arguments`):
///
///     -screenshotScene <view>-<style>-<zodiac>        required; turns screenshot mode on
///         view    heliocentric | geocentric | galactic       Instrument.ViewState
///         style   void | crimson | blue | violet | bronze | brass
///                 CelestialStyle .voidBlack, .crimsonNebula, .deepSpaceBlue, .cosmicViolet,
///                 .solarBronze, .brassWatch
///         zodiac  astrology | astronomy                      the sample reader's profile and
///                                                            reading, or the zodiac off
///     -screenshotMenu settings | calendars | astrology  optional; that tuck menu open, at rest
///     -screenshotInstant 2026-09-26T03:30:00Z           the moment shown: Friday 25 September
///                                                       2026, 8:30 pm in Los Angeles
///     -screenshotZone America/Los_Angeles               the instrument's zone (TZ is set too)
///
/// In screenshot mode the app calls `Instrument.freezeForCapture(instant:state:style:)` with
/// those values, shows the sample data of StoreAssetsCapture.kt (calendars Personal, Work and
/// Holidays with calendars 1 and 2 selected, its eight events, an Aries born 1990-04-18 at 06:45
/// and its reading) and nothing of the device's own: no permission prompts, no EventKit, no
/// Foundation Models, no network, and nothing saved to settings.
final class ScreenshotTests: XCTestCase {
    /// One store screenshot: a frozen instrument scene and, optionally, an open tuck menu.
    struct Scene {
        let name: String
        let view: String
        let style: String
        let astrology: Bool
        var menu: String? = nil

        /// The -screenshotScene value, e.g. heliocentric-brass-astrology.
        var argument: String { "\(view)-\(style)-\(astrology ? "astrology" : "astronomy")" }
    }

    /// The Play phone set (play/graphics/1-… to 8-…), in the same order.
    static let phoneScenes = [
        Scene(name: "1-solar-view", view: "heliocentric", style: "crimson", astrology: false),
        Scene(name: "2-earth-view", view: "geocentric", style: "crimson", astrology: false),
        Scene(name: "3-brass-astrology", view: "heliocentric", style: "brass", astrology: true),
        Scene(name: "4-brass-earth-view", view: "geocentric", style: "brass", astrology: false),
        Scene(name: "5-galactic", view: "galactic", style: "blue", astrology: false),
        Scene(name: "6-settings", view: "heliocentric", style: "brass", astrology: false, menu: "settings"),
        Scene(name: "7-astrology-menu", view: "heliocentric", style: "void", astrology: true, menu: "astrology"),
        Scene(name: "8-calendars", view: "geocentric", style: "violet", astrology: false, menu: "calendars"),
    ]

    /// The Play tablet set (play/graphics/tablet-1-… to tablet-4-…).
    static let padScenes = [
        Scene(name: "1-brass-astrology", view: "heliocentric", style: "brass", astrology: true),
        Scene(name: "2-earth-view", view: "geocentric", style: "crimson", astrology: false),
        Scene(name: "3-solar-view", view: "heliocentric", style: "blue", astrology: false),
        Scene(name: "4-astrology-menu", view: "heliocentric", style: "void", astrology: true, menu: "astrology"),
    ]

    /// Friday 25 September 2026, 20:30 in Los Angeles (PDT, UTC−7).
    static let instant = "2026-09-26T03:30:00Z"
    static let screenshotZone = "America/Los_Angeles"

    override func setUpWithError() throws {
        // A scene that fails should not cost the others.
        continueAfterFailure = true
    }

    @MainActor
    func testPhoneScreenshots() throws {
        let pad = isPad
        try XCTSkipIf(pad, "The iPhone set is captured on an iPhone simulator")
        XCUIDevice.shared.orientation = .portrait
        for scene in Self.phoneScenes {
            capture(scene)
        }
    }

    @MainActor
    func testPadScreenshots() throws {
        let pad = isPad
        try XCTSkipUnless(pad, "The iPad set is captured on an iPad simulator")
        // Portrait, the 13-inch size App Store Connect lists; and landscape, as the Play tablet
        // listing shows Sundial.
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            for scene in Self.padScenes {
                capture(scene)
            }
        }
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: Capture

    static func launchArguments(_ scene: Scene) -> [String] {
        var arguments = [
            "-screenshotScene", scene.argument,
            "-screenshotInstant", instant,
            "-screenshotZone", screenshotZone,
            // A known language, region and text size, whatever the simulator was set to.
            "-AppleLanguages", "(en-US)",
            "-AppleLocale", "en_US",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL",
        ]
        if let menu = scene.menu {
            arguments += ["-screenshotMenu", menu]
        }
        return arguments
    }

    /// Launches the app in [scene] and attaches the screen as "<device>-<scene name>", e.g.
    /// "iPhone-6.9-3-brass-astrology", which CI turns into the file name.
    @MainActor
    private func capture(_ scene: Scene) {
        let app = XCUIApplication()
        app.launchArguments = Self.launchArguments(scene)
        app.launchEnvironment["TZ"] = Self.screenshotZone
        app.launch()
        guard app.wait(for: .runningForeground, timeout: 60) else {
            XCTFail("\(scene.name): Sundial did not come to the foreground")
            return
        }
        dismissSystemAlert(scene)
        let screenshot = steadyScreenshot()
        let image = Self.storePNG(screenshot.image)
        let attachment = XCTAttachment(data: image.png, uniformTypeIdentifier: "public.png")
        attachment.name = "\(Self.storePrefix(image.width, image.height))-\(scene.name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.terminate()
    }

    /// Waits for the screen to stop changing (the first frames, the globe, a menu unfolding) and
    /// returns it; after [timeout] it settles for the latest frame.
    @MainActor
    private func steadyScreenshot(timeout: TimeInterval = 20) -> XCUIScreenshot {
        pause(2)
        var previous = XCUIScreen.main.screenshot()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            pause(1)
            let current = XCUIScreen.main.screenshot()
            if current.pngRepresentation == previous.pngRepresentation {
                return current
            }
            previous = current
        }
        return previous
    }

    /// Screenshot mode must never ask for a permission. If a system alert shows anyway, fail the
    /// scene and clear the alert so the other scenes are still captured.
    @MainActor
    private func dismissSystemAlert(_ scene: Scene) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: 2) else { return }
        XCTFail("\(scene.name): a system alert appeared in screenshot mode: \(alert.label)")
        for label in ["Don’t Allow", "Don't Allow", "Not Now", "Cancel", "OK"] where alert.buttons[label].exists {
            alert.buttons[label].tap()
            return
        }
    }

    private func pause(_ seconds: TimeInterval) {
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "pause")], timeout: seconds)
    }

    /// iPads are about 4:3 and iPhones about 19.5:9. Measured on the screen rather than asked of
    /// UIDevice, which says .phone when an iPhone-only test runner is shown on an iPad.
    @MainActor
    private var isPad: Bool {
        let size = XCUIScreen.main.screenshot().image.size
        let long = max(size.width, size.height)
        let short = min(size.width, size.height)
        return short > 0 && long / short < 1.6
    }

    // MARK: Store images

    /// The screenshot as an opaque 8-bit sRGB PNG, upright, with its size in pixels. A landscape
    /// capture keeps the portrait framebuffer and records the turn in imageOrientation; drawing
    /// it bakes the turn in, and an opaque format leaves out the alpha channel store screenshots
    /// must not have.
    @MainActor
    static func storePNG(_ image: UIImage) -> (png: Data, width: Int, height: Int) {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        let png = renderer.pngData { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        let width = Int((image.size.width * image.scale).rounded())
        let height = Int((image.size.height * image.scale).rounded())
        return (png, width, height)
    }

    /// The App Store Connect display class of a screenshot this size, as the file name's prefix.
    static func storePrefix(_ width: Int, _ height: Int) -> String {
        switch (width, height) {
        case (1320, 2868): return "iPhone-6.9"
        case (2064, 2752): return "iPad-13"
        case (2752, 2064): return "iPad-13-landscape"
        default:
            let tablet = Double(max(width, height)) < 1.6 * Double(min(width, height))
            return "\(tablet ? "iPad" : "iPhone")-\(width)x\(height)"
        }
    }
}
