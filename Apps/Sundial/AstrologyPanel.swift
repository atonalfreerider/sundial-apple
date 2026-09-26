import Combine
import Foundation
import SundialCore
import SwiftUI
import UIKit

/// The typed birth fields of the astrology menu. They outlive the panel (which leaves the view
/// hierarchy when its menu tucks away) as Android's EditTexts outlive a hidden panel, so digits
/// typed but not yet valid are still there when the menu opens again.
@MainActor
final class AstrologyForm: ObservableObject {
    enum Field: Hashable { case month, day, year, hour, minute }

    @Published var month = ""
    @Published var day = ""
    @Published var year = ""
    @Published var hour = ""
    @Published var minute = ""
    /// setMeridiem: PM is selected.
    @Published var pm = false
    /// showValidation: the message under the fields, nil when hidden.
    @Published var validation: String?
    /// The field being typed in, mirrored from the panel's focus: fields in use are not
    /// overwritten from the saved profile (setIfIdle).
    var focused: Field?

    /// The fields' digit limits (InputFilter.LengthFilter).
    static func maxDigits(_ field: Field) -> Int { field == .year ? 4 : 2 }

    /// AstrologyPanel.setZodiacProfile's field part: shows the saved birth date and time unless the
    /// person is typing in that field. (The switch, sign and actions read the profile directly.)
    func setZodiacProfile(_ value: ZodiacProfile) {
        if let date = value.birthDate {
            setIfIdle(.month, Self.pad2(date.month))
            setIfIdle(.day, Self.pad2(date.day))
            setIfIdle(.year, String(date.year))
        }
        if let time = value.birthTime {
            setIfIdle(.hour, String(time.hour % 12 == 0 ? 12 : time.hour % 12))
            setIfIdle(.minute, Self.pad2(time.minute))
            pm = time.hour >= 12
        }
    }

    func text(_ field: Field) -> String {
        switch field {
        case .month: return month
        case .day: return day
        case .year: return year
        case .hour: return hour
        case .minute: return minute
        }
    }

    func setText(_ field: Field, _ value: String) {
        switch field {
        case .month: month = value
        case .day: day = value
        case .year: year = value
        case .hour: hour = value
        case .minute: minute = value
        }
    }

    private func setIfIdle(_ field: Field, _ value: String) {
        if focused != field && text(field) != value { setText(field, value) }
    }

    /// toString().padStart(2, '0')
    private static func pad2(_ value: Int) -> String {
        let text = String(value)
        return text.count < 2 ? String(repeating: "0", count: 2 - text.count) + text : text
    }
}

