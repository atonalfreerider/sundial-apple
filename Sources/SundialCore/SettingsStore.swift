import Foundation

/// The Android apps' saved settings, on UserDefaults instead of SharedPreferences: the phone's
/// CelestialStylePreferences and ZodiacPreferences and the watch's WatchPreferences, with the same
/// keys, defaults and behaviour. The apps pass their App Group suite
/// (`UserDefaults(suiteName: "group.com.metavirtuoso.sundial")`): on the iPhone it is shared by
/// the app and its widgets, and separately, on the Watch, by the watch app and its complications.
/// The two devices' suites are not synced, so, as on Wear OS, the watch keeps its own settings
/// (sharing the phone's would need WatchConnectivity, a feature the Android app does not have).
///
/// Each Android preferences file becomes a key prefix, since one suite holds them all: key
/// `birth_date` of file `zodiac_profile` is stored as "zodiac_profile.birth_date". Values are
/// written as Android writes them: dates as yyyy-MM-dd, times as HH:mm (HH:mm:ss with seconds) and
/// enums by their Kotlin names ("BRASS_WATCH", "PISCES", "GALACTIC").
///
/// UserDefaults is thread-safe, so the store and its parts may be shared across threads.
public struct SettingsStore: @unchecked Sendable {
    public let defaults: UserDefaults
    /// CelestialStylePreferences: the chosen aesthetic.
    public let celestialStyle: CelestialStylePreferences
    /// ZodiacPreferences: the astrology profile, the day's horoscope and reported readings.
    public let zodiac: ZodiacPreferences
    /// WatchPreferences: watch-only settings.
    public let watch: WatchPreferences

    public init(_ defaults: UserDefaults) {
        self.defaults = defaults
        celestialStyle = CelestialStylePreferences(defaults)
        zodiac = ZodiacPreferences(defaults)
        watch = WatchPreferences(defaults)
    }
}

/// One SharedPreferences file in a UserDefaults suite, with the SharedPreferences calls the Kotlin
/// uses, so the ported code reads line for line.
struct SharedPreferences {
    let defaults: UserDefaults
    let name: String

    init(_ defaults: UserDefaults, _ name: String) {
        self.defaults = defaults
        self.name = name
    }

    private func key(_ key: String) -> String { name + "." + key }

    func getString(_ key: String, _ defValue: String?) -> String? {
        defaults.string(forKey: self.key(key)) ?? defValue
    }

    func getInt(_ key: String, _ defValue: Int) -> Int {
        defaults.object(forKey: self.key(key)) == nil ? defValue : defaults.integer(forKey: self.key(key))
    }

    func getBoolean(_ key: String, _ defValue: Bool) -> Bool {
        defaults.object(forKey: self.key(key)) == nil ? defValue : defaults.bool(forKey: self.key(key))
    }

    /// As Editor.putString, a nil value removes the key.
    func putString(_ key: String, _ value: String?) {
        if let value {
            defaults.set(value, forKey: self.key(key))
        } else {
            defaults.removeObject(forKey: self.key(key))
        }
    }

    func putInt(_ key: String, _ value: Int) { defaults.set(value, forKey: self.key(key)) }

    func putBoolean(_ key: String, _ value: Bool) { defaults.set(value, forKey: self.key(key)) }

    func remove(_ key: String) { defaults.removeObject(forKey: self.key(key)) }
}

// MARK: - CelestialStylePreferences (ui/CelestialStyle.kt)

public struct CelestialStylePreferences: @unchecked Sendable {
    private static let preferences = "celestial_appearance"
    private static let backgroundStyle = "background_style"

    private let values: SharedPreferences

    init(_ defaults: UserDefaults) { values = SharedPreferences(defaults, CelestialStylePreferences.preferences) }

    public func get() -> CelestialStyle {
        let stored = values.getString(Self.backgroundStyle, nil)
        return CelestialStyle.allCases.first { $0.name == stored } ?? .voidBlack
    }

    public func set(_ style: CelestialStyle) {
        values.putString(Self.backgroundStyle, style.name)
    }
}

// MARK: - ZodiacPreferences (ui/ZodiacPreferences.kt)

public struct ZodiacPreferences: @unchecked Sendable {
    private static let prefs = "zodiac_profile"
    private static let enabled = "enabled"
    private static let optInVersion = "opt_in_version"
    private static let birthDate = "birth_date"
    private static let birthTime = "birth_time"
    private static let sign = "sign"
    private static let horoscope = "horoscope"
    private static let horoscopeSignature = "horoscope_signature"
    private static let horoscopeDate = "horoscope_date"
    private static let reportedDate = "reported_date"

    private let values: SharedPreferences

