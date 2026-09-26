import SundialCore
import SwiftUI

/// The lower-left tuck menu: which synced calendars to lay onto the dials. A port of
/// CalendarPanel.kt. Without calendar access it explains what access is for and continues to
/// iOS's request in context (never at launch), or, once iOS will no longer ask, sends the person
/// to Settings.
struct CalendarPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InstrumentControls.title("CALENDARS", "SYNCED · READ ONLY")
            if model.calendarAccess == .granted {
                let calendars = model.deviceCalendars
                if calendars.isEmpty {
                    message("No synced calendars found")
                } else {
                    ForEach(calendars, id: \.id) { calendar in
                        row(calendar)
                    }
                }
            } else {
                // setAccessNeeded(openSettings)
                message("Show events from the calendars synced to this device around Sundial's year and day " +
                    "dials. Access is read-only, and calendar data never leaves your device.")
                // Android's "ALLOW CALENDAR ACCESS" / "ALLOW IN SETTINGS": the button before iOS's
                // own request says CONTINUE, as the HIG and App Review ask of a screen shown ahead
                // of a permission alert (no "Allow"); once iOS no longer asks it opens Settings.
                let denied = model.calendarAccess == .denied
                InstrumentAction(denied ? "OPEN SETTINGS" : "CONTINUE",
                                 denied ? "Open Sundial's page in Settings, where calendar access can be turned on"
                                     : "Continue to the iOS request to read your synced calendars") {
                    model.requestCalendarAccess()
                }
            }
        }
        .padding(EdgeInsets(top: 20, leading: 22, bottom: 14, trailing: 18))
    }

    private func row(_ calendar: DeviceCalendar) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            InstrumentSwitch(calendar.displayName,
                             isOn: Binding(get: { model.isCalendarSelected(calendar.id) },
                                           set: { model.setCalendar(calendar.id, selected: $0) }),
                             accent: calendar.color,
                             minHeight: 46,
                             hint: "Show events from \(calendar.displayName)")
                .padding(.top, 6)
            InstrumentControls.text(calendar.isGoogle ? "Google · \(calendar.accountName)" : calendar.accountName,
                                    11, 0x7AFF_FFFF)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 0, leading: 2, bottom: 5, trailing: 8))
        }
    }

    /// showMessage(message)
    private func message(_ text: String) -> some View {
        InstrumentControls.label(text, 14, 0x99FF_FFFF)
            .padding(EdgeInsets(top: 12, leading: 2, bottom: 14, trailing: 2))
    }
}
