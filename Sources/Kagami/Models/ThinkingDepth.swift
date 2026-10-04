import Foundation

enum ThinkingDepth: String, CaseIterable, Hashable, Sendable {
    case automatic, fast, balanced, deep

    var title: String {
        switch self {
        case .automatic: "模型默认"
        case .fast: "快速（少思考）"
        case .balanced: "均衡"
        case .deep: "深入"
        }
    }

    var reasoningEffort: String? {
        switch self {
        case .automatic: nil
        case .fast: "low"
        case .balanced: "medium"
        case .deep: "high"
        }
    }
}

struct ModelGeneration: Sendable {
    let text: String
    var usedDefaultThinking = false
}

enum ThinkingValue: Codable, Equatable, Sendable {
    case toggle(Bool)
    case level(String)

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let toggle = try? container.decode(Bool.self) { self = .toggle(toggle) }
        else { self = .level(try container.decode(String.self)) }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .toggle(let value): try container.encode(value)
        case .level(let value): try container.encode(value)
        }
    }
}

enum ThinkingCompatibility {
    /// Retry only explicit parameter rejections, never authorization, rate limits or outages.
    static func isRejection(status: Int, data: Data, parameter: String) -> Bool {
        guard status == 400 || status == 422,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        let error = json["error"] as? [String: Any]
        let message = ((error?["message"] as? String) ?? (json["error"] as? String) ?? (json["message"] as? String) ?? "").lowercased()
        let param = error?["param"] as? String
        let mentionsParameter = param == parameter || message.contains(parameter)
        let rejection = ["unsupported", "not supported", "does not support", "invalid", "unrecognized", "unknown", "unexpected", "not allowed", "must be"].contains { message.contains($0) }
        return mentionsParameter && rejection
    }
}
