// The host side of Android's SundialView: owns the Instrument, turns its invalidate() into SwiftUI
// redraws, runs its long-press timer and passes the app's settings to it. InstrumentView draws it;
// the iOS app and the watch app hold one each (as a @StateObject) and call its setters from their
// panels and settings screens.

import Combine
import CoreGraphics
import Foundation
import SundialCoreGraphics
import SundialRender

@MainActor
public final class InstrumentModel: ObservableObject {
    /// The instrument itself. Hosts may read it; changing it through the model keeps redraws and
    /// saved settings in step.
    public let instrument: Instrument
    /// Where the style and the astrology profile are saved (the App Group's settings).
    public let settings: SettingsStore

    // MARK: Published state (InstrumentView observes these)

    /// Bumped whenever the Instrument asks for a redraw (View.invalidate on Android).
    @Published public private(set) var redrawTick: UInt64 = 0
    /// How often InstrumentView's TimelineView should tick, from the Instrument's nextRedrawDelay
    /// after the last frame: 0 for every display frame (a camera flight), 0.25 s with the clock,
    /// 1 s without, nil when nothing moves (the clock is paused, or the watch is always-on).
    @Published public private(set) var frameInterval: TimeInterval? = 0.25
    /// The instrument in words, for VoiceOver (TalkBack's content description on Android).
    @Published public private(set) var accessibilityDescription = ""
    /// Counts long presses, so the view can play the long-press haptic Android's view plays.
    @Published public private(set) var longPressCount = 0

    // MARK: Host callbacks (the Android view's listeners)

    /// The Sun view's year changed with calendars selected, or time was reset: reload occurrences
    /// for `displayedYear` and pass them to `setCalendarOccurrences`.
    public var onCalendarSelectionChanged: ((Set<Int64>) -> Void)?
    /// The view (solar, Earth, galactic) changed: resync the settings panel's controls.
    public var onControlsChanged: (() -> Void)?
    /// A horoscope card was tapped: offer to report the reading.
    public var onHoroscopeTapped: (() -> Void)?
    /// Set by a host that opens settings on a long press (the watch app). While it is nil the
    /// instrument does not arm long presses at all, as on Android.
    public var onLongPress: (() -> Void)? {
        didSet { wireLongPress() }
    }

    /// Whether the instrument is drawing its always-on (ambient) face.
    public private(set) var isAmbient = false

    private var isDrawing = false
    private var redrawSuppressed = false
    private var publishScheduled = false
    private var fingerDown = false
    private var touchSequence = 0
    private var longPressTask: Task<Void, Never>?

    // MARK: Init

    /// An instrument fitted to [layout], set up from the saved settings as SundialView sets itself
    /// up (see SundialResources.makeInstrument, which also registers the fonts), with density 1 for
    /// a SwiftUI Canvas in points. A watch host then calls applyWatchSettings() whenever it becomes
    /// active, first launch included, as WatchActivity.onResume does.
    public convenience init(layout: InstrumentLayout = .phone, settings: SettingsStore = SundialResources.settings()) {
        self.init(instrument: SundialResources.makeInstrument(layout: layout, settings: settings), settings: settings)
    }

    /// Wraps an existing instrument (previews, captures). The model takes over its callbacks.
    public init(instrument: Instrument, settings: SettingsStore = SundialResources.settings()) {
        self.instrument = instrument
        self.settings = settings
        instrument.onRedrawRequested = { [weak self] in self?.requestRedraw() }
        instrument.onControlsChanged = { [weak self] in self?.deliver { $0.onControlsChanged?() } }
        instrument.onHoroscopeTapped = { [weak self] in self?.deliver { $0.onHoroscopeTapped?() } }
        instrument.onCalendarSelectionChanged = { [weak self] ids in
            self?.deliver { $0.onCalendarSelectionChanged?(ids) }
        }
        instrument.onLongPress = nil
    }

    // MARK: Reading the instrument

    public var layout: InstrumentLayout { instrument.layout }
    public var isClockVisible: Bool { instrument.isClockVisible }
    public var isGalacticVisible: Bool { instrument.isGalacticVisible }
    public var isSouthernHemisphere: Bool { instrument.isSouthernHemisphere }
    /// False once time has been scrubbed away from now.
    public var isRealtime: Bool { instrument.isRealtime }
    public var viewState: Instrument.ViewState { instrument.viewState }
    public var style: CelestialStyle { instrument.style }
    /// The year the dial shows (the calendar year to load occurrences for).
    public var displayedYear: Int { instrument.displayedYear }
    /// The moment the dial shows.
    public var instant: Date { instrument.instant }

    // MARK: Settings (SundialView's setters)

    public func setClockVisible(_ value: Bool) { instrument.setClockVisible(value) }

    public func setGalacticVisible(_ value: Bool) { instrument.setGalacticVisible(value) }

    public func setSouthernHemisphere(_ value: Bool) { instrument.setSouthernHemisphere(value) }