/// The lower-right tuck menu: every astrology input in one place. A port of AstrologyPanel.kt.
/// Birth date and time are typed straight into the panel and saved as soon as they are valid, so
/// the horoscope can be written without any further step.
struct AstrologyPanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var form: AstrologyForm
    @FocusState private var focus: AstrologyForm.Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InstrumentControls.title("ASTROLOGY", "OPTIONAL ZODIAC · PRIVATE ON DEVICE")
            InstrumentSwitch("ASTROLOGY MODE", isOn: Binding(
                get: { model.zodiacProfile.enabled },
                set: { model.setZodiacEnabled($0) }))
            InstrumentControls.text(Zodiac.Sign.allCases.map { $0.symbol }.joined(separator: " "), 18, 0xFFFF_D88A)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
                .padding(.bottom, 4)
                .accessibilityHidden(true)

            InstrumentControls.section("BIRTH DATE")
            weightedRow([1, 1, 1.7], height: 52) { widths in
                numberField(.month, "MM", "Birth month").frame(width: widths[0])
                numberField(.day, "DD", "Birth day").frame(width: widths[1])
                numberField(.year, "YYYY", "Four digit birth year").frame(width: widths[2])
            }
            weightedRow([1, 1, 1.7], height: 22) { widths in
                caption("MONTH").frame(width: widths[0])
                caption("DAY").frame(width: widths[1])
                caption("YEAR").frame(width: widths[2])
            }

            InstrumentControls.section("BIRTH TIME")
            weightedRow([1, 0.28, 1, 0.9, 0.9], height: 52) { widths in
                numberField(.hour, "HH", "Birth hour").frame(width: widths[0])
                InstrumentControls.text(":", 22, Colors.white)
                    .frame(width: widths[1])
                    .accessibilityHidden(true)
                numberField(.minute, "MM", "Birth minutes").frame(width: widths[2])
                meridiem("AM", selected: !form.pm) { setMeridiem(false) }.frame(width: widths[3])
                meridiem("PM", selected: form.pm) { setMeridiem(true) }.frame(width: widths[4])
            }
            if let validation = form.validation, !Self.isBlank(validation) {
                InstrumentControls.label(validation, 13, 0xFFFF_8F7A)
                    .padding(EdgeInsets(top: 4, leading: 2, bottom: 0, trailing: 2))
            }

            InstrumentControls.section("SUN SIGN")
            InstrumentAction(signTitle, "Choose zodiac sign") { model.showZodiacSignPicker() }

            InstrumentControls.section("TODAY'S HOROSCOPE")
            if let reading = model.readingText {
                // The reading in full, with its AI disclosure: on short screens the instrument's
                // card falls back to one card without them and cuts the reading short.
                InstrumentControls.label(reading, 13, 0xE6FF_FFFF)
                    .padding(EdgeInsets(top: 2, leading: 4, bottom: 4, trailing: 4))
                InstrumentControls.label("Written by on-device AI · tap REPORT THIS READING to report", 11, 0x99FF_FFFF)
                    .padding(EdgeInsets(top: 0, leading: 4, bottom: 6, trailing: 4))
            }
            InstrumentAction("WRITE A NEW READING", "Write today's private horoscope with Apple Intelligence",
                             enabled: model.zodiacProfile.isComplete) {
                model.generateHoroscope(automatic: false)
            }
            InstrumentAction("REPORT THIS READING", "Report today's AI-written horoscope",
                             enabled: model.hasReading) {
                model.showReportDialog()
            }
            InstrumentControls.label(model.horoscopeStatus, 12, 0x99FF_FFFF)
                .padding(EdgeInsets(top: 6, leading: 4, bottom: 4, trailing: 4))
            if case .unavailable(let reason) = model.horoscopeAvailability, reason != model.horoscopeStatus {
                // Why this device cannot write a reading, as Android says when Gemini Nano is missing.
                InstrumentControls.label(reason, 12, 0x99FF_FFFF)
                    .padding(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
            }
            InstrumentControls.label("Readings are written by on-device AI for entertainment only.", 11, 0x77FF_FFFF)
                .padding(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
        }
        .padding(EdgeInsets(top: 20, leading: 22, bottom: 16, trailing: 18))
        .onChange(of: focus) { _, value in form.focused = value }
        .onChange(of: form.month) { _, value in edited(.month, value, next: .day, commit: commitDate) }
        .onChange(of: form.day) { _, value in edited(.day, value, next: .year, commit: commitDate) }
        .onChange(of: form.year) { _, value in edited(.year, value, next: .hour, commit: commitDate) }
        .onChange(of: form.hour) { _, value in edited(.hour, value, next: .minute, commit: commitTime) }
        .onChange(of: form.minute) { _, value in edited(.minute, value, next: nil, commit: commitTime) }
        // setSelectAllOnFocus(true): a tapped field's digits are selected, so typing replaces them.
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { note in
            guard let field = note.object as? UITextField else { return }
            DispatchQueue.main.async {
                field.selectedTextRange = field.textRange(from: field.beginningOfDocument, to: field.endOfDocument)
            }
        }
        .toolbar {
            // The number pad has no return key: NEXT stands for Android's IME_ACTION_NEXT (month →
            // day → year → hour → minute; the minute field has IME_ACTION_DONE, so NEXT is off
            // there), and DONE closes the keyboard from any field. Moving focus selects the next
            // field's digits (the select-all handler above), as setSelectAllOnFocus does; the date
            // and time are already committed on every edit.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("NEXT") {
                    if let next = Self.next(after: focus) { focus = next }
                }
                .font(InstrumentControls.font(17))
                .disabled(Self.next(after: focus) == nil)
                Button("DONE") { focus = nil }
                    .font(InstrumentControls.font(17))
            }
        }
        .onAppear {
            form.focused = nil
            model.refreshHoroscopeAvailability()
        }
        .onDisappear { form.focused = nil }
    }

    /// "♈︎  ARIES  · FROM BIRTHDAY", or without the note for a sign chosen by hand.
    private var signTitle: String {
        let profile = model.zodiacProfile
        let sign = profile.resolvedSign()
        let fromBirthday = profile.selectedSign == nil || profile.birthDate.map(Zodiac.signFor) == profile.selectedSign
        return "\(sign.symbol)  \(sign.displayName.uppercased())" + (fromBirthday ? "  · FROM BIRTHDAY" : "")
    }

    // MARK: Editing

    /// A field changed: keep its digits (TYPE_CLASS_NUMBER, LengthFilter), and when the person typed
    /// it, move on once it is full (advance) and try the date or time (afterTextChanged). Changes
    /// from the saved profile only reach fields not in use, and commit nothing.
    private func edited(_ field: AstrologyForm.Field, _ value: String, next: AstrologyForm.Field?,
                        commit: () -> Void) {
        let digits = String(value.filter { $0.isASCII && $0.isNumber }.prefix(AstrologyForm.maxDigits(field)))
        if digits != value {
            form.setText(field, digits)
            return
        }
        guard focus == field else { return }
        if let next, value.count >= AstrologyForm.maxDigits(field) { focus = next }
        commit()
    }

    /// The field Android's IME_ACTION_NEXT moves to; nil for the minute field (IME_ACTION_DONE).
    private static func next(after field: AstrologyForm.Field?) -> AstrologyForm.Field? {
        guard let field else { return nil }
        switch field {
        case .month: return .day
        case .day: return .year
        case .year: return .hour
        case .hour: return .minute
        case .minute: return nil
        }
    }

    private func commitDate() {
        let parts = [form.month, form.day, form.year]
        if parts.contains(where: Self.isBlank) || form.year.count < 4 {
            form.validation = nil
            return
        }
        do {
            let date = try BirthDateInput.parse(parts[0], parts[1], parts[2])
            form.validation = nil
            if date != model.zodiacProfile.birthDate { model.setBirthDate(date) }
        } catch {
            form.validation = Self.message(error)
        }
    }

    private func commitTime() {
        let hour = form.hour
        let minute = form.minute
        if Self.isBlank(hour) || Self.isBlank(minute) {
            form.validation = nil
            return
        }
        do {
            let time = try BirthTimeInput.parse(hour, minute, form.pm)
            form.validation = nil
            if time != model.zodiacProfile.birthTime { model.setBirthTime(time) }
        } catch {
            form.validation = Self.message(error)
        }
    }

    private func setMeridiem(_ value: Bool) {
        form.pm = value
        commitTime()
    }

    private static func message(_ error: Error) -> String {
        (error as? BirthInputError)?.message ?? error.localizedDescription
    }

    /// Kotlin's isBlank().
    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Views

    /// A row of cells sized by [weights] (LinearLayout weights), 6 points apart.
    private func weightedRow<Content: View>(_ weights: [CGFloat], height: CGFloat,
                                            @ViewBuilder _ content: @escaping ([CGFloat]) -> Content) -> some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 6
            let available = max(0, geometry.size.width - spacing * CGFloat(weights.count - 1))
            let total = weights.reduce(0, +)
            HStack(spacing: spacing) {
                content(weights.map { available * $0 / total })
            }
        }
        .frame(height: height)
    }

    private func numberField(_ field: AstrologyForm.Field, _ hint: String, _ description: String) -> some View {
        TextField("", text: binding(field),
                  prompt: Text(hint).font(InstrumentControls.font(20)).foregroundStyle(InstrumentControls.color(0x55FF_FFFF)))
            .font(InstrumentControls.font(20))
            .foregroundStyle(Color.white)
            .multilineTextAlignment(.center)
            .keyboardType(.numberPad)
            .tint(Color.white)
            .focused($focus, equals: field)
            .accessibilityLabel(description)
            .frame(maxHeight: .infinity)
            .background {
                // The whole cell focuses its field, not only the line of text.
                RoundedRectangle(cornerRadius: 12, style: .circular)
                    .fill(InstrumentControls.color(0x14FF_FFFF))
                    .contentShape(Rectangle())
                    .onTapGesture { focus = field }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .circular)
                    .strokeBorder(InstrumentControls.color(0x45FF_FFFF), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }

    private func binding(_ field: AstrologyForm.Field) -> Binding<String> {
        switch field {
        case .month: return $form.month
        case .day: return $form.day
        case .year: return $form.year
        case .hour: return $form.hour
        case .minute: return $form.minute
        }
    }

    private func caption(_ text: String) -> some View {
        InstrumentControls.text(text, 10, 0x88FF_FFFF)
            .tracking(10 * 0.12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }

    private func meridiem(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            InstrumentControls.text(label, 15, selected ? Colors.black : Colors.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .circular)
                        .fill(InstrumentControls.color(selected ? InstrumentControls.brass : 0x1200_0000))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .circular)
                        .strokeBorder(InstrumentControls.color(selected ? InstrumentControls.brass : 0x45FF_FFFF),
                                      lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Birth time is \(label)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// MainActivity.showZodiacSignPicker: "Natal sun sign", automatic from the birthday or one of the
/// twelve signs, applied as soon as it is chosen.
struct ZodiacSignPicker: View {
    let profile: ZodiacProfile
    /// Android's `which`: 0 for AUTOMATIC FROM BIRTHDAY, n for the n-th sign.
    let onSelect: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let checked = profile.selectedSign.map { $0.ordinal + 1 } ?? 0
        NavigationStack {
            List {
                ForEach(0...Zodiac.Sign.allCases.count, id: \.self) { which in
                    Button {
                        onSelect(which)
                        dismiss()
                    } label: {
                        HStack {
                            Text(Self.label(which))
                                .font(InstrumentControls.font(18))
                                .foregroundStyle(Color.primary)
                            Spacer()
                            if which == checked {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(InstrumentControls.color(InstrumentControls.brass))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityAddTraits(which == checked ? .isSelected : [])
                }
            }
            .navigationTitle("Natal sun sign")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("CANCEL") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private static func label(_ which: Int) -> String {
        if which == 0 { return "AUTOMATIC FROM BIRTHDAY" }
        let sign = Zodiac.Sign.allCases[which - 1]
        return "\(sign.symbol)  \(sign.displayName.uppercased())"
    }
}
