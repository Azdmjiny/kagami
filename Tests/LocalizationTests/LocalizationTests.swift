import XCTest
@testable import Kagami

final class LocalizationTests: XCTestCase {
    func testAllLanguagesCoverInterfaceStrings() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let resources = root.appendingPathComponent("Sources/Kagami/Resources")
        var catalogs: [String: [String: String]] = [:]
        for language in AppLanguage.allCases {
            let data = try Data(contentsOf: resources.appendingPathComponent("\(language.rawValue).lproj/Localizable.strings"))
            catalogs[language.rawValue] = try XCTUnwrap(
                PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
        }
        let reference = try XCTUnwrap(catalogs["en"])
        for (language, catalog) in catalogs {
            XCTAssertEqual(Set(catalog.keys), Set(reference.keys), language)
            XCTAssertFalse(catalog.values.contains(""), language)
            for (key, value) in catalog {
                XCTAssertEqual(value.components(separatedBy: "%@").count,
                               key.components(separatedBy: "%@").count, "\(language): \(key)")
            }
        }
        let pattern = #"store\.text\("([^"]+)""#
        let regex = try NSRegularExpression(pattern: pattern)
        for name in ["ContentView", "SettingsView", "LanguageSetupView"] {
            let source = try String(contentsOf: root.appendingPathComponent("Sources/Kagami/Views/\(name).swift"))
            for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                let key = String(source[Range(match.range(at: 1), in: source)!])
                XCTAssertNotNil(reference[key], "Missing interface string: \(key)")
            }
        }
    }

    @MainActor
    func testSwitchingLanguageUpdatesTextAndPersistsSelection() throws {
        let suite = "KagamiLocalizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = KagamiStore(preferences: .init(defaults: defaults))
        let translations: [(AppLanguage, String)] = [
            (.english, "Input"), (.japanese, "入力"), (.french, "Saisie"),
            (.spanish, "Entrada"), (.russian, "Ввод"),
            (.traditionalChinese, "輸入"), (.simplifiedChinese, "输入")
        ]
        for (language, expected) in translations {
            store.selectLanguage(language, completingSetup: true)
            XCTAssertEqual(store.text("输入"), expected)
            XCTAssertEqual(store.preferences.promptStyle, language.defaultPromptStyle)
            let restored = KagamiStore(preferences: .init(defaults: defaults))
            XCTAssertEqual(restored.language, language)
            XCTAssertEqual(restored.text("输入"), expected)
            XCTAssertTrue(restored.preferences.hasCompletedLanguageSetup)
        }
        store.preferences.promptStyle = "My custom style"
        store.markPromptStyleAsCustom()
        store.selectLanguage(.english)
        XCTAssertEqual(store.preferences.promptStyle, "My custom style")
        XCTAssertEqual(store.text("Unknown key"), "Unknown key")
    }
}