    /// Flies to the Earth view the way a tap on the Sun does (a widget's sundial://view/geocentric
    /// link), leaving the galactic view first if it is showing. SundialKit's view switch with the
    /// camera flight (Instrument.switchToState) is internal to SundialRender, so this taps the Sun
    /// at the dial's centre, straight on the Instrument: no long press is scheduled, and pointerUp
    /// clears the long-press deadline.
    ///
    /// Returns false when it cannot fly yet, for the host to try again shortly: before the first
    /// frame (the dial has no size, and the flight reads its geometry), while a finger is on the
    /// dial, or while another camera flight is still running.
    @discardableResult
    public func showEarthView() -> Bool {
        if instrument.viewState == .geocentric { return true }
        guard !fingerDown, instrument.width > 0, instrument.height > 0 else { return false }
        if instrument.viewState == .galactic { instrument.setGalacticVisible(false) }
        guard instrument.viewState == .heliocentric else { return true }
        let (cx, cy, _) = instrument.dialGeometry
        instrument.pointerDown(x: cx, y: cy)
        instrument.pointerUp(x: cx, y: cy)
        return instrument.viewState == .geocentric
    }

    /// Shows [style] and saves it, as SundialView.setBackgroundStyle does.
    public func setBackgroundStyle(_ style: CelestialStyle) {
        instrument.setBackgroundStyle(style)
        settings.celestialStyle.set(style)
    }

    /// Saves [profile] (keeping stored birth details a partial update leaves out) and shows it with
    /// the day's horoscope for it, as SundialView.setZodiacProfile does. Returns the saved profile.
    @discardableResult
    public func setZodiacProfile(_ profile: ZodiacProfile,
                                 today: LocalDate = LocalDate.of(Date(), TimeZone.current)) -> ZodiacProfile {
        let saved = settings.zodiac.set(profile)
        instrument.setZodiacProfile(saved, horoscope: settings.zodiac.getCurrentHoroscope(saved, today))
        return saved
    }

    /// Shows [text] as the horoscope (nil or blank hides it). Saving it is the host's job
    /// (SettingsStore.zodiac.setHoroscope), as on Android.
    public func setHoroscope(_ text: String?) { instrument.setHoroscope(text) }

    /// The selected calendars, in the order they were chosen.
    public func setSelectedCalendarIds(_ ids: [Int64]) { instrument.setSelectedCalendarIds(ids) }

    public func setCalendarOccurrences(_ occurrences: [CalendarOccurrence]) {
        instrument.setCalendarOccurrences(occurrences)
    }

    /// Back to the present moment (the RESET CURRENT TIME pill, the watch's NOW, the settings
    /// panel's reset).
    public func resetNow() { instrument.resetNow() }

    /// Onscreen and live (Activity.onResume).
    public func resumeClock() { instrument.resumeClock() }

    /// Offscreen (Activity.onPause): the dial stops following the clock.
    public func pauseClock() { instrument.pauseClock() }

    /// Moves through time by [detents] crown steps (a day, twenty minutes or a month per step).
    public func scrubBy(_ detents: Double) { instrument.scrubBy(detents) }

    /// The watch's always-on display: grey and dim, redrawn once a minute.
    public func setAmbient(_ value: Bool, burnInProtection: Bool = false) {
        isAmbient = value
        instrument.setAmbient(value, burnInProtection: burnInProtection)
    }

    /// Freezes one moment, view and style for screenshots; nothing is saved.
    public func freezeForCapture(instant: Date, state: Instrument.ViewState, style: CelestialStyle) {
        instrument.freezeForCapture(instant: instant, state: state, style: style)
    }

    /// WatchActivity.applySettings, for the watch app when it becomes active: the shared style and
    /// astrology profile, the watch's clock and hemisphere, and a pending one-shot request from the
    /// watch settings screen (toggle the galactic view, or return to now).
    public func applyWatchSettings() {
        setBackgroundStyle(settings.celestialStyle.get())
        setZodiacProfile(settings.zodiac.get())
        instrument.setClockVisible(settings.watch.showClock())
        instrument.setSouthernHemisphere(settings.watch.southern())
        switch settings.watch.consumeRequest() {
        case .galactic: instrument.setGalacticVisible(!instrument.isGalacticVisible)
        case .now: instrument.resetNow()
        case .none: break
        }
    }

    // MARK: Drawing

    /// Draws a frame into a Core Graphics context that is y-down in points, [size] big: the
    /// context SwiftUI's Canvas lends through withCGContext. [displayScale] is the screen's pixels
    /// per point. [date], when given, is the moment to show instead of the clock's (the always-on
    /// display draws the TimelineView entry's date, which watchOS may render ahead of time).
    /// [ambient], when given, brings the always-on state in line before drawing, so the first frame
    /// after the display wakes or dims is already the right one.
    ///
    /// Call it on the main thread (as SwiftUI renders a Canvas); it is nonisolated only so the
    /// Canvas's renderer closure can call it whatever isolation that closure has.
    nonisolated public func draw(in context: CGContext, size: CGSize, displayScale: CGFloat,
                                 date: Date? = nil, ambient: Bool? = nil) {
        guard size.width > 0, size.height > 0 else { return }
        MainActor.assumeIsolated {
            let canvas = CGCanvas(context: context, width: Double(size.width), height: Double(size.height),
                                  displayScale: Double(displayScale))
            self.draw(canvas, date: date, ambient: ambient)
        }
    }

