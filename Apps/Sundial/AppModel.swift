import Combine
import Foundation
import SundialCore
import SundialRender
import SwiftUI
import UIKit
import WidgetKit

/// What MainActivity.kt does, for the iOS app: owns the instrument (through InstrumentModel), the
/// calendars, the astrology profile and the day's horoscope, and wires them to the three tuck
/// menus. The panels read its published state and call its methods as the Android panels call
/// MainActivity's listeners.
///
/// Android's wallpaper refresh (refreshWallpapers) becomes a reload of the widgets' timelines,
/// which draw from the same App Group settings. As on Android, the hemisphere lives in the view
/// only: it is not saved, every launch starts in the northern hemisphere, and the widgets (like
/// the wallpaper) always draw the northern one.
@MainActor
final class AppModel: ObservableObject {
    let settings: SettingsStore
    let instrumentModel: InstrumentModel
    /// EventKit, once the app runs normally (screenshot mode never touches it).
    let calendarStore: CalendarStore?
    let horoscopeService: HoroscopeService
    /// The astrology menu's typed fields, kept while the menu is tucked away.
    let astrologyForm = AstrologyForm()
    /// Set when UI tests launch the app to capture store screenshots (ScreenshotTests).
    let screenshot: ScreenshotScene?

    // MARK: Published state

    /// The open tuck menu, if any (TuckMenuHost's `open`).
    @Published var openMenu: TuckCorner?

    // SettingsPanel.syncControls
    @Published private(set) var clockVisible = false
    @Published private(set) var galacticVisible = false
    @Published private(set) var southernHemisphere = false
    @Published private(set) var style: CelestialStyle

    /// The chosen calendars, in the order they were chosen (CalendarPanel's LinkedHashSet).
    @Published private(set) var selectedCalendarIds: [Int64] = []

    // AstrologyPanel
    @Published private(set) var zodiacProfile: ZodiacProfile
    @Published private(set) var hasReading = false
    @Published private(set) var horoscopeStatus = AppModel.defaultStatus
    @Published private(set) var horoscopeAvailability: HoroscopeService.Availability

    /// MainActivity.showZodiacSignPicker's dialog.
    @Published var showingSignPicker = false
    /// MainActivity.showReportDialog's dialog, with the reading it would report.
    @Published var reportRequest: ReadingReportRequest?
    /// Android's Toast.
    @Published private(set) var toast: SundialToast?

    // MARK: Private state

    private var horoscopeGenerating = false
    /// The pending automatic horoscope (Android's automaticHoroscope Runnable).
    private var automaticHoroscope: Task<Void, Never>?
    private var occurrenceTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    /// A widget's Earth-view link waiting for the instrument's first frame (openURL).
    private var earthViewRetry: Task<Void, Never>?
    private var subscriptions: Set<AnyCancellable> = []

    static let defaultStatus = "Birth details stay on this device."
    static let writingStatus = "Writing your private horoscope on device…"
    static let writtenStatus = "Written privately by Apple Intelligence · displayed on the instrument"
    static let displayedStatus = "Today's on-device horoscope is displayed on the instrument."

    // MARK: onCreate

