import Foundation

protocol OllamaServing: Sendable {
    func fetchModels() async throws -> [String]
    func generate(model: String, prompt: String, system: String?) async throws -> String
}

struct OllamaClient: OllamaServing {
    private let baseURL = URL(string: "http://127.0.0.1:11434")!

    func fetchModels() async throws -> [String] {
        let url = baseURL.appending(path: "api/tags")
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            try validate(response, service: "Ollama")
            let decoded = try JSONDecoder().decode(ModelList.self, from: data)
            return decoded.models.map(\.name).sorted()
        } catch let error as KagamiError {
            throw error
        } catch {
            throw KagamiError.connection(service: "Ollama", detail: "请确认 Ollama 已启动。")
        }
    }

    func generate(model: String, prompt: String, system: String?) async throws -> String {
        let url = baseURL.appending(path: "api/generate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90
        request.httpBody = try JSONEncoder().encode(GenerateRequest(model: model, prompt: prompt, stream: false, format: "json", system: system))
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try validate(response, service: "Ollama")
            return try JSONDecoder().decode(GenerateResponse.self, from: data).response
        } catch let error as KagamiError {
            throw error
        } catch {
            throw KagamiError.connection(service: "Ollama", detail: "生成失败，请确认模型已下载且服务正在运行。")
        }
    }

    private func validate(_ response: URLResponse, service: String) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw KagamiError.connection(service: service, detail: "服务没有正常响应。")
        }
    }
}

private struct ModelList: Decodable { let models: [Model]; struct Model: Decodable { let name: String } }
private struct GenerateRequest: Encodable { let model: String; let prompt: String; let stream: Bool; let format: String; let system: String? }
private struct GenerateResponse: Decodable { let response: String }
