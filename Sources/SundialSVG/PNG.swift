import CZlib
import Foundation
import SundialRender

// A small PNG codec for the SVG backend: it reads the app's assets (the Earth texture, the icon)
// into PixelImages and writes PixelImages back out as PNG for SVG <image> elements. It covers
// what those need: 8-bit greyscale, grey + alpha, RGB, RGBA and palette images, not interlaced,
// with zlib (the system library) for inflate and deflate.

public enum PNG {
    public enum Error: Swift.Error, Equatable {
        case notPNG
        case unsupported(String)
        case corrupt(String)
    }

    private static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    // MARK: Decoding

    public static func decode(contentsOf url: URL) throws -> PixelImage {
        try decode(Data(contentsOf: url))
    }

    /// Decodes an 8-bit, non-interlaced PNG to straight (not premultiplied) ARGB pixels.
    public static func decode(_ data: Data) throws -> PixelImage {
        let bytes = [UInt8](data)
        guard bytes.count >= 8, Array(bytes[0..<8]) == signature else { throw Error.notPNG }

        var width = 0, height = 0, bitDepth = 0, colorType = -1, interlace = 0
        var palette: [ARGB] = []
        var transparency: [UInt8] = []
        var compressed: [UInt8] = []
        var offset = 8
        var sawHeader = false
        chunks: while offset + 8 <= bytes.count {
            let length = Int(readUInt32(bytes, offset))
            let type = String(decoding: bytes[(offset + 4)..<(offset + 8)], as: UTF8.self)
            let start = offset + 8
            guard length >= 0, start + length + 4 <= bytes.count else { throw Error.corrupt("chunk \(type) runs past the end") }
            let body = bytes[start..<(start + length)]
            switch type {
            case "IHDR":
                guard length >= 13 else { throw Error.corrupt("short IHDR") }
                width = Int(readUInt32(bytes, start))
                height = Int(readUInt32(bytes, start + 4))
                bitDepth = Int(bytes[start + 8])
                colorType = Int(bytes[start + 9])
                interlace = Int(bytes[start + 12])
                guard bytes[start + 10] == 0, bytes[start + 11] == 0 else { throw Error.unsupported("compression or filter method") }
                sawHeader = true
            case "PLTE":
                palette = stride(from: body.startIndex, to: body.endIndex - 2, by: 3).map {
                    Colors.argb(255, Int(bytes[$0]), Int(bytes[$0 + 1]), Int(bytes[$0 + 2]))
                }
            case "tRNS":
                transparency = Array(body)
            case "IDAT":
                compressed.append(contentsOf: body)
            case "IEND":
                break chunks
            default:
                break
            }
            offset = start + length + 4
        }
        guard sawHeader, width > 0, height > 0 else { throw Error.corrupt("no image header") }
        guard bitDepth == 8 else { throw Error.unsupported("bit depth \(bitDepth)") }
        guard interlace == 0 else { throw Error.unsupported("interlaced images") }
        let channels: Int
        switch colorType {
        case 0: channels = 1
        case 2: channels = 3
        case 3: channels = 1
        case 4: channels = 2
        case 6: channels = 4
        default: throw Error.unsupported("colour type \(colorType)")
        }
        if colorType == 3 && palette.isEmpty { throw Error.corrupt("palette image without PLTE") }

        let rowBytes = width * channels
        let expected = height * (rowBytes + 1)
        var raw = [UInt8](repeating: 0, count: expected)
        var rawLength = uLongf(expected)
        let status = compressed.withUnsafeBufferPointer { source in
            raw.withUnsafeMutableBufferPointer { target in
                uncompress(target.baseAddress, &rawLength, source.baseAddress, uLong(source.count))
            }
        }
        guard status == Z_OK, Int(rawLength) == expected else { throw Error.corrupt("zlib status \(status)") }

        try unfilter(&raw, rowBytes: rowBytes, height: height, bytesPerPixel: channels)

        // Palette entries past the tRNS table are opaque; a grey or RGB tRNS names one colour
        // (16-bit samples, of which 8-bit images use the low byte) that is fully transparent.
        if colorType == 3 {
            for (index, alpha) in transparency.prefix(palette.count).enumerated() {
                palette[index] = (palette[index] & 0x00FF_FFFF) | ARGB(alpha) << 24
            }
        }
        let transparentGrey: Int? = colorType == 0 && transparency.count >= 2 ? Int(transparency[1]) : nil
        let transparentRGB: (Int, Int, Int)? = colorType == 2 && transparency.count >= 6
            ? (Int(transparency[1]), Int(transparency[3]), Int(transparency[5])) : nil

        var pixels = [ARGB](repeating: 0, count: width * height)
        for y in 0..<height {
            var i = y * (rowBytes + 1) + 1
            let row = y * width
            for x in 0..<width {
                let pixel: ARGB
                switch colorType {
                case 0:
                    let g = Int(raw[i])
                    pixel = Colors.argb(g == transparentGrey ? 0 : 255, g, g, g)
                case 2:
                    let r = Int(raw[i]), g = Int(raw[i + 1]), b = Int(raw[i + 2])
                    let clear = transparentRGB.map { $0 == (r, g, b) } ?? false
                    pixel = Colors.argb(clear ? 0 : 255, r, g, b)
                case 3:
                    let index = Int(raw[i])
                    guard index < palette.count else { throw Error.corrupt("palette index \(index) out of range") }
                    pixel = palette[index]
                case 4:
                    let g = Int(raw[i])
                    pixel = Colors.argb(Int(raw[i + 1]), g, g, g)
                default:
                    pixel = Colors.argb(Int(raw[i + 3]), Int(raw[i]), Int(raw[i + 1]), Int(raw[i + 2]))
                }
                pixels[row + x] = pixel
                i += channels
            }
        }
        return PixelImage(width: width, height: height, pixels: pixels)
    }

