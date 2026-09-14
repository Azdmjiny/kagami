import Foundation

protocol AnkiConnecting: Sendable {
    func checkConnection() async throws
    func deckNames() async throws -> [String]
    func modelNames() async throws -> [String]
    func fieldNames(for model: String) async throws -> [String]
    func addNote(deck: String, model: String, fields: [String: String]) async throws
}

struct AnkiConnectClient: AnkiConnecting {
    private let endpoint = URL(string: "http://127.0.0.1:8765")!

    func checkConnection() async throws { _ = try await perform("version", params: EmptyParams()) as Int }
    func deckNames() async throws -> [String] { try await perform("deckNames", params: EmptyParams()) }
    func modelNames() async throws -> [String] { try await perform("modelNames", params: EmptyParams()) }
    func fieldNames(for model: String) async throws -> [String] { try await perform("modelFieldNames", params: ModelParams(modelName: model)) }

    func addNote(deck: String, model: String, fields: [String: String]) async throws {
        let note = Note(deckName: deck, modelName: model, fields: fields, options: NoteOptions(allowDuplicate: true), tags: ["Kagami"])
        let _: Int = try await perform("addNote", params: AddNoteParams(note: note))
    }

    private func perform<Result: Decodable, Params: Encodable>(_ action: String, params: Params) async throws -> Result {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Request(action: action, version: 6, params: params))
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw KagamiError.connection(service: "AnkiConnect", detail: "服务没有正常响应。")
            }
            let envelope = try JSONDecoder().decode(Response<Result>.self, from: data)
            if let error = envelope.error { throw KagamiError.anki(error) }
            guard let result = envelope.result else { throw KagamiError.anki("返回结果为空。") }
            return result
        } catch let error as KagamiError {
            throw error
        } catch {
            throw KagamiError.connection(service: "AnkiConnect", detail: "请打开 Anki，并确认已安装 AnkiConnect 插件。")
        }
    }
}

private struct Request<Params: Encodable>: Encodable { let action: String; let version: Int; let params: Params }
private struct Response<Result: Decodable>: Decodable { let result: Result?; let error: String? }
private struct EmptyParams: Encodable {}
private struct ModelParams: Encodable { let modelName: String }
private struct AddNoteParams: Encodable { let note: Note }
private struct Note: Encodable { let deckName: String; let modelName: String; let fields: [String: String]; let options: NoteOptions; let tags: [String] }
private struct NoteOptions: Encodable { let allowDuplicate: Bool }
