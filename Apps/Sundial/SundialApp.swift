import SwiftUI

/// The iOS app: MainActivity's life cycle on SwiftUI's. The label face (Sundial Condensed) is
/// registered before anything draws; the scene's phase stands in for onResume (active: the clock
/// runs again, calendar access and the day's horoscope are refreshed) and onPause (inactive or in
/// the background: the clock stops).
@main
struct SundialApp: App {
    @StateObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        SundialResources.registerFonts()
        _model = StateObject(wrappedValue: AppModel())
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    model.scenePhaseChanged(phase)
                }
        }
    }
}
