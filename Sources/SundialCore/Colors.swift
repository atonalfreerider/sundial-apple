import Foundation

// Colours are packed as 0xAARRGGBB, exactly as Android's colour ints, so the instrument's
// palette ports digit for digit.

/// A colour packed as 0xAARRGGBB, like Android's colour ints.
public typealias ARGB = UInt32

public enum Colors {
    public static func alpha(_ color: ARGB) -> Int { Int(color >> 24) }
    public static func red(_ color: ARGB) -> Int { Int((color >> 16) & 0xFF) }
    public static func green(_ color: ARGB) -> Int { Int((color >> 8) & 0xFF) }
    public static func blue(_ color: ARGB) -> Int { Int(color & 0xFF) }

    /// Components clamped to 0...255.
    public static func argb(_ a: Int, _ r: Int, _ g: Int, _ b: Int) -> ARGB {
        func c(_ v: Int) -> ARGB { ARGB(max(0, min(255, v))) }
        return c(a) << 24 | c(r) << 16 | c(g) << 8 | c(b)
    }

    public static func rgb(_ r: Int, _ g: Int, _ b: Int) -> ARGB { argb(255, r, g, b) }

    public static let white: ARGB = 0xFFFF_FFFF
    public static let black: ARGB = 0xFF00_0000
    public static let transparent: ARGB = 0x0000_0000
}
