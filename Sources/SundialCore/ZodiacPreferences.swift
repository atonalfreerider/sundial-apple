import Foundation

// The Android file's ZodiacPreferences object (SharedPreferences) is ported in SettingsStore.swift.

public struct ZodiacProfile: Hashable, Sendable {
    public var enabled: Bool
    public var birthDate: LocalDate?
    public var birthTime: LocalTime?
    public var selectedSign: Zodiac.Sign?
    /// IANA identifier for the place where the birth time was observed.
    public var birthZoneId: String?

    public init(enabled: Bool = false, birthDate: LocalDate? = nil, birthTime: LocalTime? = nil,
                selectedSign: Zodiac.Sign? = nil, birthZoneId: String? = nil) {
        self.enabled = enabled
        self.birthDate = birthDate
        self.birthTime = birthTime
        self.selectedSign = selectedSign
        self.birthZoneId = birthZoneId
    }

    /// [today] defaults to LocalDate.now(): today in the device's zone.
    public func resolvedSign(today: LocalDate = LocalDate.of(Date(), TimeZone.current)) -> Zodiac.Sign {
        selectedSign ?? natalSign ?? birthDate.map(Zodiac.signFor) ?? Zodiac.signFor(today)
    }

    public var birthZone: TimeZone {
        birthZoneId.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent
    }

    public var birthInstant: Date? {
        guard let birthDate, let birthTime else { return nil }
        return ZonedDateTime.instant(birthDate, birthTime, birthZone)
    }

    /// True solar longitude settles births on a civil-date cusp once time and zone are known.
    public var natalSign: Zodiac.Sign? {
        birthInstant.map { Zodiac.signForLongitude(Zodiac.sunLongitude($0)) } ?? birthDate.map(Zodiac.signFor)
    }

    public var isComplete: Bool { birthDate != nil && birthTime != nil }

    /// listOf(enabled, birthDate, birthTime, selectedSign).joinToString("|"): each value's Kotlin
    /// toString ("true", "1976-07-04", "07:05", "PISCES"), "null" when absent.
    public var signature: String {
        [
            String(enabled),
            birthDate.map { $0.description } ?? "null",
            birthTime.map { $0.description } ?? "null",
            selectedSign.map { $0.name } ?? "null",
            birthZoneId ?? "null",
        ].joined(separator: "|")
    }
}
