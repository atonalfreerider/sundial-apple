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
    case fire
    case earth
    case air
    case water

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
        case .fire: return "FIRE"
        case .earth: return "EARTH"
        case .air: return "AIR"
        case .water: return "WATER"
        }
    }

    public var displayName: String { properties.displayName }
    public var baseColor: ARGB { properties.baseColor }
    public var haloColor: ARGB { properties.haloColor }
    public var accentColor: ARGB { properties.accentColor }
    public var instrumentColor: ARGB { properties.instrumentColor }
    public var chromeColor: ARGB { properties.chromeColor }
    public var brassFace: Bool { properties.brassFace }
    /// Element palettes are selected automatically in astrology mode, not listed in settings.
    public var pickable: Bool { properties.pickable }

    public static var pickableCases: [CelestialStyle] { allCases.filter(\.pickable) }

    public static func forElement(_ element: Zodiac.Element) -> CelestialStyle {
        switch element {
        case .fire: return .fire
        case .earth: return .earth
        case .air: return .air
        case .water: return .water
        }
    }

    /// Brass wins; otherwise astrology uses the reader's element instead of the saved palette.
    public static func effective(_ selected: CelestialStyle, _ profile: ZodiacProfile) -> CelestialStyle {
        if selected.brassFace { return selected }
        return profile.enabled ? forElement(profile.resolvedSign().element) : selected
    }

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
        case .fire: return Properties("Fire", 0xFF2A_0703, 0xFF8C_2A0B, 0xFFFF_B347, 0xFFFF_EBD6, pickable: false)
        case .earth: return Properties("Earth", 0xFF0D_1507, 0xFF3F_5B1F, 0xFFD9_C47C, 0xFFF1_EEDA, pickable: false)
        case .air: return Properties("Air", 0xFF0B_1424, 0xFF58_7DA6, 0xFFE4_F1FF, 0xFFF6_FAFF, pickable: false)
        case .water: return Properties("Water", 0xFF02_1A1F, 0xFF0E_6A73, 0xFF7F_E6DE, 0xFFDD_FAF7, pickable: false)
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
        let pickable: Bool

        init(_ displayName: String, _ baseColor: ARGB, _ haloColor: ARGB, _ accentColor: ARGB,
             _ instrumentColor: ARGB, chromeColor: ARGB? = nil, brassFace: Bool = false,
             pickable: Bool = true) {
            self.displayName = displayName
            self.baseColor = baseColor
            self.haloColor = haloColor
            self.accentColor = accentColor
            self.instrumentColor = instrumentColor
            self.chromeColor = chromeColor ?? instrumentColor
            self.brassFace = brassFace
            self.pickable = pickable
        }
    }
}
