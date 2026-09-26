import Foundation

// The Android app's ui/BirthDateInput.kt (BirthDateInput and BirthTimeInput), UI-free. Kotlin's
// trim() and toIntOrNull() are kept exactly (KotlinSemantics.swift), so the same text is accepted
// or rejected with the same message.

/// Why a birth date or time was rejected: the IllegalArgumentException message the Android panel
/// shows under the fields.
public struct BirthInputError: Error, Equatable, LocalizedError {
    public let message: String

    public init(_ message: String) { self.message = message }

    public var errorDescription: String? { message }
}

/// Strict direct-entry parsing for a human birthday, including Gregorian leap-year validation.
public enum BirthDateInput {
    /// [today] defaults to LocalDate.now(): today in the device's zone.
    public static func parse(_ month: String, _ day: String, _ year: String,
                             today: LocalDate = LocalDate.of(Date(), TimeZone.current)) throws -> LocalDate {
        guard year.trim().utf16.count == 4 else { throw BirthInputError("Enter a 4-digit birth year") }
        guard let monthNumber = month.trim().toIntOrNull() else { throw BirthInputError("Enter a numeric month") }
        guard let dayNumber = day.trim().toIntOrNull() else { throw BirthInputError("Enter a numeric day") }
        guard let yearNumber = year.trim().toIntOrNull() else { throw BirthInputError("Enter a numeric year") }
        // LocalDate.of throws DateTimeException for an impossible date; CivilTime's LocalDate traps.
        guard (-999_999_999...999_999_999).contains(yearNumber), (1...12).contains(monthNumber),
              dayNumber >= 1, dayNumber <= LocalDate.lengthOfMonth(yearNumber, monthNumber) else {
            throw BirthInputError("Enter a valid calendar date")
        }
        let date = LocalDate(yearNumber, monthNumber, dayNumber)
        guard !(date > today) else { throw BirthInputError("Birth date cannot be in the future") }
        return date
    }
}

/// Strict direct-entry parsing for a 12-hour birth time.
public enum BirthTimeInput {
    public static func parse(_ hour: String, _ minute: String, _ pm: Bool) throws -> LocalTime {
        guard let hourNumber = hour.trim().toIntOrNull() else { throw BirthInputError("Enter a numeric hour") }
        guard let minuteNumber = minute.trim().toIntOrNull() else { throw BirthInputError("Enter numeric minutes") }
        guard (1...12).contains(hourNumber) else { throw BirthInputError("Hour must be 1 to 12") }
        guard (0...59).contains(minuteNumber) else { throw BirthInputError("Minutes must be 00 to 59") }
        return LocalTime(hourNumber % 12 + (pm ? 12 : 0), minuteNumber)
    }
}
