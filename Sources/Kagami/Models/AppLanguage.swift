import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"
    case japanese = "ja"
    case spanish = "es"
    case french = "fr"
    case russian = "ru"

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .english: "English"
        case .japanese: "日本語"
        case .spanish: "Español"
        case .french: "Français"
        case .russian: "Русский"
        }
    }

    var promptName: String {
        switch self {
        case .simplifiedChinese: "Simplified Chinese（简体中文）"
        case .traditionalChinese: "Traditional Chinese（繁體中文）"
        case .english: "English"
        case .japanese: "Japanese（日本語）"
        case .spanish: "Spanish（Español）"
        case .french: "French（Français）"
        case .russian: "Russian（Русский）"
        }
    }

    var defaultPromptStyle: String {
        switch self {
        case .simplifiedChinese: "使用自然、简明的简体中文。翻译应准确，释义适合制作记忆卡片。"
        case .traditionalChinese: "使用自然、簡明的繁體中文。翻譯應準確，釋義適合製作記憶卡片。"
        case .english: "Use natural, concise English. Keep translations accurate and definitions suitable for flashcards."
        case .japanese: "自然で簡潔な日本語を使用してください。翻訳は正確で、暗記カードに適した説明にしてください。"
        case .spanish: "Usa un español natural y conciso. La traducción debe ser precisa y adecuada para tarjetas de estudio."
        case .french: "Utilisez un français naturel et concis. La traduction doit être exacte et adaptée aux cartes mémoire."
        case .russian: "Используйте естественный и краткий русский язык. Перевод должен быть точным и подходить для карточек."
        }
    }
}
