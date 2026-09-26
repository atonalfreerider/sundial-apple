import Foundation

/// Sends a flagged horoscope to the developer from inside the app, as the app stores' AI-generated
/// content policies require. Reports go to [reportEndpoint] as a form post, so a Google Form's
/// `formResponse` URL works; [reportFields] renames the fields (`reason=entry.123,reading=entry.456,...`)
/// to match it.
///
/// This is the network-free part of the Android ReadingReporter: its configuration, the request
/// send() makes and the form body it posts. The apps post it with URLSession.
public enum ReadingReporter {
    public enum Reason: Int, CaseIterable, Sendable {
        case offensive, harmful, sexual, misleading, other

        public var ordinal: Int { rawValue }

        public var label: String {
            switch self {
            case .offensive: return "Offensive or hateful"
            case .harmful: return "Harmful or dangerous advice"
            case .sexual: return "Sexual or explicit"
            case .misleading: return "Presented as fact or misleading"
            case .other: return "Something else"
            }
        }
    }

    public struct Report: Hashable, Sendable {
        public let reason: Reason
        public let reading: String
        public let date: LocalDate

        public init(_ reason: Reason, _ reading: String, _ date: LocalDate) {
            self.reason = reason
            self.reading = reading
            self.date = date
        }
    }

    /// BuildConfig.REPORT_ENDPOINT: sundial.reportEndpoint in the Android gradle.properties.
    public static let reportEndpoint =
        "https://docs.google.com/forms/d/e/1FAIpQLSfJ2K6I3d5i0zcD7JO_CKLLiJtLu_LiGz1nx62bCsRNZ4O2nA/formResponse"

    /// BuildConfig.REPORT_FIELDS: sundial.reportFields in the Android gradle.properties.
    public static let reportFields =
        "reason=entry.742829122,reading=entry.149455074,date=entry.1432046920,version=entry.1693543655"

    public static var isConfigured: Bool { reportEndpoint.isNotBlank() }

    // The request send() makes: a form POST that gives up after 10 s to connect and 10 s to read,
    // and counts any status from 200 to 399 as accepted.
    public static let requestMethod = "POST"
    public static let contentType = "application/x-www-form-urlencoded; charset=utf-8"
    public static let connectTimeout: TimeInterval = 10
    public static let readTimeout: TimeInterval = 10
    public static let acceptedStatusCodes = 200...399

    /// The body send() posts, UTF-8 encoded. [version] is the app's "versionName (versionCode)";
    /// [fields] renames the keys (fieldNames() of [reportFields] by default).
    public static func formBody(_ report: Report, version: String, fields: [String: String] = fieldNames()) -> String {
        let body: KeyValuePairs = [
            "reason": report.reason.label,
            "reading": report.reading,
            "date": report.date.description,
            "version": version,
        ]
        return body.map { key, value in
            "\(encode(fields[key] ?? key))=\(encode(value))"
        }.joined(separator: "&")
    }

    public static func fieldNames(spec: String = reportFields) -> [String: String] {
        var result: [String: String] = [:]
        for pair in spec.split(",") {
            let parts = pair.split("=", limit: 2).map { $0.trim() }
            guard parts.count == 2 else { continue }
            let (key, value) = (parts[0], parts[1])
            if key.isEmpty || value.isEmpty { continue }
            result[key] = value // toMap(): a repeated key's last value wins
        }
        return result
    }

    /// URLEncoder.encode(s, "UTF-8"): A–Z a–z 0–9 . - * _ stay, a space becomes +, and every other
    /// byte of the UTF-8 becomes %XX in upper-case hex.
    static func encode(_ text: String) -> String {
        let hex = Array("0123456789ABCDEF")
        var out = ""
        for byte in text.utf8 {
            switch byte {
            case 0x41...0x5A, 0x61...0x7A, 0x30...0x39, 0x2E, 0x2D, 0x2A, 0x5F:
                out.append(Character(Unicode.Scalar(byte)))
            case 0x20:
                out.append("+")
            default:
                out.append("%")
                out.append(hex[Int(byte >> 4)])
                out.append(hex[Int(byte & 0x0F)])
            }
        }
        return out
    }
}
