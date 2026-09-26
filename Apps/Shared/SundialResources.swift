// What every Sundial target shares from its bundle and its App Group: the label font, the Earth
// texture and the settings. Compiled into the iOS app, its widgets, the watch app and the watch's
// widgets; each of them bundles sundial_condensed.ttf (Sundial Condensed, an Archivo instance
// under the SIL Open Font License 1.1, with sundial-condensed-OFL.txt) and (if it draws the globe)
// earth_texture.png, and has the App Group entitlement.
//
// The Android apps read the same things from their resources (R.font.sundial_condensed,
// R.drawable.earth_texture) and SharedPreferences.

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import SundialCoreGraphics
import SundialRender

// `nonisolated` keeps these usable from widget timeline providers (which run off the main thread)
// whatever the targets' default actor isolation is.
nonisolated public enum SundialResources {
    /// The App Group every target joins: the app and its widgets share one set of settings on the
    /// iPhone or iPad, and the watch app and its complications share another on the watch (not
    /// synced).
    public static let appGroup = "group.com.metavirtuoso.sundial"

    /// sundial_condensed.ttf in each target's bundle: the label face, FontFace.sundialCondensed.
    public static let condensedFontResource = "sundial_condensed"
    /// earth_texture.png in each target's bundle that draws the globe.
    public static let earthTextureResource = "earth_texture"

    /// The label face's PostScript name (Sundial Condensed's is "SundialCondensed"), for SwiftUI's
    /// `Font.custom(_:size:)` in the panels once `registerFonts()` has run.
    public static var condensedPostScriptName: String { FontLibrary.condensedPostScriptName }

    // MARK: Settings

    private static let store = SettingsStore(UserDefaults(suiteName: appGroup) ?? .standard)

    /// The shared settings (CelestialStylePreferences, ZodiacPreferences and WatchPreferences on
    /// Android), on the App Group's UserDefaults suite, or on the standard defaults if the suite
    /// cannot be opened.
    public static func settings() -> SettingsStore { store }

    // MARK: Fonts

    /// Registers sundial_condensed.ttf from the main bundle for this process, once, and says
    /// whether the label face is available. Safe to call any number of times, from any thread.
    /// SundialCoreGraphics' FontLibrary finds it by PostScript name, and SwiftUI can use it through
    /// `Font.custom(SundialResources.condensedPostScriptName, size:)`.
    @discardableResult
    public static func registerFonts() -> Bool { condensedAvailable }

    /// A static's initializer runs once, thread-safely, which makes the registration idempotent.
    private static let condensedAvailable: Bool = {
        let name = FontLibrary.condensedPostScriptName
        if let url = Bundle.main.url(forResource: condensedFontResource, withExtension: "ttf") {
            var error: Unmanaged<CFError>?
            // Fails harmlessly when the font is already registered (listed in UIAppFonts, or
            // FontLibrary got there first); the error is released either way.
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                _ = error?.takeRetainedValue()
            }
        }
        // CTFontCreateWithName quietly substitutes another font for a name it cannot find.
        let probe = CTFontCreateWithName(name as CFString, 12, nil)
        return (CTFontCopyPostScriptName(probe) as String) == name
    }()

    // MARK: Earth texture

    private static let textures = TextureCache()

    /// The equirectangular satellite map (earth_texture.png) as the straight-ARGB PixelImage the
    /// Instrument samples, decoded once per size and then shared. [downsampled] halves it in each
    /// direction, as Android decodes it on Wear OS (BitmapFactory's inSampleSize = 2): the watch
    /// and the widgets use it to keep memory down.
    ///
    /// If the texture is missing from the bundle (a packaging mistake) this asserts in debug
    /// builds and returns a plain dark ocean, so the instrument still draws.
    public static func earthTexture(downsampled: Bool) -> PixelImage {
        textures.image(downsampled) {
            if let image = loadEarthTexture(downsampled: downsampled) { return image }
            assertionFailure("\(earthTextureResource).png is missing or unreadable in \(Bundle.main.bundlePath)")
            return PixelImage(width: 2, height: 1, pixels: [0xFF0A_1A2E, 0xFF0A_1A2E])
        }
    }

    /// Decodes earth_texture.png from [bundle] with ImageIO, uncached; nil if it cannot be read.
    public static func loadEarthTexture(downsampled: Bool, bundle: Bundle = .main) -> PixelImage? {
        guard let url = bundle.url(forResource: earthTextureResource, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let sourceWidth = properties?[kCGImagePropertyPixelWidth] as? Int
        let sourceHeight = properties?[kCGImagePropertyPixelHeight] as? Int

        if downsampled, let sourceWidth, let sourceHeight, sourceWidth > 0, sourceHeight > 0 {
            // Skia's sampled size: each dimension divided by the sample size, rounding down, and
            // never below one pixel.
            let width = sourceWidth >= 2 ? sourceWidth / 2 : 1
            let height = sourceHeight >= 2 ? sourceHeight / 2 : 1
            // ImageIO scales while it decodes, so the full-size map never sits in memory. (Android
            // point-samples every other pixel; ImageIO filters, which differs only in fine detail.)
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: max(width, height),
                kCGImageSourceCreateThumbnailWithTransform: false,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            // Drawn into exactly the sampled size, in case ImageIO rounded a side differently.
            return pixelImage(thumbnail, width: width, height: height)
        }

        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        if downsampled {
            // No size in the properties: decode in full and let Core Graphics halve it.
            return pixelImage(image, width: image.width >= 2 ? image.width / 2 : 1,
                              height: image.height >= 2 ? image.height / 2 : 1)
        }
        return pixelImage(image, width: image.width, height: image.height)
    }

    /// Draws [image] into a [width] × [height] sRGB bitmap and returns its pixels as straight
    /// 0xAARRGGBB words, row 0 at the top, as PixelImage holds them.
    ///
    /// Core Graphics only draws into premultiplied (or alpha-less) bitmaps. With alpha first and
    /// 32-bit little-endian byte order, each pixel read as a native UInt32 on every Apple device is
    /// 0xAARRGGBB, premultiplied; opaque pixels (the whole texture) are already straight, and any
    /// others are divided back out.
    public static func pixelImage(_ image: CGImage, width: Int, height: Int) -> PixelImage? {
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixels = [ARGB](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ) else { return false }
            context.setBlendMode(.copy)
            context.interpolationQuality = .high
            // A bitmap context's first row in memory is the top of what is drawn into it, so the
            // image lands right side up with no flip.
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        for index in pixels.indices where pixels[index] >> 24 != 0xFF {
            pixels[index] = unpremultiplied(pixels[index])
        }
        return PixelImage(width: width, height: height, pixels: pixels)
    }

    private static func unpremultiplied(_ pixel: ARGB) -> ARGB {
        let alpha = pixel >> 24
        guard alpha != 0 else { return 0 }
        func channel(_ shift: ARGB) -> ARGB {
            min(255, (((pixel >> shift) & 0xFF) * 255 + alpha / 2) / alpha) << shift
        }
        return alpha << 24 | channel(16) | channel(8) | channel(0)
    }

    // MARK: Instrument

    /// An Instrument set up as Android's SundialView sets itself up: the saved style, the saved
    /// astrology profile and today's horoscope for it, the device's zone, and the Earth texture
    /// (downsampled on a watch unless [downsampledTexture] says otherwise; widgets pass true).
    ///
    /// [density] is canvas units per point: 1 for a SwiftUI Canvas (InstrumentView), the image's
    /// scale for a bitmap (InstrumentImage), as Android's wallpaper draws in pixels.
    /// ZodiacPreferences.get() migrates a pre-opt-in profile on first read, as on Android.
    public static func makeInstrument(layout: InstrumentLayout = .phone, density: Double = 1,
                                      downsampledTexture: Bool? = nil,
                                      settings: SettingsStore = SundialResources.settings(),
                                      now: Date = Date()) -> Instrument {
        registerFonts()
        let zone = TimeZone.current
        let profile = settings.zodiac.get()
        let horoscope = settings.zodiac.getCurrentHoroscope(profile, LocalDate.of(now, zone))
        return Instrument(layout: layout, density: density,
                          earthTexture: earthTexture(downsampled: downsampledTexture ?? layout.isWatch),
                          style: settings.celestialStyle.get(), zodiacProfile: profile, horoscope: horoscope,
                          // Follows the device's zone as it changes, as ZoneId.systemDefault() does.
                          zone: .autoupdatingCurrent, now: now)
    }
}

/// The decoded textures, one per size, shared by every Instrument in the process.
nonisolated private final class TextureCache: @unchecked Sendable {
    private let lock = NSLock()
    private var images: [Bool: PixelImage] = [:]

    func image(_ downsampled: Bool, _ make: () -> PixelImage) -> PixelImage {
        lock.lock()
        defer { lock.unlock() }
        if let image = images[downsampled] { return image }
        let image = make()
        images[downsampled] = image
        return image
    }
}
