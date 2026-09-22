import SwiftUI

struct LanguageSetupView: View {
    @Bindable var store: KagamiStore

    var body: some View {
        VStack(spacing: 20) {
            Text("Kagami").font(.largeTitle.weight(.semibold))
            Text(store.text("Choose your language / 選擇語言"))
                .font(.title3).foregroundStyle(.secondary)
            Picker(store.text("Language"), selection: Binding(get: { store.language }, set: { store.selectLanguage($0) })) {
                ForEach(AppLanguage.allCases) { language in Text(language.nativeName).tag(language) }
            }
            .pickerStyle(.radioGroup)
            Button(store.text("Continue")) { store.selectLanguage(store.language, completingSetup: true) }
                .buttonStyle(.borderedProminent)
        }
        .padding(36)
        .frame(minWidth: 420, minHeight: 360)
    }
}
