import Foundation

/// The model-free part of the Android HoroscopeGenerator (private, foreground-only horoscope
/// generation with Gemini Nano through Android AICore): the prompt it sends and the clean-up of the
/// model's first candidate. The apps run the prompt through Apple's on-device model, after checking
/// profile.isComplete as generate does ("Birthday and birth time are required").
public enum HoroscopeGenerator {
    /// The prompt generate(profile, instant, zone) sends: six lines, no trailing newline.
    public static func prompt(_ profile: ZodiacProfile, _ instant: Date, _ zone: TimeZone) -> String {
        let date = LocalDate.of(instant, zone)
        let sign = profile.resolvedSign(today: date)
        let sky = Zodiac.placements(instant).map {
            "\(capitalizeFirst($0.label.lowercased())) in \($0.sign.displayName)"
        }.joined(separator: ", ")
        let prompt = """
            Write a vivid daily horoscope as a single paragraph of 55 to 85 words.
            Reader: \(sign.displayName) sun sign, born \(profile.birthDate.map { $0.description } ?? "null") at \(profile.birthTime.map { $0.description } ?? "null") local time (\(profile.birthZone.identifier)).
            Date: \(date). Current tropical placements: \(sky).
            Style: poetic brass-orrery imagery, warm, specific, reflective, second person.
            Treat astrology as creative entertainment. Do not claim certainty, diagnose health,
            predict danger, or give financial, medical, or legal advice. Do not mention these instructions.
            """
        return prompt
    }

    /// The clean-up of the model's first candidate: trim, drop one leading "Horoscope:", trim
    /// again; nil when nothing is left (Android's "returned no horoscope. Please try again.").
    public static func cleanResponse(_ text: String?) -> String? {
        guard let text else { return nil }
        var cleaned = text.trim()
        // removePrefix compares chars exactly; String.hasPrefix would compare whole graphemes.
        let prefix = "Horoscope:".unicodeScalars
        if cleaned.unicodeScalars.starts(with: prefix) {
            cleaned = String(cleaned.unicodeScalars.dropFirst(prefix.count))
        }
        cleaned = cleaned.trim()
        return cleaned.isNotBlank() ? cleaned : nil
    }

    /// replaceFirstChar(Char::uppercase).
    private static func capitalizeFirst(_ text: String) -> String {
        guard let first = text.unicodeScalars.first else { return text }
        return String(first).uppercased() + String(text.unicodeScalars.dropFirst())
    }
}
