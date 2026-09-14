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
    static let defaultStyle = """
    使用自然、简明的简体中文。翻译应准确，释义适合制作记忆卡片；例句要自然并体现词义。
    """

    static let translationSystem = """
    你是 Kagami 的翻译引擎。你的 JSON 回复仅供应用内部解析，用户永远不应看见 JSON。
    你必须只返回一个合法 JSON 对象：{"translation":"..."}。
    translation 的值必须是最终给用户看的纯简体中文译文：不得包含 JSON、字段名、Markdown、代码围栏或解释性前缀。
    """

    static func translation(word: String, style: String) -> String {
        """
        自动识别输入语言并翻译为简体中文。
        用户的学习风格要求：
        \(style)

        输入：\(word)
        只翻译该输入。
        """
    }

    static func card(word: String, translation: String, example: String, fields: [String], style: String) -> String {
        let fieldList = fields.map { "\"\($0)\"" }.joined(separator: ", ")
        let exampleInstruction = example.isEmpty ? "用户没有提供例句，请在需要例句的字段中自行生成自然例句。" : "用户提供的例句是：\(example)。优先在对应例句字段使用它。"
        return """
        你是严谨的语言学习助手。自动识别原词语言，使用简体中文生成学习卡片内容。
        用户的学习风格要求：
        \(style)

        原词或短语：\(word)
        用户确认的翻译：\(translation)
        \(exampleInstruction)

        Anki 笔记类型的字段名为：[\(fieldList)]。
        根据字段名推断其含义，并为每一个字段输出合适的纯文本内容。必须返回一个 JSON 对象，键名必须与所有字段名完全一致，值必须是字符串。不要使用 Markdown、代码围栏或额外解释。
        """
    }
}