    /// Draws a frame on any Canvas (see draw(in:size:displayScale:date:ambient:)).
    public func draw(_ canvas: Canvas, date: Date? = nil, ambient: Bool? = nil) {
        isDrawing = true
        if let ambient, ambient != isAmbient {
            // This frame is about to show the new state: no second redraw for it.
            redrawSuppressed = true
            setAmbient(ambient)
            redrawSuppressed = false
        }
        let clock = instrument.currentDate
        if let date { instrument.currentDate = { date } }
        instrument.draw(canvas)
        instrument.currentDate = clock
        isDrawing = false
        publishAfterDraw()
    }

    /// View.invalidate(). A request made while a frame is being drawn waits for the next turn of
    /// the main loop, since SwiftUI does not allow publishing changes during a view update.
    private func requestRedraw() {
        if redrawSuppressed { return }
        if isDrawing {
            Task { @MainActor [weak self] in self?.redrawTick &+= 1 }
        } else {
            redrawTick &+= 1
        }
    }

    /// Calls a host callback now, or just after the frame if the Instrument raised it while
    /// drawing (onCalendarSelectionChanged fires from onDraw when the displayed year changes).
    private func deliver(_ action: @escaping @MainActor (InstrumentModel) -> Void) {
        if isDrawing {
            Task { @MainActor [weak self] in
                if let self { action(self) }
            }
        } else {
            action(self)
        }
    }

    /// Hands the frame's outcome (the next redraw delay, the spoken description) to SwiftUI once
    /// the view update is over.
    private func publishAfterDraw() {
        guard !publishScheduled,
              instrument.nextRedrawDelay != frameInterval
              || instrument.accessibilityDescription != accessibilityDescription else { return }
        publishScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.publishScheduled = false
            let interval = self.instrument.nextRedrawDelay
            if interval != self.frameInterval { self.frameInterval = interval }
            let description = self.instrument.accessibilityDescription
            if description != self.accessibilityDescription { self.accessibilityDescription = description }
        }
    }

    // MARK: Touch (onTouchEvent)

    /// DragGesture.onChanged with the finger's location in the view's points: the first call of a
    /// gesture is ACTION_DOWN, the rest ACTION_MOVE.
    public func touchChanged(_ location: CGPoint) {
        let x = Double(location.x)
        let y = Double(location.y)
        if fingerDown {
            instrument.pointerMove(x: x, y: y)
            return
        }
        fingerDown = true
        touchSequence &+= 1
        instrument.pointerDown(x: x, y: y)
        scheduleLongPress()
    }

    /// DragGesture.onEnded: ACTION_UP.
    public func touchEnded(_ location: CGPoint) {
        guard fingerDown else { return }
        endTouch()
        instrument.pointerUp(x: Double(location.x), y: Double(location.y))
    }

    /// ACTION_CANCEL: the system took the touch away.
    public func touchCancelled() {
        guard fingerDown else { return }
        endTouch()
        instrument.pointerCancel()
    }

    /// The gesture's @GestureState went back to its resting value. That happens when the gesture
    /// ends and when it is cancelled; onEnded is only called in the first case (before this), so a
    /// touch still down once the current event is handled was cancelled.
    public func touchGestureReset() {
        guard fingerDown else { return }
        let sequence = touchSequence
        Task { @MainActor [weak self] in
            guard let self, self.fingerDown, self.touchSequence == sequence else { return }
            self.touchCancelled()
        }
    }

    private func endTouch() {
        fingerDown = false
        longPressTask?.cancel()
        longPressTask = nil
    }

    // MARK: Long press

    /// postDelayed(longPress, getLongPressTimeout()): waits until the Instrument's deadline and
    /// fires if the same finger is still down and has not moved away (moving clears the deadline).
    private func scheduleLongPress() {
        longPressTask?.cancel()
        longPressTask = nil
        guard instrument.longPressDeadline != nil else { return }
        let sequence = touchSequence
        longPressTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.fingerDown, self.touchSequence == sequence,
                      let deadline = self.instrument.longPressDeadline else { return }
                let remaining = deadline - self.instrument.uptime()
                if remaining <= 0 {
                    self.instrument.longPressElapsed()
                    return
                }
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000) + 1)
            }
        }
    }

    private func wireLongPress() {
        guard onLongPress != nil else {
            instrument.onLongPress = nil
            return
        }
        instrument.onLongPress = { [weak self] in
            guard let self else { return }
            // performHapticFeedback(LONG_PRESS): InstrumentView plays it when this changes.
            self.longPressCount &+= 1
            self.onLongPress?()
        }
    }
}