    /// Reverses the per-row filters (None, Sub, Up, Average, Paeth) in place.
    private static func unfilter(_ raw: inout [UInt8], rowBytes: Int, height: Int, bytesPerPixel bpp: Int) throws {
        let stride = rowBytes + 1
        for y in 0..<height {
            let filter = raw[y * stride]
            let row = y * stride + 1
            let previous = y == 0 ? -1 : (y - 1) * stride + 1
            switch filter {
            case 0:
                break
            case 1:
                for x in bpp..<max(bpp, rowBytes) { raw[row + x] &+= raw[row + x - bpp] }
            case 2:
                if previous >= 0 { for x in 0..<rowBytes { raw[row + x] &+= raw[previous + x] } }
            case 3:
                for x in 0..<rowBytes {
                    let left = x >= bpp ? Int(raw[row + x - bpp]) : 0
                    let up = previous >= 0 ? Int(raw[previous + x]) : 0
                    raw[row + x] &+= UInt8((left + up) / 2)
                }
            case 4:
                for x in 0..<rowBytes {
                    let a = x >= bpp ? Int(raw[row + x - bpp]) : 0
                    let b = previous >= 0 ? Int(raw[previous + x]) : 0
                    let c = x >= bpp && previous >= 0 ? Int(raw[previous + x - bpp]) : 0
                    raw[row + x] &+= UInt8(paeth(a, b, c))
                }
            default:
                throw Error.corrupt("filter type \(filter)")
            }
        }
    }

    private static func paeth(_ a: Int, _ b: Int, _ c: Int) -> Int {
        let p = a + b - c
        let pa = abs(p - a), pb = abs(p - b), pc = abs(p - c)
        if pa <= pb && pa <= pc { return a }
        return pb <= pc ? b : c
    }

    private static func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16 | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
    }

    // MARK: Encoding

    /// Encodes [image] as an 8-bit RGBA PNG. Each row takes the filter with the smallest sum of
    /// absolute differences (libpng's heuristic), which keeps rendered spheres and rings small.
    public static func encode(_ image: PixelImage, level: Int32 = 6) -> Data {
        let width = image.width, height = image.height
        let rowBytes = width * 4
        var rgba = [UInt8](repeating: 0, count: rowBytes * height)
        for (index, pixel) in image.pixels.enumerated() {
            let o = index * 4
            rgba[o] = UInt8(truncatingIfNeeded: pixel >> 16)
            rgba[o + 1] = UInt8(truncatingIfNeeded: pixel >> 8)
            rgba[o + 2] = UInt8(truncatingIfNeeded: pixel)
            rgba[o + 3] = UInt8(truncatingIfNeeded: pixel >> 24)
        }

        var filtered = [UInt8](repeating: 0, count: (rowBytes + 1) * height)
        var candidate = [UInt8](repeating: 0, count: rowBytes)
        var best = [UInt8](repeating: 0, count: rowBytes)
        for y in 0..<height {
            let row = y * rowBytes
            let previous = y == 0 ? -1 : (y - 1) * rowBytes
            var bestFilter: UInt8 = 0
            var bestScore = Int.max
            for filter in UInt8(0)...4 {
                var score = 0
                for x in 0..<rowBytes {
                    let value = rgba[row + x]
                    let a = x >= 4 ? Int(rgba[row + x - 4]) : 0
                    let b = previous >= 0 ? Int(rgba[previous + x]) : 0
                    let c = x >= 4 && previous >= 0 ? Int(rgba[previous + x - 4]) : 0
                    let predictor: Int
                    switch filter {
                    case 0: predictor = 0
                    case 1: predictor = a
                    case 2: predictor = b
                    case 3: predictor = (a + b) / 2
                    default: predictor = paeth(a, b, c)
                    }
                    let out = value &- UInt8(truncatingIfNeeded: predictor)
                    candidate[x] = out
                    score += out < 128 ? Int(out) : 256 - Int(out)
                }
                if score < bestScore {
                    bestScore = score
                    bestFilter = filter
                    swap(&best, &candidate)
                }
            }
            let o = y * (rowBytes + 1)
            filtered[o] = bestFilter
            filtered.replaceSubrange((o + 1)..<(o + 1 + rowBytes), with: best)
        }

        var compressedLength = compressBound(uLong(filtered.count))
        var compressed = [UInt8](repeating: 0, count: Int(compressedLength))
        let status = filtered.withUnsafeBufferPointer { source in
            compressed.withUnsafeMutableBufferPointer { target in
                compress2(target.baseAddress, &compressedLength, source.baseAddress, uLong(source.count), level)
            }
        }
        precondition(status == Z_OK, "zlib compress2 failed: \(status)")
        compressed.removeSubrange(Int(compressedLength)...)

        var out = signature
        var header = [UInt8]()
        appendUInt32(&header, UInt32(width))
        appendUInt32(&header, UInt32(height))
        header += [8, 6, 0, 0, 0]
        appendChunk(&out, "IHDR", header)
        appendChunk(&out, "IDAT", compressed)
        appendChunk(&out, "IEND", [])
        return Data(out)
    }

    private static func appendUInt32(_ bytes: inout [UInt8], _ value: UInt32) {
        bytes += [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    private static func appendChunk(_ out: inout [UInt8], _ type: String, _ body: [UInt8]) {
        appendUInt32(&out, UInt32(body.count))
        let typed = Array(type.utf8) + body
        out += typed
        let crc = typed.withUnsafeBufferPointer { crc32(0, $0.baseAddress, uInt($0.count)) }
        appendUInt32(&out, UInt32(truncatingIfNeeded: crc))
    }
}
