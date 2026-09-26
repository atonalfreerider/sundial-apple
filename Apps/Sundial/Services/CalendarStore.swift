import Combine
import CoreGraphics
import EventKit
import Foundation
import SundialCore

/// The calendars on this device, read-only, through EventKit: the iOS port of the Android
/// CalendarRepository (CalendarContract) together with the access state MainActivity kept.
///
/// Calendar access is asked for in context, from the calendar menu, never at launch: the panel
/// calls `requestAccess()` while `access == .notDetermined`. Once iOS has recorded a refusal it no
/// longer shows the prompt (Android's "permanent refusal"), so `.denied` is the panel's cue to offer
/// "OPEN SETTINGS" (Android's "ALLOW IN SETTINGS") and open the app's page in Settings. Access may be granted or revoked in
/// Settings while the app is away: call `refreshAccess()` when the scene becomes active, as
/// Android's onResume did.
///
/// Calendars are identified by a stable `Int64` (FNV-1a of `EKCalendar.calendarIdentifier`), so
/// ids survive relaunches as Android's `Calendars._ID` does.
@MainActor
final class CalendarStore: ObservableObject {
    enum Access { case notDetermined, denied, granted }

    @Published private(set) var access: Access = .notDetermined
    /// The device's event calendars, Google first, then by name (CalendarRepository.loadCalendars).
    @Published private(set) var calendars: [DeviceCalendar] = []
    /// Bumped whenever EventKit reports a change to the calendar database (`.EKEventStoreChanged`):
    /// whoever shows occurrences fetches them again. `calendars` is reloaded before it changes.
    @Published private(set) var revision = 0

    private let store = EKEventStore()
    /// Android's calendarsLoaded: the list is read once per grant, then kept current by
    /// `.EKEventStoreChanged`.
    private var calendarsLoaded = false
    /// Android's single-thread calendarExecutor: EventKit's fetch is synchronous and can be slow, so
    /// it runs here, one request at a time, in the order they were made.
    private let queue = DispatchQueue(label: "com.metavirtuoso.sundial.calendar", qos: .userInitiated)
    private var changeObserver: StoreChangeObserver?

    init() {
        changeObserver = StoreChangeObserver(store) { [weak self] in self?.storeChanged() }
        refreshAccess()
    }

    /// Reads the current authorization; with access, lists the calendars (once), without it clears them.
    func refreshAccess() {
        let current = Self.currentAccess()
        if access != current { access = current }
        if current == .granted {
            if !calendarsLoaded { reloadCalendars() }
        } else {
            calendarsLoaded = false
            if !calendars.isEmpty { calendars = [] }
        }
    }

    /// Shows iOS's full-access prompt (iOS 17's requestFullAccessToEvents) and lists the calendars
    /// once it is granted. When iOS has already recorded an answer it returns at once with that
    /// answer, without a prompt.
    func requestAccess() async {
        let wasGranted = Self.currentAccess() == .granted
        do {
            _ = try await store.requestFullAccessToEvents()
        } catch {
            // The prompt could not be shown; the status below still says what access there is.
        }
        if !wasGranted && Self.currentAccess() == .granted {
            // A store made before the grant can hold an empty cache of the calendar database.
            store.reset()
            calendarsLoaded = false
        }
        refreshAccess()
    }

    /// Lists the device's event calendars again (CalendarRepository.loadCalendars).
    func reloadCalendars() {
        guard Self.currentAccess() == .granted else {
            calendarsLoaded = false
            if !calendars.isEmpty { calendars = [] }
            return
        }
        calendarsLoaded = true
        var seen = Set<Int64>()
        let loaded = store.calendars(for: .event)
            .map(EventKitMapping.deviceCalendar)
            .filter { seen.insert($0.id).inserted }
        // CalendarContract returned them ordered by account type, then name (COLLATE NOCASE); the
        // repository then sorts Google calendars first, then by lower-cased name, keeping that order
        // for ties (sortedWith is stable, as is sorted(by:)).
        calendars = loaded
            .sorted { ($0.accountType, $0.displayName.lowercased()) < ($1.accountType, $1.displayName.lowercased()) }
            .sorted { lhs, rhs in
                if lhs.isGoogle != rhs.isGoogle { return lhs.isGoogle }
                return lhs.displayName.lowercased() < rhs.displayName.lowercased()
            }
    }

