import SundialCore
import SundialCoreGraphics
import SwiftUI

// The shared look of Sundial's native controls: instrument type, brass switches, hairlines.
// A port of core ui/InstrumentControls.kt for the tuck menus' panels.
//
// Android sizes are in sp and dp; here they are points. The label face, Sundial Condensed
// (SundialKit's sundialCondensed face), comes from Font.custom, which scales with Dynamic Type as
// Android's sp scale with the font size setting. Android's letterSpacing (in ems) becomes
// tracking in points: ems × text size.

@MainActor
enum InstrumentControls {
    /// InstrumentControls.BRASS.
    nonisolated static let brass: ARGB = 0xFFFF_B34A

    /// sundial_condensed.ttf, registered at launch (SundialResources.registerFonts()).
    nonisolated static func font(_ size: CGFloat) -> Font {
        .custom(FontLibrary.condensedPostScriptName, size: size)
    }

    /// An Android colour int (0xAARRGGBB) as a SwiftUI colour.
    nonisolated static func color(_ argb: ARGB) -> Color {
        Color(.sRGB,
              red: Double(Colors.red(argb)) / 255,
              green: Double(Colors.green(argb)) / 255,
              blue: Double(Colors.blue(argb)) / 255,
              opacity: Double(Colors.alpha(argb)) / 255)
    }

    /// [argb] with its alpha replaced, as Color.argb(alpha, red(c), green(c), blue(c)).
    nonisolated static func withAlpha(_ argb: ARGB, _ alpha: Int) -> ARGB {
        Colors.argb(alpha, Colors.red(argb), Colors.green(argb), Colors.blue(argb))
    }

    /// label(value, size, color): label-face text in one colour.
    static func text(_ value: String, _ size: CGFloat, _ color: ARGB) -> Text {
        Text(value)
            .font(font(size))
            .foregroundStyle(InstrumentControls.color(color))
    }

    /// label(...) as a full-width, left-aligned view.
    static func label(_ value: String, _ size: CGFloat, _ color: ARGB) -> some View {
        text(value, size, color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// title(value, subtitle): the panel's name, its subtitle and a hairline.
    static func title(_ value: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            text(value, 26, Colors.white)
                .tracking(26 * 0.12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            text(subtitle, 11, 0x99FF_FFFF)
                .tracking(11 * 0.18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
                .padding(.bottom, 14)
            InstrumentHairline()
        }
    }

    /// section(title): a small spaced heading.
    static func section(_ title: String) -> some View {
        text(title, 12, 0x99FF_FFFF)
            .tracking(12 * 0.16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 2)
            .padding(.top, 18)
            .padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

/// hairline(): a one-point rule.
struct InstrumentHairline: View {
    var body: some View {
        Rectangle()
            .fill(InstrumentControls.color(0x38FF_FFFF))
            .frame(maxWidth: .infinity)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// switch(title): a one-line label-face title with a brass switch at its end. [accent] tints the
/// switch (Switch.tint), as the calendar menu does with each calendar's colour.
struct InstrumentSwitch: View {
    let title: String
    @Binding var isOn: Bool
    var accent: ARGB = InstrumentControls.brass
    var minHeight: CGFloat = 50
    /// Android's contentDescription, read after the title (the title stays the label).
    var hint: String? = nil

    init(_ title: String, isOn: Binding<Bool>, accent: ARGB = InstrumentControls.brass,
         minHeight: CGFloat = 50, hint: String? = nil) {
        self.title = title
        _isOn = isOn
        self.accent = accent
        self.minHeight = minHeight
        self.hint = hint
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            InstrumentControls.text(title, 16, Colors.white)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .toggleStyle(InstrumentSwitchStyle(accent: accent, minHeight: minHeight))
        .padding(.leading, 2)
        .padding(.trailing, 4)
        .accessibilityHint(hint ?? "")
    }
}

/// Android's Material switch in Sundial's colours: a thumb in the accent over a translucent
/// accent track when on, grey over a dark track when off.
struct InstrumentSwitchStyle: ToggleStyle {
    var accent: ARGB
    var minHeight: CGFloat = 50

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { configuration.isOn.toggle() }
        } label: {
            HStack(spacing: 12) {
                configuration.label
                    .frame(maxWidth: .infinity, alignment: .leading)
                InstrumentSwitchGlyph(isOn: configuration.isOn, accent: accent)
            }
            .frame(minHeight: minHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRemoveTraits(.isButton)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

/// The switch itself: thumbTintList and trackTintList of InstrumentControls.tint.
struct InstrumentSwitchGlyph: View {
    let isOn: Bool
    let accent: ARGB

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(InstrumentControls.color(isOn ? InstrumentControls.withAlpha(accent, 112) : 0xFF35_393D))
                .frame(width: 34, height: 14)
            Circle()
                .fill(InstrumentControls.color(isOn ? accent : 0xFF8A_8D90))
                .frame(width: 20, height: 20)
                .shadow(color: Color.black.opacity(0.35), radius: 1, x: 0, y: 1)
                .offset(x: isOn ? 14 : 0)
        }
        .frame(width: 34, height: 20)
        .accessibilityHidden(true)
    }
}

/// action(title, description, click): an outlined, full-width row that runs [action]. Disabled
/// actions fade to 46 %, as AstrologyPanel sets their alpha.
struct InstrumentAction: View {
    let title: String
    /// Android's contentDescription: VoiceOver reads it as the hint after the title.
    let description: String
    var enabled = true
    var accessibilityLabel: String? = nil
    var selected = false
    let action: () -> Void

    init(_ title: String, _ description: String, enabled: Bool = true, accessibilityLabel: String? = nil,
         selected: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.description = description
        self.enabled = enabled
        self.accessibilityLabel = accessibilityLabel
        self.selected = selected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            InstrumentControls.text(title, 16, Colors.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, 16)
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        }
        .buttonStyle(InstrumentActionStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.46)
        .padding(.vertical, 4)
        .accessibilityLabel(accessibilityLabel ?? title)
        .accessibilityHint(description)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// outlined(): a dark rounded rectangle with a light hairline, lit while pressed as Android's ripple.
struct InstrumentActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .circular)
        return configuration.label
            .background {
                ZStack {
                    shape.fill(InstrumentControls.color(0x1200_0000))
                    shape.fill(InstrumentControls.color(0x35FF_FFFF))
                        .opacity(configuration.isPressed ? 1 : 0)
                    shape.strokeBorder(InstrumentControls.color(0x45FF_FFFF), lineWidth: 1)
                }
            }
            .contentShape(shape)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
