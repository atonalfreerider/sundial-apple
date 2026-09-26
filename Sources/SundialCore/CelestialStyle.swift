import Foundation

/// Aesthetics shared by the app and its wallpapers. Sky styles draw a luminous instrument on a
/// night sky; [brassFace] engraves it into a polished brass watch face instead, with dark
/// [instrumentColor] ink on the metal and a light [chromeColor] for anything drawn off the face.
///
/// The saved choice (CelestialStylePreferences on Android) is in SettingsStore.
public enum CelestialStyle: Int, CaseIterable, Sendable {
    case voidBlack
    case crimsonNebula
    case deepSpaceBlue
    case cosmicViolet
    case solarBronze
    case brassWatch

    public var ordinal: Int { rawValue }

    /// The Kotlin constant name ("BRASS_WATCH", Enum.name), as Android stores the choice.
    public var name: String {
        switch self {
        case .voidBlack: return "VOID_BLACK"
        case .crimsonNebula: return "CRIMSON_NEBULA"
        case .deepSpaceBlue: return "DEEP_SPACE_BLUE"
        case .cosmicViolet: return "COSMIC_VIOLET"
        case .solarBronze: return "SOLAR_BRONZE"
        case .brassWatch: return "BRASS_WATCH"
        }
    }

    public var displayName: String { properties.displayName }
    public var baseColor: ARGB { properties.baseColor }
    public var haloColor: ARGB { properties.haloColor }
    public var accentColor: ARGB { properties.accentColor }
    public var instrumentColor: ARGB { properties.instrumentColor }
    public var chromeColor: ARGB { properties.chromeColor }
    public var brassFace: Bool { properties.brassFace }

    private var properties: Properties {
        switch self {
        case .voidBlack: return Properties("Void Black", 0xFF01_0101, 0xFF17_130D, 0xFFFF_D37A, 0xFFF2_EFE7)
        case .crimsonNebula: return Properties("Crimson Nebula", 0xFF27_030B, 0xFF78_152B, 0xFFFF_A27B, 0xFFFF_E5DE)
        case .deepSpaceBlue: return Properties("Deep Space Blue", 0xFF03_1027, 0xFF15_5284, 0xFF8E_D9FF, 0xFFE2_F3FF)
        case .cosmicViolet: return Properties("Cosmic Violet", 0xFF17_0628, 0xFF60_298A, 0xFFD7_A4FF, 0xFFF3_E5FF)
        case .solarBronze: return Properties("Solar Bronze", 0xFF25_1204, 0xFF75_4313, 0xFFFF_C96B, 0xFFFF_EFD0)
        case .brassWatch:
            return Properties(
                "Brass Watch",
                0xFF0B_0A09, // baseColor
                0xFF2C_2822, // haloColor
                0xFF8A_6526, // accentColor
                0xFF3A_2710, // instrumentColor
                chromeColor: 0xFFEB_D393,
                brassFace: true
            )
        }
    }

    /// The Kotlin enum's constructor, with its defaults: chromeColor = instrumentColor, brassFace = false.
    private struct Properties {
        let displayName: String
        let baseColor: ARGB
        let haloColor: ARGB
        let accentColor: ARGB
        let instrumentColor: ARGB
        let chromeColor: ARGB
        let brassFace: Bool

        init(_ displayName: String, _ baseColor: ARGB, _ haloColor: ARGB, _ accentColor: ARGB,
             _ instrumentColor: ARGB, chromeColor: ARGB? = nil, brassFace: Bool = false) {
            self.displayName = displayName
            self.baseColor = baseColor
            self.haloColor = haloColor
            self.accentColor = accentColor
            self.instrumentColor = instrumentColor
            self.chromeColor = chromeColor ?? instrumentColor
            self.brassFace = brassFace
        }
    }
}
