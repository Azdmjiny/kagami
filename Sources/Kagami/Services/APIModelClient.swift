import Foundation

/// A minimal OpenAI Chat Completions-compatible client. This also works with
/// compatible gateways and self-hosted providers that expose `/chat/completions`.
protocol APIModelServing: Sendable {
    func generate(baseURL: String, apiKey: String, model: String, prompt: String, system: String?) async throws -> String
}

struct APIModelClient: APIModelServing {
    func generate(baseURL: String, apiKey: String, model: String, prompt: String, system: String?) async throws -> String {
        guard let root = URL(string: baseURL), !apiKey.isEmpty, !model.isEmpty else {
            throw KagamiError.configuration("请在设置中填写云端 API 地址、模型和密钥。")
        }
        let endpoint = root.appending(path: "chat/completions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(ChatRequest(
            model: model,
            messages: [
                system.map { Message(role: "system", content: $0) },
                Message(role: "user", content: prompt)
            ].compactMap { $0 },
            responseFormat: ResponseFormat(type: "json_object")
        ))

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw KagamiError.connection(service: "云端 API", detail: "没有收到有效响应。")
            }
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw KagamiError.connection(service: "云端 API", detail: "请求失败（HTTP \(http.statusCode)）。\(body.isEmpty ? "" : " 请检查地址、模型和密钥。")")
            }
            guard let content = try JSONDecoder().decode(ChatResponse.self, from: data).choices.first?.message.content,
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw KagamiError.invalidModelResponse
            }
            return content
        } catch let error as KagamiError {
            throw error
        } catch is DecodingError {
            throw KagamiError.connection(service: "云端 API", detail: "返回格式不兼容 Chat Completions 接口。")
        } catch {
            throw KagamiError.connection(service: "云端 API", detail: "连接超时或网络不可用。")
        }
    }
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [Message]
    let responseFormat: ResponseFormat
    enum CodingKeys: String, CodingKey { case model, messages; case responseFormat = "response_format" }
}

private struct Message: Codable { let role: String; let content: String }
private struct ResponseFormat: Encodable { let type: String }
private struct ChatResponse: Decodable { let choices: [Choice]; struct Choice: Decodable { let message: Message } }
