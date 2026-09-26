import Foundation
import SundialCore

/// Sends a flagged horoscope to the developer from inside the app, as the stores' rules for
/// AI-generated content require: the network part of the Android ReadingReporter.send, on
/// URLSession. SundialCore's `ReadingReporter` holds the endpoint, the field names, the request's
/// method, content type and timeouts, and the form body.
///
/// As on Android, the caller hides the reading first (`SettingsStore.zodiac.hideReportedHoroscope`)
/// and then reports it, showing `sentMessage` when this returns and `unsentMessage` when it throws.
nonisolated enum ReadingReportService {
    enum Failure: LocalizedError, Equatable {
        /// ReadingReporter.isConfigured is false, or its endpoint is not a URL.
        case notConfigured
        /// The endpoint answered outside 200–399.
        case rejected(statusCode: Int)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Reporting is not configured in this build."
            case .rejected(let statusCode): return "The report was not accepted (HTTP \(statusCode))."
            }
        }
    }

    /// Android's toasts after the report dialog.
    static let sentMessage = "Thank you — the reading was reported"
    static let unsentMessage = "Reading hidden; the report could not be sent"

    /// The version the report carries, as Android's "versionName (versionCode)":
    /// "CFBundleShortVersionString (CFBundleVersion)".
    static var bundleVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let name = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(name) (\(build))"
    }

    /// Posts the report. [reason] is one of `ReadingReporter.Reason`'s labels ("Offensive or
    /// hateful"…), or its case name; anything else is sent as "Something else". Returns once the
    /// endpoint has accepted the report (any status from 200 to 399, as Android counts it) and
    /// throws otherwise.
    static func submit(reading: String, reason: String, date: LocalDate, appVersion: String) async throws {
        try await submit(reading: reading, reason: reportReason(reason), date: date, appVersion: appVersion)
    }

    /// The same, with the reason as SundialCore's enum.
    static func submit(reading: String, reason: ReadingReporter.Reason, date: LocalDate, appVersion: String) async throws {
        guard ReadingReporter.isConfigured, let url = URL(string: ReadingReporter.reportEndpoint) else {
            throw Failure.notConfigured
        }
        let report = ReadingReporter.Report(reason, reading, date)
        let body = ReadingReporter.formBody(report, version: appVersion)
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: ReadingReporter.readTimeout
        )
        request.httpMethod = ReadingReporter.requestMethod
        request.setValue(ReadingReporter.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard ReadingReporter.acceptedStatusCodes.contains(http.statusCode) else {
            throw Failure.rejected(statusCode: http.statusCode)
        }
    }

    /// The reason a label or case name stands for (label first, then name, ignoring case).
    static func reportReason(_ text: String) -> ReadingReporter.Reason {
        let reasons = ReadingReporter.Reason.allCases
        return reasons.first { $0.label == text }
            ?? reasons.first { $0.label.caseInsensitiveCompare(text) == .orderedSame }
            ?? reasons.first { String(describing: $0).caseInsensitiveCompare(text) == .orderedSame }
            ?? .other
    }

    /// HttpURLConnection's 10 s to connect and 10 s to read: URLSession has no separate connect
    /// timeout, so the request gives up after 10 s without data and 20 s in all. Ephemeral: no
    /// cookies or cache are kept. Redirects are followed, as HttpURLConnection follows them.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = ReadingReporter.readTimeout
        configuration.timeoutIntervalForResource = ReadingReporter.connectTimeout + ReadingReporter.readTimeout
        return URLSession(configuration: configuration)
    }()
}
