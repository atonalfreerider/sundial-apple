import Foundation

// The Android file's ZodiacPreferences object (SharedPreferences) is ported in SettingsStore.swift.

public struct ZodiacProfile: Hashable, Sendable {
    public var enabled: Bool
    public var birthDate: LocalDate?
    public var birthTime: LocalTime?
    public var selectedSign: Zodiac.Sign?

    public init(enabled: Bool = false, birthDate: LocalDate? = nil, birthTime: LocalTime? = nil,
                selectedSign: Zodiac.Sign? = nil) {
        self.enabled = enabled
        self.birthDate = birthDate
        self.birthTime = birthTime
        self.selectedSign = selectedSign
    }

    /// [today] defaults to LocalDate.now(): today in the device's zone.
    public func resolvedSign(today: LocalDate = LocalDate.of(Date(), TimeZone.current)) -> Zodiac.Sign {
        selectedSign ?? birthDate.map(Zodiac.signFor) ?? Zodiac.signFor(today)
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
        ].joined(separator: "|")
    }
}
