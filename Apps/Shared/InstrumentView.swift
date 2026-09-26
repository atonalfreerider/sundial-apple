// The instrument on screen, for the iOS app and the watch app: Android's SundialView as a SwiftUI
// view. A Canvas lends its context to Core Graphics, where CGCanvas draws the Instrument; a
// TimelineView paces the frames as the Instrument asks; a zero-distance drag feeds its touch
// handling. The watch adds the Digital Crown (the Wear OS rotary input) and the always-on display.
//
// The host owns the model (a @StateObject), lays the view out (full screen, under the safe areas,
// as Android hides the system bars) and wires the model's callbacks.

import SwiftUI

public struct InstrumentView: View {
    @ObservedObject private var model: InstrumentModel
    @Environment(\.displayScale) private var displayScale
    /// True while a finger is down; SwiftUI resets it when the drag ends or is cancelled.
    @GestureState private var touching = false
    #if os(watchOS)
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @State private var crownValue = 0.0
    @FocusState private var crownFocused: Bool
    /// The crown's travel either way, in detents: far more than anyone turns it.
    private static let crownRange = 1_000_000.0
    #endif

    public init(model: InstrumentModel) {
        _model = ObservedObject(wrappedValue: model)
    }

    public var body: some View {
        #if os(watchOS)
        interactiveInstrument
            // The crown moves through time, as the Wear OS rotary input does: one detent is a day in
            // the Sun view, twenty minutes in the Earth view and a month in the galactic view.
            // Turning it up moves forward.
            .focusable()
            .focused($crownFocused)
            .focusEffectDisabled()
            .digitalCrownRotation(detent: $crownValue, from: -Self.crownRange, through: Self.crownRange, by: 1,
                                  sensitivity: .high, isContinuous: false, isHapticFeedbackEnabled: true)
            .digitalCrownAccessory(.hidden)
            .onChange(of: crownValue) { oldValue, newValue in
                model.scrubBy(newValue - oldValue)
            }
            // The always-on display: grey and dim, once a minute (AmbientLifecycleObserver).
            .onChange(of: isLuminanceReduced, initial: true) { _, reduced in
                model.setAmbient(reduced)
            }
            .onAppear { crownFocused = true }
        #else
        interactiveInstrument
        #endif
    }

    private var interactiveInstrument: some View {
        ZStack { frames }
            // SundialView's black background, under the first frame and the safe areas.
            .background(Color.black)
            .contentShape(Rectangle())
            .gesture(touchGesture)
            .onChange(of: touching) { _, isTouching in
                if !isTouching { model.touchGestureReset() }
            }
            // performHapticFeedback(LONG_PRESS).
            .sensoryFeedback(.impact, trigger: model.longPressCount)
            // The instrument is drawn, not built from views: VoiceOver reads its summary.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: model.accessibilityDescription))
            .accessibilityAction(named: Text("Reset current time")) {
                model.resetNow()
            }
    }

    /// The frame pacing (postInvalidateDelayed / postInvalidateOnAnimation on Android): every
    /// display frame during a camera flight, then every 0.25 s with the clock or 1 s without,
    /// paused when nothing moves; once a minute on the watch's always-on display.
    @ViewBuilder
    private var frames: some View {
        #if os(watchOS)
        if isLuminanceReduced {
            // watchOS may render these entries ahead of time, so each shows its own minute.
            TimelineView(.everyMinute) { timeline in
                instrumentCanvas(frameDate: timeline.date, clockDate: timeline.date, ambient: true)
            }
        } else {
            liveFrames
        }
        #else
        liveFrames
        #endif
    }

    private var liveFrames: some View {
        let interval = model.frameInterval
        return TimelineView(.animation(minimumInterval: interval == 0 ? nil : interval, paused: interval == nil)) { timeline in
            instrumentCanvas(frameDate: timeline.date, clockDate: nil, ambient: liveAmbientState)
        }
    }

    /// Outside the always-on display the watch is never ambient; the phone has no ambient mode.
    private var liveAmbientState: Bool? {
        #if os(watchOS)
        return false
        #else
        return nil
        #endif
    }

    /// One frame. The redraw tick and the frame's date are captured so SwiftUI redraws the Canvas
    /// whenever either changes.
    private func instrumentCanvas(frameDate: Date, clockDate: Date?, ambient: Bool?) -> some View {
        let model = self.model
        let scale = displayScale
        let tick = model.redrawTick
        return SwiftUI.Canvas { context, size in
            _ = (frameDate, tick)
            context.withCGContext { cg in
                model.draw(in: cg, size: size, displayScale: scale, date: clockDate, ambient: ambient)
            }
        }
    }

    /// onTouchEvent: the finger's location in the view's points (the Canvas's units) goes to the
    /// Instrument as down, move and up; the model runs the long-press timer.
    private var touchGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($touching) { _, isTouching, _ in isTouching = true }
            .onChanged { value in model.touchChanged(value.location) }
            .onEnded { value in model.touchEnded(value.location) }
    }
}
