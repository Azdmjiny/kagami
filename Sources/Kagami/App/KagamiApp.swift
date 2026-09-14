import SwiftUI

@main
struct KagamiApp: App {
    @State private var store = KagamiStore()

    var body: some Scene {
        WindowGroup("Kagami") {
            ContentView(store: store)
                .frame(minWidth: 680, minHeight: 560)
        }
        .defaultSize(width: 760, height: 650)

        Settings {
            SettingsView(store: store)
                .frame(width: 620, height: 640)
        }
    }
}
