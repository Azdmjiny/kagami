import SwiftUI

@main
struct KagamiApp: App {
    @State private var store = KagamiStore()
    private let updateManager = UpdateManager()

    var body: some Scene {
        Window("Kagami", id: "main") {
            Group {
                if store.preferences.hasCompletedLanguageSetup {
                    ContentView(store: store)
                } else {
                    LanguageSetupView(store: store)
                }
            }
            .frame(minWidth: 680, minHeight: 560)
            .environment(\.locale, Locale(identifier: store.preferences.languageCode))
        }
        .defaultSize(width: 760, height: 650)

        Settings {
            SettingsView(store: store, updateManager: updateManager)
                .frame(width: 620, height: 640)
                .environment(\.locale, Locale(identifier: store.preferences.languageCode))
        }
    }
}
