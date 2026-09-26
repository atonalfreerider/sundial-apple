import SundialCore
import SwiftUI
import UIKit

// A port of TuckMenuHost.kt: small "tuck" menus in the corners of the full-screen instrument.
// Each corner button unfolds a panel from that corner and tucks it away again; only one is open
// at a time, and a tap outside (on the scrim) or on the button again closes it. Bottom panels
// rise above the keyboard.
//
// Android lays the buttons 14 dp from the screen edges of an immersive window. On iOS the
// margins are at least the safe area's (the sensor housing, the home indicator and rounded
// corners), and never less than those 14 points.

/// TuckMenuHost.Corner.
enum TuckCorner: Hashable, CaseIterable {
    case topStart, bottomStart, bottomEnd
}

/// The corner buttons' drawings: ic_tuck_settings, ic_tuck_calendar and ic_tuck_astrology.
enum TuckIcon {
    case settings, calendar, astrology
}

struct TuckMenuHost<SettingsContent: View, CalendarContent: View, AstrologyContent: View>: View {
    @Binding var open: TuckCorner?
    /// The closed buttons' icon colour: the style's chrome colour.
    var iconColor: Color
    /// TuckMenuHost.accentColor: InstrumentControls.BRASS.
    var accentColor: ARGB = InstrumentControls.brass
    private let settings: SettingsContent
    private let calendar: CalendarContent
    private let astrology: AstrologyContent

    /// The size the layout leaves above the keyboard (the whole screen when none is shown).
    @State private var keyboardFreeSize: CGSize = .zero

    static var margin: CGFloat { 14 }
    static var buttonSize: CGFloat { 50 }
    static var gap: CGFloat { 8 }
    static var maxPanelWidth: CGFloat { 372 }
    /// ANIMATION_MS; Android unfolds with DecelerateInterpolator(1.6).
    static var animation: Animation { .easeOut(duration: 0.19) }

    init(open: Binding<TuckCorner?>, iconColor: Color, accentColor: ARGB = InstrumentControls.brass,
         @ViewBuilder settings: () -> SettingsContent,
         @ViewBuilder calendar: () -> CalendarContent,
         @ViewBuilder astrology: () -> AstrologyContent) {
        _open = open
        self.iconColor = iconColor
        self.accentColor = accentColor
        self.settings = settings()
        self.calendar = calendar()
        self.astrology = astrology()
    }