    init(_ defaults: UserDefaults) { values = SharedPreferences(defaults, ZodiacPreferences.prefs) }

    /// The saved profile. Astrology is opt-in: a profile saved before the opt-in (version 1) comes
    /// back disabled, and is marked as migrated.
    public func get() -> ZodiacProfile {
        let enabled = values.getInt(Self.optInVersion, 0) >= 1 && values.getBoolean(Self.enabled, false)
        if values.getInt(Self.optInVersion, 0) < 1 {
            values.putInt(Self.optInVersion, 1)
            values.putBoolean(Self.enabled, false)
        }
        return ZodiacProfile(
            enabled: enabled,
            // LocalDate::parse and LocalTime::parse throw on text they cannot read; these give nil.
            birthDate: values.getString(Self.birthDate, nil).flatMap(LocalDate.parse),
            birthTime: values.getString(Self.birthTime, nil).flatMap(LocalTime.parse),
            selectedSign: values.getString(Self.sign, nil).flatMap { stored in Zodiac.Sign.allCases.first { $0.name == stored } }
        )
    }

    /// Saves profile controls without allowing a partial UI update to erase natal data. There is
    /// deliberately no implicit "clear" operation: birthday and time remain until the user replaces
    /// them through their respective editors.
    @discardableResult
    public func set(_ profile: ZodiacProfile) -> ZodiacProfile {
        let existing = get()
        let preserved = ZodiacPreferences.preserveNatalData(profile, existing)
        values.putInt(Self.optInVersion, 1)
        values.putBoolean(Self.enabled, preserved.enabled)
        values.putString(Self.birthDate, preserved.birthDate?.description)
        values.putString(Self.birthTime, preserved.birthTime?.description)
        values.putString(Self.sign, preserved.selectedSign?.name)
        return preserved
    }

    static func preserveNatalData(_ requested: ZodiacProfile, _ stored: ZodiacProfile) -> ZodiacProfile {
        var copy = requested
        copy.birthDate = requested.birthDate ?? stored.birthDate
        copy.birthTime = requested.birthTime ?? stored.birthTime
        return copy
    }

    public func setHoroscope(_ profile: ZodiacProfile, _ date: LocalDate, _ text: String) {
        values.putString(Self.horoscope, text.trim())
        values.putString(Self.horoscopeSignature, profile.signature)
        values.putString(Self.horoscopeDate, date.description)
    }

    /// Hides a reported reading and holds off writing another automatically until tomorrow.
    public func hideReportedHoroscope(_ date: LocalDate) {
        values.remove(Self.horoscope)
        values.putString(Self.reportedDate, date.description)
    }

    public func wasReadingReported(_ date: LocalDate) -> Bool {
        values.getString(Self.reportedDate, nil) == date.description
    }

    public func getCurrentHoroscope(_ profile: ZodiacProfile, _ date: LocalDate) -> String? {
        if values.getString(Self.horoscopeSignature, nil) != profile.signature { return nil }
        if values.getString(Self.horoscopeDate, nil) != date.description { return nil }
        return values.getString(Self.horoscope, nil).flatMap { $0.isNotBlank() ? $0 : nil }
    }
}

// MARK: - WatchPreferences (wear/WatchPreferences.kt)

/// Watch-only settings. The aesthetic and astrology mode use the shared core preferences; the
/// galactic view and "return to now" are one-shot requests the dial picks up when it resumes.
public struct WatchPreferences: @unchecked Sendable {
    private static let preferences = "watch_settings"
    private static let clock = "clock"
    private static let southern = "southern_hemisphere"
    private static let request = "request"

    public enum Request: Int, CaseIterable, Sendable {
        case none, galactic, now

        public var ordinal: Int { rawValue }
        /// The Kotlin constant name ("GALACTIC", Enum.name), as it is stored.
        public var name: String { String(describing: self).uppercased() }
    }

    private let values: SharedPreferences

    init(_ defaults: UserDefaults) { values = SharedPreferences(defaults, WatchPreferences.preferences) }

    public func showClock() -> Bool { values.getBoolean(Self.clock, true) }
    public func setShowClock(_ value: Bool) { values.putBoolean(Self.clock, value) }

    public func southern() -> Bool { values.getBoolean(Self.southern, false) }
    public func setSouthern(_ value: Bool) { values.putBoolean(Self.southern, value) }

    public func request(_ value: Request) { values.putString(Self.request, value.name) }

    public func consumeRequest() -> Request {
        let value = values.getString(Self.request, nil)
            .flatMap { stored in Request.allCases.first { $0.name == stored } } ?? Request.none
        if value != Request.none { values.remove(Self.request) }
        return value
    }
}
