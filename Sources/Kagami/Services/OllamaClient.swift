import Foundation

protocol OllamaServing: Sendable {
    func fetchModels() async throws -> [String]
    func generate(model: String, prompt: String, system: String?, thinking: ThinkingDepth) async throws -> ModelGeneration
}

actor OllamaClient: OllamaServing {
    private let baseURL: URL
    private let session: URLSession
    private var modelDetails: [String: ModelDetails] = [:]
    private var unsupportedSettings: Set<SettingKey> = []

    init(baseURL: URL = URL(string: "http://127.0.0.1:11434")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func fetchModels() async throws -> [String] {
        let url = baseURL.appending(path: "api/tags")
        do {
            let (data, response) = try await session.data(from: url)
            try validate(response, service: "Ollama")
            let decoded = try JSONDecoder().decode(ModelList.self, from: data)
            modelDetails.removeAll()
            unsupportedSettings.removeAll()
            return decoded.models.map(\.name).sorted()
        } catch let error as KagamiError {
            throw error
        } catch {
            throw KagamiError.connection(service: "Ollama", detail: "请确认 Ollama 已启动。")
        }
    }

    func generate(model: String, prompt: String, system: String?, thinking: ThinkingDepth) async throws -> ModelGeneration {
        let url = baseURL.appending(path: "api/generate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90
        do {
            let key = SettingKey(model: model, thinking: thinking)
            let details = thinking == .automatic ? nil : await details(for: model)
            let value = unsupportedSettings.contains(key) ? nil : details?.value(for: thinking, model: model)
            var payload = GenerateRequest(model: model, prompt: prompt, stream: false, format: "json", system: system, think: value)
            var (data, response) = try await send(request: request, payload: payload)
            var usedDefaultThinking = thinking != .automatic && value == nil
            if let http = response as? HTTPURLResponse, value != nil,
               ThinkingCompatibility.isRejection(status: http.statusCode, data: data, parameter: "think") {
                payload.think = nil
                (data, response) = try await send(request: request, payload: payload)
                usedDefaultThinking = true
            }
            try validate(response, service: "Ollama")
            let text = try JSONDecoder().decode(GenerateResponse.self, from: data).response
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw KagamiError.invalidModelResponse }
            // Cache only confirmed rejections, not temporary discovery failures.
            if usedDefaultThinking && value != nil { unsupportedSettings.insert(key) }
            return ModelGeneration(text: text, usedDefaultThinking: usedDefaultThinking)
        } catch let error as KagamiError {
            throw error
        } catch {
            throw KagamiError.connection(service: "Ollama", detail: "生成失败，请确认模型已下载且服务正在运行。")
        }
    }

    private func send(request: URLRequest, payload: GenerateRequest) async throws -> (Data, URLResponse) {
        var request = request
        request.httpBody = try JSONEncoder().encode(payload)
        return try await session.data(for: request)
    }

    private func details(for model: String) async -> ModelDetails? {
        if let cached = modelDetails[model] { return cached }
        var request = URLRequest(url: baseURL.appending(path: "api/show"))
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["model": model])
        do {
            let (data, response) = try await session.data(for: request)
            try validate(response, service: "Ollama")
            let details = try JSONDecoder().decode(ModelDetails.self, from: data)
            modelDetails[model] = details
            return details
        } catch { return nil }
    }

    private struct SettingKey: Hashable {
        let model: String
        let thinking: ThinkingDepth
    }

    private func validate(_ response: URLResponse, service: String) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw KagamiError.connection(service: service, detail: "服务没有正常响应。")
        }
    }
}

private struct ModelList: Decodable { let models: [Model]; struct Model: Decodable { let name: String } }
private struct GenerateRequest: Encodable {
    let model: String
    let prompt: String
    let stream: Bool
    let format: String
    let system: String?
    var think: ThinkingValue?
}
private struct GenerateResponse: Decodable { let response: String }

private struct ModelDetails: Decodable, Sendable {
    struct Thinking: Decodable, Sendable { let values: [ThinkingValue] }
    let thinking: Thinking?
    let capabilities: [String]?

    func value(for depth: ThinkingDepth, model: String) -> ThinkingValue? {
        guard let effort = depth.reasoningEffort else { return nil }
        if let values = thinking?.values {
            let level = ThinkingValue.level(effort)
            if values.contains(level) { return level }
            let toggle = ThinkingValue.toggle(depth != .fast)
            if values.contains(toggle), values.contains(.toggle(true)) { return toggle }
            return nil
        }
        // Older Ollama versions report capabilities without thinking.values.
        guard capabilities?.contains("thinking") == true else { return nil }
        let name = model.split(separator: "/").last?.split(separator: ":").first
        if name == "gpt-oss" { return .level(effort) }
        return .toggle(depth != .fast)
    }
}