    init() {
        SundialResources.registerFonts()
        let screenshot = ScreenshotScene.fromLaunchArguments()
        let settings = SundialResources.settings()
        let instrumentModel: InstrumentModel
        if let screenshot {
            // Built from the scene alone: screenshot mode neither reads nor migrates saved settings.
            let instrument = Instrument(layout: .phone, density: 1,
                                        earthTexture: SundialResources.earthTexture(downsampled: false),
                                        style: screenshot.style, zone: screenshot.zone, now: screenshot.instant)
            instrumentModel = InstrumentModel(instrument: instrument, settings: settings)
        } else {
            // Set up from the saved style, astrology profile and today's reading (SundialView's init).
            instrumentModel = InstrumentModel(layout: .phone, settings: settings)
        }
        let horoscopeService = HoroscopeService()
        self.screenshot = screenshot
        self.settings = settings
        self.instrumentModel = instrumentModel
        self.calendarStore = screenshot == nil ? CalendarStore() : nil
        self.horoscopeService = horoscopeService
        style = instrumentModel.style
        zodiacProfile = screenshot == nil ? settings.zodiac.get() : ScreenshotScene.sampleProfile
        horoscopeAvailability = screenshot == nil ? horoscopeService.availability : .available

        instrumentModel.onControlsChanged = { [weak self] in self?.syncControls() }
        instrumentModel.onCalendarSelectionChanged = { [weak self] ids in self?.loadOccurrences(ids) }
        instrumentModel.onHoroscopeTapped = { [weak self] in self?.showReportDialog() }

        if let screenshot {
            setUpScreenshot(screenshot)
            return
        }

        if let calendarStore {
            // The panels read the store through this model: pass its changes on.
            calendarStore.objectWillChange
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &subscriptions)
            // EventKit reported a change to the calendar database: fetch the occurrences again.
            calendarStore.$revision
                .dropFirst()
                .sink { [weak self] _ in
                    guard let self, !self.selectedCalendarIds.isEmpty else { return }
                    self.loadOccurrences(Set(self.selectedCalendarIds))
                }
                .store(in: &subscriptions)
        }
        // Midnight, a new time zone or a changed clock (also posted on waking when the day changed
        // while the device slept): the app stays in front as a desk clock (the idle timer is off),
        // so yesterday's reading is taken down and the new day's is written.
        NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshTodaysReading()
                self.scheduleHoroscope(0)
            }
            .store(in: &subscriptions)

        syncControls()
        astrologyForm.setZodiacProfile(zodiacProfile)
        if let horoscope = settings.zodiac.getCurrentHoroscope(zodiacProfile, Self.today()) {
            instrumentModel.setHoroscope(horoscope)
            hasReading = true
            horoscopeStatus = Self.displayedStatus
        }
        refreshCalendarAccess()
    }

    // MARK: onResume / onPause

    /// The scene's phase (SundialApp): active is Android's onResume, anything else its onPause.
    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active: resume()
        case .inactive, .background: pause()
        @unknown default: break
        }
    }

    /// onResume: the clock runs again, calendar access is read again (it may have changed in
    /// Settings), and a new day (or a first launch with astrology on) gets its reading unasked.
    func resume() {
        // FLAG_KEEP_SCREEN_ON.
        UIApplication.shared.isIdleTimerDisabled = true
        if screenshot != nil { return }
        instrumentModel.resumeClock()
        refreshCalendarAccess()
        refreshHoroscopeAvailability()
        refreshTodaysReading()
        scheduleHoroscope(0)
    }

    /// onPause.
    func pause() {
        if screenshot == nil { instrumentModel.pauseClock() }
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: Settings panel

    func closeMenu() { openMenu = nil }

    func setClockVisible(_ value: Bool) {
        instrumentModel.setClockVisible(value)
        syncControls()
    }

    func setGalacticVisible(_ value: Bool) {
        instrumentModel.setGalacticVisible(value)
        syncControls()
        closeMenu()
    }

    /// SundialView.setSouthernHemisphere: shown, not saved (Android keeps it in the view only).
    func setSouthernHemisphere(_ value: Bool) {
        instrumentModel.setSouthernHemisphere(value)
        syncControls()
    }

    func setBackgroundStyle(_ value: CelestialStyle) {
        if screenshot != nil {
            instrumentModel.instrument.setBackgroundStyle(value)
        } else {
            // Shows and saves it (SundialView.setBackgroundStyle).
            instrumentModel.setBackgroundStyle(value)
        }
        style = value
        refreshWidgets()
    }

    func resetNow() {
        if screenshot == nil { instrumentModel.resetNow() }
        refreshWidgets()
        closeMenu()
    }

    /// SettingsPanel.syncControls from the instrument's state.
    private func syncControls() {
        let clock = instrumentModel.isClockVisible
        let galactic = instrumentModel.isGalacticVisible
        let southern = instrumentModel.isSouthernHemisphere
        if clockVisible != clock { clockVisible = clock }
        if galacticVisible != galactic { galacticVisible = galactic }
        if southernHemisphere != southern { southernHemisphere = southern }
    }

    // MARK: Calendars

    var calendarAccess: CalendarStore.Access {
        if screenshot != nil { return .granted }
        return calendarStore?.access ?? .notDetermined
    }

    var deviceCalendars: [DeviceCalendar] {
        if let screenshot { return screenshot.calendars }
        return calendarStore?.calendars ?? []
    }

    func isCalendarSelected(_ id: Int64) -> Bool { selectedCalendarIds.contains(id) }

    /// CalendarPanel's switch listener, then MainActivity's onCalendarSelectionChanged.
    func setCalendar(_ id: Int64, selected: Bool) {
        var ids = selectedCalendarIds
        if selected {
            if !ids.contains(id) { ids.append(id) }
        } else {
            ids.removeAll { $0 == id }
        }
        selectedCalendarIds = ids
        instrumentModel.setSelectedCalendarIds(ids)
        loadOccurrences(Set(ids))
    }

    /// requestCalendarAccess: ask iOS, or open Settings once iOS will no longer ask.
    func requestCalendarAccess() {
        guard screenshot == nil, let calendarStore else { return }
        if calendarStore.access == .denied {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } else {
            Task { await calendarStore.requestAccess() }
        }
    }

    /// refreshCalendarAccess: with access the calendars are listed, without it the panel asks.
    private func refreshCalendarAccess() {
        calendarStore?.refreshAccess()
    }

    /// loadOccurrences: the chosen calendars' events in the displayed year. The year is read now,
    /// on the main thread, since scrubbing keeps changing it. Only the latest request is applied.
    private func loadOccurrences(_ ids: Set<Int64>) {
        guard screenshot == nil, let calendarStore else { return }
        let year = instrumentModel.displayedYear
        let zone = TimeZone.current
        occurrenceTask?.cancel()
        occurrenceTask = Task { [weak self] in
            let occurrences = await calendarStore.occurrences(calendarIds: ids, year: year, zone: zone)
            guard !Task.isCancelled, let self else { return }
            self.instrumentModel.setCalendarOccurrences(occurrences)
        }
    }

    // MARK: Astrology panel

    func setZodiacEnabled(_ enabled: Bool) {
        var profile = zodiacProfile
        profile.enabled = enabled
        updateZodiacProfile(profile, horoscopeDelay: 0)
    }

    func setBirthDate(_ date: LocalDate) {
        var profile = zodiacProfile
        profile.birthDate = date
        profile.selectedSign = Zodiac.signFor(date)
        updateZodiacProfile(profile)
    }

    func setBirthTime(_ time: LocalTime) {
        var profile = zodiacProfile
        profile.birthTime = time
        updateZodiacProfile(profile)
    }

    func showZodiacSignPicker() { showingSignPicker = true }

    /// Whether Apple's on-device model can write a reading now; it changes as Apple Intelligence is
    /// turned on or its model finishes downloading, so the panel reads it again when it appears.
    func refreshHoroscopeAvailability() {
        guard screenshot == nil else { return }
        let availability = horoscopeService.availability
        if availability != horoscopeAvailability { horoscopeAvailability = availability }
    }

    /// The sign picker's choice: [which] 0 is AUTOMATIC FROM BIRTHDAY (the birthday's sign, or none
    /// without a birthday), n the n-th sign.
    func selectZodiacSign(_ which: Int) {
        let signs = Zodiac.Sign.allCases
        guard which >= 0, which <= signs.count else { return }
        var profile = zodiacProfile
        profile.selectedSign = which == 0 ? zodiacProfile.birthDate.map(Zodiac.signFor) : signs[which - 1]
        updateZodiacProfile(profile, horoscopeDelay: 0)
    }

    /// Saves the profile and, once astrology is on with a valid birth date and time, writes today's
    /// horoscope straight away. Typing settles for [horoscopeDelay] seconds first so a half-edited
    /// date does not start a reading.
    private func updateZodiacProfile(_ profile: ZodiacProfile, horoscopeDelay: TimeInterval = 0.9) {
        if screenshot != nil {
            // Screenshot mode saves nothing.
            zodiacProfile = profile
            astrologyForm.setZodiacProfile(profile)
            return
        }
        zodiacProfile = instrumentModel.setZodiacProfile(profile)
        astrologyForm.setZodiacProfile(zodiacProfile)
        if !zodiacProfile.isComplete {
            horoscopeStatus = "Enter birth date and time for a private on-device horoscope."
        } else if !zodiacProfile.enabled {
            horoscopeStatus = "Turn on astrology mode to write today's horoscope."
        } else {
            horoscopeStatus = Self.defaultStatus
        }
        refreshWidgets()
        scheduleHoroscope(horoscopeDelay)
    }

    private func scheduleHoroscope(_ delay: TimeInterval) {
        automaticHoroscope?.cancel()
        automaticHoroscope = nil
        guard screenshot == nil, zodiacProfile.enabled, zodiacProfile.isComplete else { return }
        let today = Self.today()
        if settings.zodiac.getCurrentHoroscope(zodiacProfile, today) != nil { return }
        // A reading the person reported is not silently replaced; they can ask for a new one.
        if settings.zodiac.wasReadingReported(today) { return }
        automaticHoroscope = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard !Task.isCancelled else { return }
            self?.generateHoroscope(automatic: true)
        }
    }

    func generateHoroscope(automatic: Bool) {
        automaticHoroscope?.cancel()
        automaticHoroscope = nil
        if horoscopeGenerating || screenshot != nil { return }
        if !zodiacProfile.isComplete {
            if !automatic { showToast("Set birth date and birth time first") }
            return
        }
        let requested = zodiacProfile
        // One day for the prompt and the saved reading, so a reading written across midnight is
        // stored under the day it was written for.
        let date = Self.today()
        horoscopeGenerating = true
        horoscopeStatus = Self.writingStatus
        Task { [weak self] in
            guard let self else { return }
            do {
                let horoscope = try await self.horoscopeService.generate(profile: requested, date: date)
                self.settings.zodiac.setHoroscope(requested, date, horoscope)
                // Shown only while it is still that day's reading for this profile; otherwise the
                // new day's reading follows (scheduleHoroscope below, or the time-change observer).
                if requested.signature == self.zodiacProfile.signature && date == Self.today() {
                    self.instrumentModel.setHoroscope(horoscope)
                    self.hasReading = true
                }
                self.horoscopeStatus = Self.writtenStatus
                self.refreshWidgets()
            } catch {
                let message = Self.message(error, fallback: "On-device horoscope generation failed")
                self.horoscopeStatus = message
                if !automatic { self.showToast(message, long: true) }
            }
            self.horoscopeGenerating = false
            self.refreshHoroscopeAvailability()
            // Birth details changed, or the day turned, while the reading was being written: write
            // the new one.
            if requested.signature != self.zodiacProfile.signature || date != Self.today() {
                self.scheduleHoroscope(0)
            }
        }
    }

    /// Only today's saved reading is shown: at a new day yesterday's is taken down, since it could
    /// no longer be reported (showReportDialog looks up today's).
    private func refreshTodaysReading() {
        guard screenshot == nil else { return }
        let reading = settings.zodiac.getCurrentHoroscope(zodiacProfile, Self.today())
        instrumentModel.setHoroscope(reading)
        hasReading = reading != nil
        if reading == nil && !horoscopeGenerating
            && (horoscopeStatus == Self.writtenStatus || horoscopeStatus == Self.displayedStatus) {
            horoscopeStatus = Self.defaultStatus
        }
    }

    // MARK: Reporting a reading

    /// showReportDialog: readings can be reported without leaving the app, as the stores' rules
    /// for AI-generated content ask.
    func showReportDialog() {
        if screenshot != nil { return }
        let today = Self.today()
        guard let reading = settings.zodiac.getCurrentHoroscope(zodiacProfile, today) else {
            showToast("There is no reading to report today")
            return
        }
        reportRequest = ReadingReportRequest(reading: reading, date: today)
    }

    /// SEND REPORT: the reading disappears at once and is sent to the developer with the reason.
    func sendReport(_ request: ReadingReportRequest, reason: ReadingReporter.Reason) {
        reportRequest = nil
        if screenshot != nil { return }
        settings.zodiac.hideReportedHoroscope(request.date)
        instrumentModel.setHoroscope(nil)
        hasReading = false
        horoscopeStatus = "Reading hidden. Write a new reading whenever you like."
        refreshWidgets()
        let version = Self.appVersion
        Task { [weak self] in
            do {
                try await ReadingReportService.submit(reading: request.reading, reason: reason,
                                                      date: request.date, appVersion: version)
                self?.showToast("Thank you — the reading was reported")
            } catch {
                self?.showToast("Reading hidden; the report could not be sent")
            }
        }
    }

    // MARK: Links

    /// A widget's link (sundial://view/heliocentric or sundial://view/geocentric): the app comes
    /// forward with its menus tucked away, showing the solar view for the first and flying to the
    /// Earth view for the second, as a tap on the Sun does.
    func openURL(_ url: URL) {
        closeMenu()
        guard screenshot == nil, url.scheme == "sundial", url.host == "view" else { return }
        earthViewRetry?.cancel()
        earthViewRetry = nil
        if url.lastPathComponent == "heliocentric" && instrumentModel.viewState != .heliocentric {
            instrumentModel.setGalacticVisible(false)
            syncControls()
        } else if url.lastPathComponent == "geocentric" && instrumentModel.viewState != .geocentric {
            // A link that opens the app arrives before the instrument's first frame.
            if !instrumentModel.showEarthView() { retryEarthView() }
            syncControls()
        }
    }

    /// The Earth-view link could not fly yet (no frame drawn, a finger on the dial, or another
    /// flight running): tried again every 0.1 s for up to 5 s.
    private func retryEarthView() {
        earthViewRetry = Task { [weak self] in
            for _ in 0..<50 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard !Task.isCancelled, let self else { return }
                if self.instrumentModel.viewState == .geocentric || self.instrumentModel.showEarthView() {
                    self.earthViewRetry = nil
                    self.syncControls()
                    return
                }
            }
        }
    }

    // MARK: Helpers

    /// refreshWallpapers: the widgets draw from the saved settings, so they are told to redraw.
    private func refreshWidgets() {
        guard screenshot == nil else { return }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Toast.makeText(…).show(): LENGTH_SHORT is 2 s, LENGTH_LONG 3.5 s. VoiceOver reads it out, as
    /// TalkBack reads toasts.
    private func showToast(_ text: String, long: Bool = false) {
        toast = SundialToast(text: text)
        UIAccessibility.post(notification: .announcement, argument: text)
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: long ? 3_500_000_000 : 2_000_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    /// LocalDate.now().
    static func today() -> LocalDate { LocalDate.of(Date(), TimeZone.current) }

    /// Android's "versionName (versionCode)".
    static var appVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let name = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(name) (\(build))"
    }

    /// Throwable.message ?: [fallback].
    static func message(_ error: Error, fallback: String) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription,
           !description.isEmpty {
            return description
        }
        if let description = (error as NSError).userInfo[NSLocalizedDescriptionKey] as? String,
           !description.isEmpty {
            return description
        }
        return fallback
    }

    // MARK: Screenshot mode

    /// StoreAssetsCapture.screen: a frozen scene with the sample calendars, events, reader and
    /// reading, and nothing of the device's own. Nothing is saved.
    private func setUpScreenshot(_ scene: ScreenshotScene) {
        let instrument = instrumentModel.instrument
        instrument.zone = scene.zone
        instrumentModel.setSelectedCalendarIds(ScreenshotScene.selectedCalendarIds)
        instrumentModel.setCalendarOccurrences(scene.events())
        instrument.setZodiacProfile(scene.astrology ? ScreenshotScene.sampleProfile : ZodiacProfile(enabled: false),
                                    horoscope: scene.astrology ? ScreenshotScene.sampleReading : nil)
        instrumentModel.freezeForCapture(instant: scene.instant, state: scene.state, style: scene.style)
        selectedCalendarIds = ScreenshotScene.selectedCalendarIds
        style = scene.style
        zodiacProfile = ScreenshotScene.sampleProfile
        astrologyForm.setZodiacProfile(ScreenshotScene.sampleProfile)
        hasReading = true
        horoscopeStatus = Self.writtenStatus
        syncControls()
        openMenu = TuckCorner(screenshotMenu: scene.menu)
    }
}

/// The reading the report sheet is about, and the day it was written for.
struct ReadingReportRequest: Identifiable {
    let id = UUID()
    let reading: String
    let date: LocalDate
}

/// One Android Toast.
struct SundialToast: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

extension TuckCorner {
    /// The corner -screenshotMenu names (ScreenshotScene.menu): settings, calendars or astrology.
    init?(screenshotMenu name: String?) {
        switch name {
        case "settings": self = .topStart
        case "calendars": self = .bottomStart
        case "astrology": self = .bottomEnd
        default: return nil
        }
    }
}
