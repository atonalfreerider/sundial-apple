// Renders an Instrument into a CGImage: what the widgets show (iOS cannot set wallpapers, so the
// Android celestial wallpaper becomes Home and Lock Screen widgets, and the Wear OS watch face
// becomes complications), and a still for previews. Works on iOS and watchOS, from any thread, as
// long as each Instrument is used from one thread at a time.
//
// In SwiftUI: Image(decorative: cgImage, scale: scale).

import CoreGraphics
import Foundation
import SundialCoreGraphics
import SundialRender

nonisolated public enum InstrumentImage {
    /// A bitmap [size] points big at [scale] pixels per point, handed to [draw] as a CGCanvas whose
    /// user space is y-down with its origin at the top left, as CGCanvas expects, in canvas units
    /// of 1 / [unitsPerPoint] point. Pass the Instrument's density as [unitsPerPoint].
    ///
    /// Draw widget instruments with density equal to [scale] (so the canvas is in pixels, as
    /// Android's wallpaper draws). Core Graphics sets a bitmap's shadows in its pixels, whatever
    /// the transform, and the canvas is told so (shadowsInDeviceSpace), so the labels' halos come
    /// out at their Android size (Skia's radius-to-sigma conversion) at any density; an instrument
    /// in points (density 1) works too.
    ///
    /// [opaque] makes an image without alpha, on black (the instrument fills its background
    /// anyway); otherwise the bitmap starts transparent.
    public static func render(size: CGSize, scale: CGFloat, unitsPerPoint: CGFloat = 1, opaque: Bool = true,
                              _ draw: (CGCanvas) -> Void) -> CGImage? {
        guard scale > 0, unitsPerPoint > 0, size.width > 0, size.height > 0 else { return nil }
        let pixelWidth = Int((size.width * scale).rounded())
        let pixelHeight = Int((size.height * scale).rounded())
        guard pixelWidth > 0, pixelHeight > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        // Alpha first, 32-bit little-endian: the native BGRA layout of Apple's GPUs and displays.
        let alpha = opaque ? CGImageAlphaInfo.noneSkipFirst : CGImageAlphaInfo.premultipliedFirst
        guard let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: alpha.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        if opaque {
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(bounds)
        } else {
            context.clear(bounds)
        }
        // A bitmap context's user space is y-up in pixels with the origin at the bottom left. Move
        // the origin to the top left, flip y and scale to canvas units.
        let pixelsPerUnit = scale / unitsPerPoint
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: pixelsPerUnit, y: -pixelsPerUnit)
        context.interpolationQuality = .high
        // The device space is already pixels, so the display scale is the context's own.
        let canvas = CGCanvas(context: context,
                              width: Double(CGFloat(pixelWidth) / pixelsPerUnit),
                              height: Double(CGFloat(pixelHeight) / pixelsPerUnit),
                              displayScale: Double(pixelsPerUnit), shadowsInDeviceSpace: true)
        draw(canvas)
        return context.makeImage()
    }

    /// The instrument as Android's wallpaper draws it: the view at [instant] without interactive
    /// chrome (a horoscope card still shows when astrology is on, on a phone layout). This puts
    /// the Instrument in wallpaper mode for good, so keep one Instrument for images.
    public static func wallpaper(_ instrument: Instrument, size: CGSize, scale: CGFloat, instant: Date,
                                 state: Instrument.ViewState = .heliocentric, opaque: Bool = true) -> CGImage? {
        render(size: size, scale: scale, unitsPerPoint: CGFloat(instrument.density), opaque: opaque) { canvas in
            instrument.drawWallpaper(canvas, instant: instant, state: state)
        }
    }

    /// One frame of the live instrument, chrome and all, as InstrumentView would draw it now
    /// (previews, store art).
    public static func snapshot(_ instrument: Instrument, size: CGSize, scale: CGFloat,
                                opaque: Bool = true) -> CGImage? {
        render(size: size, scale: scale, unitsPerPoint: CGFloat(instrument.density), opaque: opaque) { canvas in
            instrument.draw(canvas)
        }
    }
}