    var body: some View {
        ZStack {
            // Measures the room above the keyboard: this layer ignores the container safe area
            // but not the keyboard's, so its height is the screen's less the keyboard.
            GeometryReader { probe in
                Color.clear
                    .onAppear { keyboardFreeSize = probe.size }
                    .onChange(of: probe.size) { _, size in
                        withAnimation(.easeOut(duration: 0.25)) { keyboardFreeSize = size }
                    }
            }
            .ignoresSafeArea(.container)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            GeometryReader { proxy in
                layout(TuckLayout(size: proxy.size, insets: proxy.safeAreaInsets,
                                  keyboardFreeSize: keyboardFreeSize))
            }
            .ignoresSafeArea()
        }
        .animation(Self.animation, value: open)
        .onChange(of: open) { _, value in
            if value == nil {
                // TuckMenuHost.close(): clear the focus and hide the keyboard.
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
    }

    private func layout(_ metrics: TuckLayout) -> some View {
        ZStack {
            if open != nil {
                Color.black.opacity(Double(0x70) / 255)
                    .contentShape(Rectangle())
                    .onTapGesture { open = nil }
                    .transition(.opacity)
                    .accessibilityLabel("Close menu")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { open = nil }
                    .accessibilityAction(.escape) { open = nil }
            }

            panelSlot(.topStart, metrics) { settings }
            panelSlot(.bottomStart, metrics) { calendar }
            panelSlot(.bottomEnd, metrics) { astrology }

            button(.topStart, .settings, "Settings", metrics)
            button(.bottomStart, .calendar, "Calendars", metrics)
            button(.bottomEnd, .astrology, "Astrology", metrics)
        }
    }

    // MARK: Buttons

    private func button(_ corner: TuckCorner, _ icon: TuckIcon, _ description: String, _ metrics: TuckLayout) -> some View {
        let isOpen = open == corner
        // Bottom buttons stay put under the keyboard, as they do under Android's IME.
        let hidden = corner != .topStart && metrics.keyboard > 0
        return Button {
            open = isOpen ? nil : corner
        } label: {
            TuckIconView(icon: icon, color: isOpen ? InstrumentControls.color(accentColor) : iconColor)
                .frame(width: 24, height: 24)
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .background { Circle().fill(InstrumentControls.color(isOpen ? 0xE020_1A12 : 0x8C00_0000)) }
                .overlay { Circle().strokeBorder(InstrumentControls.color(isOpen ? accentColor : 0x59FF_FFFF), lineWidth: 1) }
                .contentShape(Circle())
                .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(description)
        .accessibilityAddTraits(isOpen ? .isSelected : [])
        .opacity(hidden ? 0 : 1)
        .allowsHitTesting(!hidden)
        .accessibilityHidden(hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: metrics.alignment(corner))
        .padding(metrics.buttonPadding(corner))
    }

    // MARK: Panels

    /// A panel's place: always in the layout, holding the panel only while it is open so it
    /// unfolds from (and tucks back into) its corner.
    private func panelSlot<Content: View>(_ corner: TuckCorner, _ metrics: TuckLayout,
                                          @ViewBuilder _ content: () -> Content) -> some View {
        ZStack(alignment: metrics.alignment(corner)) {
            if open == corner {
                panel(content(), maxHeight: metrics.panelMaxHeight(corner))
                    .frame(width: metrics.panelWidth)
                    .transition(.scale(scale: 0.82, anchor: metrics.anchor(corner)).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: metrics.alignment(corner))
        .padding(metrics.panelPadding(corner))
    }

    private func panel<Content: View>(_ content: Content, maxHeight: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .circular)
        return TuckMaxHeightLayout(maxHeight: maxHeight) {
            ScrollView(.vertical) {
                content.frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .background { shape.fill(InstrumentControls.color(0xF20C_0B0D)) }
        .overlay {
            shape.strokeBorder(InstrumentControls.color(InstrumentControls.withAlpha(accentColor, 120)), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .clipShape(shape)
        .shadow(color: Color.black.opacity(0.45), radius: 12, x: 0, y: 6)
        .accessibilityElement(children: .contain)
        // VoiceOver's escape gesture tucks the panel away, as Back does on Android.
        .accessibilityAction(.escape) { open = nil }
    }
}

/// Where the buttons and panels go, from the screen size, the safe area and the keyboard.
struct TuckLayout {
    let size: CGSize
    let insets: EdgeInsets
    /// The probe's size: the screen above the keyboard.
    let keyboardFreeSize: CGSize

    private var margin: CGFloat { 14 }
    private var buttonSize: CGFloat { 50 }
    private var gap: CGFloat { 8 }

    /// How far the keyboard reaches up from the bottom of the screen. A keyboard never changes the
    /// width, so a probe of another width (the screen is turning) is not a keyboard.
    var keyboard: CGFloat {
        guard keyboardFreeSize.height > 0, abs(keyboardFreeSize.width - size.width) < 0.5 else { return 0 }
        let measured = size.height - keyboardFreeSize.height
        return measured > 1 ? measured : 0
    }

    var top: CGFloat { max(margin, insets.top) }
    var leading: CGFloat { max(margin, insets.leading) }
    var trailing: CGFloat { max(margin, insets.trailing) }
    /// The bottom buttons' margin. While the keyboard is up they are hidden beneath it, and the
    /// safe area's bottom edge is the keyboard's, so the resting margin is used.
    var bottom: CGFloat { keyboard > 0 ? margin : max(margin, insets.bottom) }

    /// min(screen width − margins, 372 dp).
    var panelWidth: CGFloat { max(0, min(size.width - leading - trailing, 372)) }

    /// A bottom panel sits above its button, or 8 points above the keyboard when that is higher.
    var bottomPanelOffset: CGFloat { max(bottom + buttonSize + gap, keyboard + gap) }

    /// place(): the panel may use the height between the button rows at the top and bottom
    /// (whichever corner unfolds), less the keyboard's lift for a bottom panel.
    func panelMaxHeight(_ corner: TuckCorner) -> CGFloat {
        let topReserve = top + buttonSize + gap
        let bottomReserve = corner == .topStart ? bottom + buttonSize + gap : bottomPanelOffset
        return max(0, size.height - topReserve - bottomReserve - 10)
    }

    func alignment(_ corner: TuckCorner) -> Alignment {
        switch corner {
        case .topStart: return .topLeading
        case .bottomStart: return .bottomLeading
        case .bottomEnd: return .bottomTrailing
        }
    }

    /// The pivot the panel unfolds from.
    func anchor(_ corner: TuckCorner) -> UnitPoint {
        switch corner {
        case .topStart: return .topLeading
        case .bottomStart: return .bottomLeading
        case .bottomEnd: return .bottomTrailing
        }
    }

    func buttonPadding(_ corner: TuckCorner) -> EdgeInsets {
        switch corner {
        case .topStart: return EdgeInsets(top: top, leading: leading, bottom: 0, trailing: 0)
        case .bottomStart: return EdgeInsets(top: 0, leading: leading, bottom: bottom, trailing: 0)
        case .bottomEnd: return EdgeInsets(top: 0, leading: 0, bottom: bottom, trailing: trailing)
        }
    }

    func panelPadding(_ corner: TuckCorner) -> EdgeInsets {
        switch corner {
        case .topStart:
            return EdgeInsets(top: top + buttonSize + gap, leading: leading, bottom: 0, trailing: trailing)
        case .bottomStart:
            return EdgeInsets(top: 0, leading: leading, bottom: bottomPanelOffset, trailing: trailing)
        case .bottomEnd:
            return EdgeInsets(top: 0, leading: leading, bottom: bottomPanelOffset, trailing: trailing)
        }
    }
}

/// MaxHeightScrollView: wraps its content up to [maxHeight], then scrolls. The scroll view is
/// asked for its ideal height (its content's, as fixedSize would) and given at most [maxHeight].
struct TuckMaxHeightLayout: Layout {
    var maxHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let ideal = child.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? ideal.width, height: min(ideal.height, maxHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for child in subviews {
            child.place(at: bounds.origin, anchor: .topLeading,
                        proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
        }
    }
}

// MARK: - Icons

/// The Android vector drawables, redrawn in their 24 × 24 viewport.
struct TuckIconView: View {
    let icon: TuckIcon
    let color: Color

    var body: some View {
        SwiftUI.Canvas { context, size in
            context.scaleBy(x: size.width / 24, y: size.height / 24)
            let ink = GraphicsContext.Shading.color(color)
            switch icon {
            case .settings: Self.drawSettings(&context, ink)
            case .calendar: Self.drawCalendar(&context, ink)
            case .astrology: Self.drawAstrology(&context, ink)
            }
        }
        .accessibilityHidden(true)
    }

    private static func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> SwiftUI.Path {
        var path = SwiftUI.Path()
        path.move(to: CGPoint(x: x1, y: y1))
        path.addLine(to: CGPoint(x: x2, y: y2))
        return path
    }

    private static func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> SwiftUI.Path {
        SwiftUI.Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
    }

    /// ic_tuck_settings: three slider rails with their knobs.
    private static func drawSettings(_ context: inout GraphicsContext, _ ink: GraphicsContext.Shading) {
        let rail = StrokeStyle(lineWidth: 1.8, lineCap: .round)
        for (y, knob) in [(CGFloat(6.5), CGFloat(15)), (12, 8.5), (17.5, 13)] {
            context.stroke(line(4, y, 20, y), with: ink, style: rail)
            context.fill(circle(knob, y, 2.3), with: ink)
        }
    }

    /// ic_tuck_calendar: a calendar page with its rings, header and five days.
    private static func drawCalendar(_ context: inout GraphicsContext, _ ink: GraphicsContext.Shading) {
        let page = SwiftUI.Path(roundedRect: CGRect(x: 3, y: 6.5, width: 18, height: 14), cornerRadius: 1.5,
                                style: .circular)
        context.stroke(page, with: ink, style: StrokeStyle(lineWidth: 1.7, lineJoin: .round))

        var header = SwiftUI.Path()
        header.move(to: CGPoint(x: 3, y: 10.5))
        header.addLine(to: CGPoint(x: 3, y: 8))
        header.addArc(tangent1End: CGPoint(x: 3, y: 6.5), tangent2End: CGPoint(x: 4.5, y: 6.5), radius: 1.5)
        header.addLine(to: CGPoint(x: 19.5, y: 6.5))
        header.addArc(tangent1End: CGPoint(x: 21, y: 6.5), tangent2End: CGPoint(x: 21, y: 8), radius: 1.5)
        header.addLine(to: CGPoint(x: 21, y: 10.5))
        header.closeSubpath()
        context.fill(header, with: ink)

        let rings = StrokeStyle(lineWidth: 1.8, lineCap: .round)
        context.stroke(line(8, 4, 8, 8.2), with: ink, style: rings)
        context.stroke(line(16, 4, 16, 8.2), with: ink, style: rings)

        for (x, y) in [(CGFloat(6.3), CGFloat(12.5)), (10.8, 12.5), (15.3, 12.5), (6.3, 16), (10.8, 16)] {
            context.fill(SwiftUI.Path(CGRect(x: x, y: y, width: 2.4, height: 2)), with: ink)
        }
    }

    /// ic_tuck_astrology: a sun of two rings and twelve rays around a four-pointed star.
    private static func drawAstrology(_ context: inout GraphicsContext, _ ink: GraphicsContext.Shading) {
        context.stroke(circle(12, 12, 9.6), with: ink, lineWidth: 1.6)
        context.stroke(circle(12, 12, 6.4), with: ink, lineWidth: 1.1)

        let rays: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (18.18, 13.66, 21.27, 14.48), (16.53, 16.53, 18.79, 18.79), (13.66, 18.18, 14.48, 21.27),
            (10.34, 18.18, 9.52, 21.27), (7.47, 16.53, 5.21, 18.79), (5.82, 13.66, 2.73, 14.48),
            (5.82, 10.34, 2.73, 9.52), (7.47, 7.47, 5.21, 5.21), (10.34, 5.82, 9.52, 2.73),
            (13.66, 5.82, 14.48, 2.73), (16.53, 7.47, 18.79, 5.21), (18.18, 10.34, 21.27, 9.52),
        ]
        var rayPath = SwiftUI.Path()
        for (x1, y1, x2, y2) in rays {
            rayPath.move(to: CGPoint(x: x1, y: y1))
            rayPath.addLine(to: CGPoint(x: x2, y: y2))
        }
        context.stroke(rayPath, with: ink, lineWidth: 1.1)

        var star = SwiftUI.Path()
        star.move(to: CGPoint(x: 12, y: 8.1))
        star.addLine(to: CGPoint(x: 12.92, y: 11.08))
        star.addLine(to: CGPoint(x: 15.9, y: 12))
        star.addLine(to: CGPoint(x: 12.92, y: 12.92))
        star.addLine(to: CGPoint(x: 12, y: 15.9))
        star.addLine(to: CGPoint(x: 11.08, y: 12.92))
        star.addLine(to: CGPoint(x: 8.1, y: 12))
        star.addLine(to: CGPoint(x: 11.08, y: 11.08))
        star.closeSubpath()
        context.fill(star, with: ink)
    }
}