    /// The occurrences of the chosen calendars' events in [year], as MainActivity.loadOccurrences
    /// asks CalendarRepository.loadInstances for them: from the start of 1 January of [year] to the
    /// start of 2 January of the next year in [zone], normalized for display in [zone] by
    /// SundialCore's CalendarNormalizer and sorted by start. EventKit expands recurring events into
    /// their occurrences, as the Instances table does. Empty without access or calendars.
    func occurrences(calendarIds: Set<Int64>, year: Int, zone: TimeZone) async -> [CalendarOccurrence] {
        guard Self.currentAccess() == .granted, !calendarIds.isEmpty else { return [] }
        let fetch = OccurrenceFetch(
            store: store,
            calendarIds: calendarIds,
            begin: LocalDate(year, 1, 1).atStartOfDay(zone),
            end: LocalDate(year + 1, 1, 2).atStartOfDay(zone),
            zone: zone
        )
        return await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: fetch.run()) }
        }
    }

    private func storeChanged() {
        guard Self.currentAccess() == .granted else {
            refreshAccess()
            return
        }
        reloadCalendars()
        revision &+= 1
    }

    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .granted
        case .notDetermined: return .notDetermined
        // .denied, .restricted and .writeOnly. (An app granted access before iOS 17 is reported
        // as .fullAccess.)
        default: return .denied
        }
    }
}

// MARK: - EventKit to SundialCore

/// One occurrence query, run on CalendarStore's queue. EventKit documents events(matching:) as
/// synchronous and meant to be run off the main thread; the store is only read here.
private nonisolated struct OccurrenceFetch: @unchecked Sendable {
    let store: EKEventStore
    let calendarIds: Set<Int64>
    let begin: Date
    let end: Date
    let zone: TimeZone

    func run() -> [CalendarOccurrence] {
        let calendars = store.calendars(for: .event).filter {
            calendarIds.contains(EventKitMapping.stableId($0.calendarIdentifier))
        }
        // An empty list would mean "every calendar" to predicateForEvents.
        if calendars.isEmpty { return [] }
        let predicate = store.predicateForEvents(withStart: begin, end: end, calendars: calendars)
        var rows: [CalendarOccurrence] = []
        for event in store.events(matching: predicate) {
            guard let raw = EventKitMapping.rawInstance(event) else { continue }
            rows.append(CalendarNormalizer.normalize(raw, zone))
        }
        return rows.sorted { $0.start.instant < $1.start.instant }
    }
}

