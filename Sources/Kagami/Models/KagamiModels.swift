import Foundation

struct CardDraft: Equatable {
    let word: String
    let translation: String
    let example: String
    let fields: [String: String]
}

enum KagamiError: LocalizedError, Equatable {
    case configuration(String)
    case connection(service: String, detail: String)
    case invalidModelResponse
    case anki(String)

    var errorDescription: String? {
        switch self {
        case .configuration(let message): message
        case .connection(let service, let detail): "无法连接 \(service)：\(detail)"
        case .invalidModelResponse: "模型没有返回可用的字段内容，请调整提示词后重试。"
        case .anki(let message): "AnkiConnect 返回错误：\(message)"
        }
    }
}

enum JSONFieldDecoder {
    static func decodeFields(from text: String, requiredKeys: [String] = []) throws -> [String: String] {
        let trimmed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") else {
            throw KagamiError.invalidModelResponse
        }
        let json = String(trimmed[start...end])
        guard let data = json.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw KagamiError.invalidModelResponse
        }

        var fields: [String: String] = [:]
        for (key, value) in object {
            if let text = value as? String {
                fields[key] = text
            } else if let value = value as? NSNumber {
                fields[key] = value.stringValue
            }
        }
        guard !fields.isEmpty, requiredKeys.allSatisfy({ fields[$0] != nil }) else {
            throw KagamiError.invalidModelResponse
        }
        return fields
    }
}

enum TranslationExtractor {
    static func extract(from modelResponse: String) throws -> String {
        let firstPass = try JSONFieldDecoder.decodeFields(from: modelResponse, requiredKeys: ["translation"])
        let value = (firstPass["translation"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        // Some small local models occasionally put the transport JSON inside the
        // translation value. Recover the user-facing text instead of displaying it.
        if value.first == "{", let nested = try? JSONFieldDecoder.decodeFields(from: value, requiredKeys: ["translation"]), let translation = nested["translation"] {
            return translation.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !value.isEmpty else { throw KagamiError.invalidModelResponse }
        return value
    }
}

enum PromptFactory {
    static let defaultStyle = AppLanguage.simplifiedChinese.defaultPromptStyle

    static func translationSystem(targetLanguage: AppLanguage) -> String {
        """
        You are Kagami's translation engine. Your JSON reply is parsed internally and is never shown to the user.
        Return exactly one valid JSON object: {"translation":"..."}.
        The translation value must be the final user-facing translation in \(targetLanguage.promptName). Do not include JSON, field names, Markdown, code fences, or explanatory prefixes inside it.
        """
    }

    static func translation(word: String, style: String, targetLanguage: AppLanguage) -> String {
        """
        Detect the input language automatically and translate it into \(targetLanguage.promptName).
        The user's learning-style instructions are:
        \(style)

        Input: \(word)
        Translate only that input.
        """
    }

    static func card(word: String, translation: String, example: String, fields: [String], style: String, targetLanguage: AppLanguage) -> String {
        let fieldList = fields.map { "\"\($0)\"" }.joined(separator: ", ")
        let exampleInstruction = example.isEmpty ? "The user did not provide an example. Generate natural examples in the input word's language wherever an example is needed." : "The user's example is: \(example). Preserve it verbatim wherever appropriate; do not translate or rewrite it."
        return """
        You are a precise language-learning assistant. Detect the source language automatically.
        Write every newly generated definition, explanation, grammar note, and other non-example content in \(targetLanguage.promptName). Write every newly generated example sentence in the input word's language. Never translate or alter an example supplied by the user.
        The user's learning-style instructions are:
        \(style)

        Source word or phrase: \(word)
        User-confirmed translation: \(translation)
        \(exampleInstruction)

        The Anki note type has these field names: [\(fieldList)].
        Infer each field's intent from its name and return suitable plain text for every field. Return exactly one JSON object whose keys exactly match all field names and whose values are strings. Do not use Markdown, code fences, or extra explanation.
        """
    }
}
