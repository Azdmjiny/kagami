import Foundation

extension KagamiStore {
    /// Resolve against the selected language, independently of macOS's preferred languages.
    /// Reading `language` here also makes SwiftUI observe changes to the preference.
    func text(_ key: String) -> String {
        guard let url = Bundle.module.url(forResource: language.rawValue, withExtension: "lproj"),
              let bundle = Bundle(url: url) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    func text(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale(identifier: language.rawValue), arguments: arguments)
    }
}