/// EventKit objects as the CalendarContract rows CalendarRepository read.
nonisolated enum EventKitMapping {
    /// DeviceCalendar.isGoogle's account type.
    static let googleAccountType = "com.google"
    /// For a calendar without a colour (CalendarContract always has one).
    static let fallbackColor: ARGB = 0xFF8E_8E93

    /// A stable id for an EventKit identifier: 64-bit FNV-1a over its UTF-8, as a signed Int64.
    static func stableId(_ identifier: String) -> Int64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in identifier.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return Int64(bitPattern: hash)
    }

    /// A Calendars row: display name ("Calendar" when blank), the account (the source's title),
    /// its type and the calendar's colour.
    static func deviceCalendar(_ calendar: EKCalendar) -> DeviceCalendar {
        let title: String? = calendar.title
        let source: EKSource? = calendar.source
        return DeviceCalendar(
            stableId(calendar.calendarIdentifier),
            title.flatMap { isBlank($0) ? nil : $0 } ?? "Calendar",
            source?.title ?? "",
            accountType(source),
            argb(calendar.cgColor)
        )
    }

    /// An Instances row. Timed events keep their instants. All-day events are floating dates that
    /// EventKit gives as local midnight of the first day through 23:59:59 of the last; like
    /// Android's CalendarContract they become UTC midnights of the first day and of the day after
    /// the last, so CalendarNormalizer reads them as date labels. (Rounding by half a day keeps the
    /// dates right even if EventKit placed them in a zone other than the device's.)
    static func rawInstance(_ event: EKEvent) -> RawCalendarInstance? {
        let startDate: Date? = event.startDate
        let endDate: Date? = event.endDate
        let calendar: EKCalendar? = event.calendar
        guard let start = startDate, let calendar else { return nil }
        let end = endDate ?? start
        let beginMillis: Int64
        let endMillis: Int64
        if event.isAllDay {
            let local = TimeZone.current
            let first = LocalDate.of(start.addingTimeInterval(halfDay), local)
            var endExclusive = LocalDate.of(end.addingTimeInterval(halfDay), local)
            if endExclusive <= first { endExclusive = first.plusDays(1) }
            beginMillis = first.atStartOfDay(utc).epochMillis
            endMillis = endExclusive.atStartOfDay(utc).epochMillis
        } else {
            beginMillis = start.epochMillis
            endMillis = end.epochMillis
        }
        let title: String? = event.title
        let eventIdentifier: String? = event.eventIdentifier
        let eventZone: TimeZone? = event.timeZone
        return RawCalendarInstance(
            stableId(eventIdentifier ?? event.calendarItemIdentifier),
            stableId(calendar.calendarIdentifier),
            title.flatMap { isBlank($0) ? nil : $0 } ?? "Busy",
            beginMillis,
            endMillis,
            event.isAllDay,
            eventZone?.identifier,
            argb(calendar.cgColor)
        )
    }

    /// Stands in for CalendarContract's ACCOUNT_TYPE. EventKit has no account types, only source
    /// types; a Google account added in Settings is a CalDAV source, titled "Gmail" unless renamed.
    static func accountType(_ source: EKSource?) -> String {
        guard let source else { return "" }
        switch source.sourceType {
        case .local: return "local"
        case .exchange: return "exchange"
        case .calDAV:
            let title = source.title.lowercased()
            if title.contains("gmail") || title.contains("google") { return googleAccountType }
            return title.contains("icloud") ? "icloud" : "caldav"
        case .mobileMe: return "icloud"
        case .subscribed: return "subscribed"
        case .birthdays: return "birthdays"
        @unknown default: return "other"
        }
    }

    /// The calendar's colour as Android's colour int, in sRGB.
    static func argb(_ color: CGColor?) -> ARGB {
        guard let color else { return fallbackColor }
        var rgba: [CGFloat] = []
        if let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
           let converted = color.converted(to: sRGB, intent: .defaultIntent, options: nil),
           let components = converted.components, components.count >= 4 {
            rgba = Array(components.prefix(4))
        } else if let components = color.components {
            switch color.colorSpace?.model {
            case .some(.rgb) where components.count >= 4: rgba = Array(components.prefix(4))
            case .some(.monochrome) where components.count >= 2:
                rgba = [components[0], components[0], components[0], components[1]]
            default: break
            }
        }
        guard rgba.count == 4 else { return fallbackColor }
        func byte(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return Colors.argb(byte(rgba[3]), byte(rgba[0]), byte(rgba[1]), byte(rgba[2]))
    }

    /// Kotlin's isBlank, near enough for titles.
    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static let halfDay: TimeInterval = 12 * 3_600
    /// ZoneId.of("UTC").
    private static let utc = TimeZone(identifier: "UTC")!
}

/// Delivers `.EKEventStoreChanged` for one store on the main actor, and stops when released.
private nonisolated final class StoreChangeObserver {
    private let token: any NSObjectProtocol

    init(_ store: EKEventStore, _ handler: @escaping @MainActor @Sendable () -> Void) {
        token = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
    }

    deinit { NotificationCenter.default.removeObserver(token) }
}
