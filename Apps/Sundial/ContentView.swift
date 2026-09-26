import SundialCore
import SwiftUI

/// MainActivity's window: the instrument with the system bars hidden (Android's immersive mode),
/// the three tuck menus in its corners, and the dialogs and toasts MainActivity shows.
///
/// The instrument runs under the bottom and side safe areas but not the top one: its clock and
/// the Earth view's zone caption are drawn at the top centre, where an iPhone's Dynamic Island or
/// notch would cover them (Android's small punch-hole camera sits in the clock's gap). With the
/// status bar hidden the top inset is 0 on iPad and in iPhone landscape, so only portrait iPhones
/// with a notch or an island start the dial below it, on the window's black, as Android 8–14 does
/// in fullscreen with the default cutout mode. (SundialKit has no top inset for its chrome yet.)
struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            InstrumentView(model: model.instrumentModel)
                .ignoresSafeArea(.all, edges: [.bottom, .horizontal])

            TuckMenuHost(open: $model.openMenu, iconColor: InstrumentControls.color(model.style.chromeColor)) {
                SettingsPanel(model: model)
            } calendar: {
                CalendarPanel(model: model)
            } astrology: {
                AstrologyPanel(model: model, form: model.astrologyForm)
            }

            if let toast = model.toast {
                ToastView(text: toast.text)
                    .id(toast.id)
                    .transition(.opacity)
            }
        }
        .background(Color.black)
        .animation(.easeOut(duration: 0.2), value: model.toast)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .sheet(isPresented: $model.showingSignPicker) {
            ZodiacSignPicker(profile: model.zodiacProfile) { which in
                model.selectZodiacSign(which)
            }
        }
        .sheet(item: $model.reportRequest) { request in
            ReportSheet { reason in
                model.sendReport(request, reason: reason)
            }
        }
        .onOpenURL { url in
            model.openURL(url)
        }
    }
}

/// Android's Toast: a short message in a dark rounded box near the bottom of the screen, which
/// passes touches through.
struct ToastView: View {
    let text: String

    var body: some View {
        VStack {
            Spacer()
            InstrumentControls.text(text, 15, Colors.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background { Capsule().fill(InstrumentControls.color(0xE633_3333)) }
                .padding(.horizontal, 32)
                .padding(.bottom, 88)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
