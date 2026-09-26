import Foundation
import SundialCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Private, foreground-only horoscope generation with Apple's on-device model: the iOS port of the
/// Android HoroscopeGenerator, which used Gemini Nano through AICore. Foundation Models (iOS 26,
/// Apple Intelligence) takes Gemini Nano's place; the prompt and the clean-up of the answer are
/// SundialCore's `HoroscopeGenerator.prompt` and `cleanResponse`, unchanged.
///
/// The service writes nothing down. As MainActivity does, the caller keeps the day's reading in
/// `SettingsStore.zodiac` (`setHoroscope(profile, date, text)`, read back with
/// `getCurrentHoroscope(profile, date)`) and shows the error's `localizedDescription` as the status
/// line when generation fails.
@MainActor
final class HoroscopeService {
    enum Availability: Equatable {
        case available
        /// Why not, in words for the astrology panel's status line.
        case unavailable(String)
    }

    /// A generation failure, with Android's wording where it had one.
    struct Failure: LocalizedError, Equatable {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    /// The status line while a reading is being written (Android's onStatus).
    static let writingStatus = "Writing your private horoscope on device…"
    /// The status line once a reading is written and shown on the instrument.
    static let writtenStatus = "Written privately by Apple Intelligence · displayed on the instrument"

    /// Holds no state, so it can be made anywhere.
    nonisolated init() {}

    /// Whether the on-device model can write a reading now. It can change while the app runs
    /// (Apple Intelligence turned on, the model finishing its download): read it again when the
    /// astrology panel appears or the app becomes active.
    var availability: Availability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return AppleIntelligence.availability()
        }
        #endif
        return .unavailable(HoroscopeMessages.needsNewerSystem)
    }

    /// Writes the reading for [date] (today) for [profile]: generate(profile, Instant.now(),
    /// ZoneId.systemDefault()) in the Android app. Throws a `Failure` when the birth date or time
    /// is missing, when the model is unavailable, or when it returns nothing usable.
    func generate(profile: ZodiacProfile, date: LocalDate) async throws -> String {
        guard profile.isComplete else { throw Failure(HoroscopeMessages.birthDetailsRequired) }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .unavailable(let message) = AppleIntelligence.availability() { throw Failure(message) }
            let zone = TimeZone.current
            let now = Date()
            // The placements are those of this moment, as Android's; a date other than today's
            // (the day turned while the caller was preparing) is read at its noon.
            let instant = LocalDate.of(now, zone) == date ? now : ZonedDateTime.instant(date, LocalTime(12, 0), zone)
            let prompt = HoroscopeGenerator.prompt(profile, instant, zone)
            let text = try await AppleIntelligence.respond(instructions: HoroscopeMessages.instructions, prompt: prompt)
            guard let horoscope = HoroscopeGenerator.cleanResponse(text) else {
                throw Failure(HoroscopeMessages.noHoroscope)
            }
            return horoscope
        }
        #endif
        throw Failure(HoroscopeMessages.needsNewerSystem)
    }
}

/// The service's words. Gemini Nano's messages, with Apple Intelligence in its place.
private nonisolated enum HoroscopeMessages {
    /// Android's require(profile.isComplete) message.
    static let birthDetailsRequired = "Birthday and birth time are required"
    static let needsNewerSystem = "Horoscopes need iOS 26 and Apple Intelligence."
    /// Gemini Nano's "not available on this device configuration".
    static let deviceNotEligible = "Apple Intelligence is not available on this device."
    static let notEnabled = "Turn on Apple Intelligence in Settings to write horoscopes on this device."
    /// Gemini Nano's "still preparing. Try again in a few minutes."
    static let modelNotReady = "Apple Intelligence is still preparing. Try again in a few minutes."
    static let unavailable = "Apple Intelligence is not available right now."
    /// Gemini Nano's "returned no horoscope. Please try again."
    static let noHoroscope = "Apple Intelligence returned no horoscope. Please try again."
    static let declined = "Apple Intelligence declined to write this horoscope. Please try again."
    static let unsupportedLanguage = "Apple Intelligence does not support this device's language yet."
    /// Android's fallback for an error without a message.
    static let failed = "On-device horoscope generation failed"

    /// The session's instructions. Android sent the prompt alone; everything the reading needs,
    /// including its limits, stays in the prompt, and this only asks for the paragraph by itself.
    static let instructions = "You write the daily horoscope shown on Sundial, a brass orrery. Reply with the horoscope paragraph only."
}

#if canImport(FoundationModels)
/// The Foundation Models calls (iOS 26).
@available(iOS 26.0, *)
private nonisolated enum AppleIntelligence {
    static func availability() -> HoroscopeService.Availability {
        let availability = SystemLanguageModel.default.availability
        if case .available = availability { return .available }
        if case .unavailable(let reason) = availability { return .unavailable(message(for: reason)) }
        return .unavailable(HoroscopeMessages.unavailable)
    }

    /// One prompt, one answer: a new session each time, as each Android request stood alone.
    static func respond(instructions: String, prompt: String) async throws -> String {
        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(to: prompt)
            return response.content
        } catch let error as LanguageModelSession.GenerationError {
            throw HoroscopeService.Failure(message(for: error))
        }
    }

    private static func message(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        if case .deviceNotEligible = reason { return HoroscopeMessages.deviceNotEligible }
        if case .appleIntelligenceNotEnabled = reason { return HoroscopeMessages.notEnabled }
        if case .modelNotReady = reason { return HoroscopeMessages.modelNotReady }
        return HoroscopeMessages.unavailable
    }

    private static func message(for error: LanguageModelSession.GenerationError) -> String {
        if case .guardrailViolation = error { return HoroscopeMessages.declined }
        if case .assetsUnavailable = error { return HoroscopeMessages.modelNotReady }
        if case .unsupportedLanguageOrLocale = error { return HoroscopeMessages.unsupportedLanguage }
        let description = error.localizedDescription
        return description.isEmpty ? HoroscopeMessages.failed : description
    }
}
#endif
