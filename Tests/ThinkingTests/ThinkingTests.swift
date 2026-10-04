import Foundation
import XCTest
@testable import Kagami

final class ThinkingTests: XCTestCase {
    private let cloudAnswer = #"{"choices":[{"message":{"role":"assistant","content":"{\"translation\":\"苹果\"}"}}]}"#
    private let localAnswer = #"{"response":"{\"translation\":\"苹果\"}"}"#

    func testCloudDepthsAndDefaultPreserveJSONRequest() async throws {
        let (server, session, baseURL) = fixture(replies: Array(repeating: .init(body: cloudAnswer), count: 4))
        let client = APIModelClient(session: session)
        for depth in ThinkingDepth.allCases {
            _ = try await client.generate(baseURL: baseURL.absoluteString, apiKey: "test-key", model: "test", prompt: "apple", system: "JSON only", thinking: depth)
        }
        for (request, depth) in zip(server.requests, ThinkingDepth.allCases) {
            XCTAssertEqual(request.path, "/v1/chat/completions")
            XCTAssertEqual(request.body["reasoning_effort"] as? String, depth.reasoningEffort)
            XCTAssertEqual(request.body["model"] as? String, "test")
            XCTAssertEqual((request.body["response_format"] as? [String: String])?["type"], "json_object")
            XCTAssertEqual((request.body["messages"] as? [[String: String]])?.map { $0["role"]! }, ["system", "user"])
        }
    }

    func testCloudParameterRejectionRetriesSameModelAndCachesPerDepth() async throws {
        let rejection = #"{"error":{"param":"reasoning_effort","message":"Unsupported value: low"}}"#
        let (server, session, baseURL) = fixture(replies: [.init(status: 400, body: rejection)] + Array(repeating: .init(body: cloudAnswer), count: 3))
        let client = APIModelClient(session: session)
        let first = try await client.generate(baseURL: baseURL.absoluteString, apiKey: "test-key", model: "test", prompt: "apple", system: nil, thinking: .fast)
        let second = try await client.generate(baseURL: baseURL.absoluteString, apiKey: "test-key", model: "test", prompt: "pear", system: nil, thinking: .fast)
        let deep = try await client.generate(baseURL: baseURL.absoluteString, apiKey: "test-key", model: "test", prompt: "pear", system: nil, thinking: .deep)
        XCTAssertTrue(first.usedDefaultThinking)
        XCTAssertTrue(second.usedDefaultThinking)
        XCTAssertFalse(deep.usedDefaultThinking)
        XCTAssertEqual(server.requests.map { $0.body["reasoning_effort"] as? String }, ["low", nil, nil, "high"])
        XCTAssertEqual(server.requests.map { $0.body["model"] as? String }, Array(repeating: "test", count: 4))
        XCTAssertEqual(first.text, #"{"translation":"苹果"}"#)
    }

    func testCloudDoesNotRetryAuthorizationRateLimitOutageOrOtherParameters() async throws {
        let rejected = #"{"error":{"message":"reasoning_effort is unsupported"}}"#
        let replies = [Reply(status: 401, body: rejected), .init(status: 429, body: rejected), .init(status: 500, body: rejected), .init(status: 400, body: #"{"error":{"param":"response_format","message":"Unsupported response_format"}}"#)]
        let (server, session, baseURL) = fixture(replies: replies)
        let client = APIModelClient(session: session)
        for _ in replies {
            do {
                _ = try await client.generate(baseURL: baseURL.absoluteString, apiKey: "test-key", model: "test", prompt: "apple", system: nil, thinking: .fast)
                XCTFail("A service failure must remain a failure")
            } catch { }
        }
        XCTAssertEqual(server.requests.count, 4)
        XCTAssertTrue(server.requests.allSatisfy { $0.body["reasoning_effort"] as? String == "low" })
    }

    func testFailedCloudRetryDoesNotCacheUnsupportedDepth() async throws {
        let (server, session, baseURL) = fixture(replies: [
            .init(status: 400, body: #"{"error":{"message":"Unsupported parameter: reasoning_effort"}}"#),
            .init(status: 500, body: #"{"error":"unavailable"}"#), .init(body: cloudAnswer)
        ])
        let client = APIModelClient(session: session)
        do {
            _ = try await client.generate(baseURL: baseURL.absoluteString, apiKey: "test-key", model: "test", prompt: "apple", system: nil, thinking: .fast)
            XCTFail("Failed default retry must throw")
        } catch { }
        _ = try await client.generate(baseURL: baseURL.absoluteString, apiKey: "test-key", model: "test", prompt: "apple", system: nil, thinking: .fast)
        XCTAssertEqual(server.requests.map { $0.body["reasoning_effort"] as? String }, ["low", nil, "low"])
    }

    func testLocalToggleModelDisablesThinkingForFastAndCachesDiscovery() async throws {
        let (server, session, baseURL) = fixture(replies: [
            .init(body: #"{"thinking":{"values":[true,false],"default":true}}"#),
            .init(body: localAnswer), .init(body: localAnswer)
        ])
        let client = OllamaClient(baseURL: baseURL, session: session)
        let fast = try await client.generate(model: "qwen", prompt: "apple", system: "JSON only", thinking: .fast)
        _ = try await client.generate(model: "qwen", prompt: "apple", system: nil, thinking: .deep)
        XCTAssertFalse(fast.usedDefaultThinking)
        XCTAssertEqual(server.requests.map(\.path), ["/v1/api/show", "/v1/api/generate", "/v1/api/generate"])
        XCTAssertEqual(server.requests[1].body["think"] as? Bool, false)
        XCTAssertEqual(server.requests[2].body["think"] as? Bool, true)
        XCTAssertEqual(server.requests[1].body["format"] as? String, "json")
        XCTAssertEqual(server.requests[1].body["stream"] as? Bool, false)
        XCTAssertEqual(server.requests[1].body["system"] as? String, "JSON only")
    }

    func testLocalNamedLevelsSendStringsIncludingLowForFast() async throws {
        let (server, session, baseURL) = fixture(replies: [
            .init(body: #"{"thinking":{"values":["low","medium","high"],"default":"medium"}}"#)
        ] + Array(repeating: .init(body: localAnswer), count: 3))
        let client = OllamaClient(baseURL: baseURL, session: session)
        for depth in [ThinkingDepth.fast, .balanced, .deep] {
            _ = try await client.generate(model: "gpt-oss:20b", prompt: "apple", system: nil, thinking: depth)
        }
        XCTAssertEqual(server.requests.dropFirst().map { $0.body["think"] as? String }, ["low", "medium", "high"])
    }

    func testLocalDefaultSkipsDiscoveryAndNonThinkingModelOmitsParameter() async throws {
        let (server, session, baseURL) = fixture(replies: [
            .init(body: localAnswer), .init(body: #"{"thinking":{"values":[false],"default":false}}"#), .init(body: localAnswer)
        ])
        let client = OllamaClient(baseURL: baseURL, session: session)
        let automatic = try await client.generate(model: "instruct", prompt: "apple", system: nil, thinking: .automatic)
        let fast = try await client.generate(model: "instruct", prompt: "apple", system: nil, thinking: .fast)
        XCTAssertFalse(automatic.usedDefaultThinking)
        XCTAssertTrue(fast.usedDefaultThinking)
        XCTAssertEqual(server.requests.map(\.path), ["/v1/api/generate", "/v1/api/show", "/v1/api/generate"])
        XCTAssertTrue(server.requests.allSatisfy { $0.body["think"] == nil })
    }

    func testOlderLocalCapabilitiesUseCorrectParameterType() async throws {
        for (model, expected) in [("gpt-oss:20b", ThinkingValue.level("low")), ("qwen3:8b", .toggle(false))] {
            let (server, session, baseURL) = fixture(replies: [.init(body: #"{"capabilities":["completion","thinking"]}"#), .init(body: localAnswer)])
            let client = OllamaClient(baseURL: baseURL, session: session)
            _ = try await client.generate(model: model, prompt: "apple", system: nil, thinking: .fast)
            let data = try JSONSerialization.data(withJSONObject: server.requests[1].body["think"]!, options: .fragmentsAllowed)
            XCTAssertEqual(try JSONDecoder().decode(ThinkingValue.self, from: data), expected)
        }
    }

    func testLocalRejectionRetriesOnceAndRefreshClearsCachedCompatibility() async throws {
        let details = Reply(body: #"{"thinking":{"values":[true,false]}}"#)
        let (server, session, baseURL) = fixture(replies: [details,
            .init(status: 400, body: #"{"error":"think is not supported by this model"}"#),
            .init(body: localAnswer), .init(body: localAnswer), .init(body: #"{"models":[{"name":"qwen"}]}"#), details, .init(body: localAnswer)
        ])
        let client = OllamaClient(baseURL: baseURL, session: session)
        let first = try await client.generate(model: "qwen", prompt: "apple", system: nil, thinking: .fast)
        let second = try await client.generate(model: "qwen", prompt: "apple", system: nil, thinking: .fast)
        XCTAssertTrue(first.usedDefaultThinking)
        XCTAssertTrue(second.usedDefaultThinking)
        _ = try await client.fetchModels()
        let afterRefresh = try await client.generate(model: "qwen", prompt: "apple", system: nil, thinking: .fast)
        XCTAssertFalse(afterRefresh.usedDefaultThinking)
        XCTAssertEqual(server.requests.count, 7)
        XCTAssertEqual(server.requests[1].body["think"] as? Bool, false)
        XCTAssertNil(server.requests[2].body["think"])
        XCTAssertNil(server.requests[3].body["think"])
        XCTAssertEqual(server.requests[6].body["think"] as? Bool, false)
    }

    func testLocalDiscoveryFailureUsesDefaultWithoutCachingFailure() async throws {
        let (server, session, baseURL) = fixture(replies: [
            .init(status: 500, body: #"{"error":"unavailable"}"#), .init(body: localAnswer),
            .init(body: #"{"thinking":{"values":[true,false]}}"#), .init(body: localAnswer)
        ])
        let client = OllamaClient(baseURL: baseURL, session: session)
        let first = try await client.generate(model: "qwen", prompt: "apple", system: nil, thinking: .fast)
        let second = try await client.generate(model: "qwen", prompt: "apple", system: nil, thinking: .fast)
        XCTAssertTrue(first.usedDefaultThinking)
        XCTAssertFalse(second.usedDefaultThinking)
        XCTAssertNil(server.requests[1].body["think"])
        XCTAssertEqual(server.requests[3].body["think"] as? Bool, false)
    }

    @MainActor
    func testPreferencesPersistAndTasksPassTheirOwnDepthIncludingLocalFallback() async throws {
        let suite = "KagamiThinkingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var preferences = KagamiStore.Preferences(defaults: defaults)
        XCTAssertEqual(preferences.translationThinking, .fast)
        XCTAssertEqual(preferences.cardThinking, .fast)
        preferences.translationThinking = .balanced
        preferences.cardThinking = .deep
        preferences.cloudEnabled = true
        preferences.cloudModelName = "test"
        let restored = KagamiStore.Preferences(defaults: defaults)
        XCTAssertEqual(restored.translationThinking, .balanced)
        XCTAssertEqual(restored.cardThinking, .deep)
        let api = RecordingAPI()
        let ollama = RecordingOllama()
        let store = KagamiStore(ollama: ollama, api: api, apiKeyStore: TestKey(), preferences: restored)
        store.input = "apple"
        store.fieldNames = ["Front", "Back"]
        await store.translate()
        XCTAssertNil(store.error)
        let generated = await store.generateCard(example: "")
        XCTAssertTrue(generated)
        let depths = await api.depths
        XCTAssertEqual(depths, [.balanced, .deep])
        await api.fail()
        await store.translate()
        XCTAssertNil(store.error)
        let localDepths = await ollama.depths
        XCTAssertEqual(localDepths, [.balanced])
        XCTAssertTrue(store.modelStatus.contains("回退"))
        XCTAssertTrue(store.modelStatus.contains("思考设置不可用"))
        defaults.set("invalid", forKey: "translationThinking")
        XCTAssertEqual(KagamiStore.Preferences(defaults: defaults).translationThinking, .fast)
    }

    private func fixture(replies: [Reply]) -> (StubServer, URLSession, URL) {
        let host = "\(UUID().uuidString.lowercased()).invalid"
        let server = StubServer(replies: replies)
        StubProtocol.register(server, host: host)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: config)
        addTeardownBlock { session.invalidateAndCancel(); StubProtocol.unregister(host: host) }
        return (server, session, URL(string: "https://\(host)/v1")!)
    }
}

private struct Reply { var status = 200; let body: String }
private struct RecordedRequest { let path: String; let body: [String: Any] }

private final class StubServer: @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [Reply]
    private var recorded: [RecordedRequest] = []
    init(replies: [Reply]) { self.replies = replies }
    var requests: [RecordedRequest] { lock.lock(); defer { lock.unlock() }; return recorded }
    func respond(to request: URLRequest) throws -> Reply {
        lock.lock(); defer { lock.unlock() }
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        let body = data.isEmpty ? [:] : try JSONSerialization.jsonObject(with: data) as! [String: Any]
        recorded.append(RecordedRequest(path: request.url!.path, body: body))
        guard !replies.isEmpty else { throw URLError(.resourceUnavailable) }
        return replies.removeFirst()
    }
}

private final class StubProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var servers: [String: StubServer] = [:]
    static func register(_ server: StubServer, host: String) { lock.lock(); defer { lock.unlock() }; servers[host] = server }
    static func unregister(host: String) { lock.lock(); defer { lock.unlock() }; servers.removeValue(forKey: host) }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host?.hasSuffix(".invalid") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let server = Self.servers[request.url!.host!]
        Self.lock.unlock()
        do {
            let reply = try XCTUnwrap(server).respond(to: request)
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}

private actor RecordingAPI: APIModelServing {
    var depths: [ThinkingDepth] = []
    private var shouldFail = false
    func fail() { shouldFail = true }
    func generate(baseURL: String, apiKey: String, model: String, prompt: String, system: String?, thinking: ThinkingDepth) async throws -> ModelGeneration {
        depths.append(thinking)
        if shouldFail { throw KagamiError.connection(service: "云端 API", detail: "离线") }
        return ModelGeneration(text: system == nil ? #"{"Front":"apple","Back":"苹果"}"# : #"{"translation":"苹果"}"#)
    }
}

private actor RecordingOllama: OllamaServing {
    var depths: [ThinkingDepth] = []
    func fetchModels() async throws -> [String] { ["test"] }
    func generate(model: String, prompt: String, system: String?, thinking: ThinkingDepth) async throws -> ModelGeneration {
        depths.append(thinking)
        return ModelGeneration(text: #"{"translation":"苹果"}"#, usedDefaultThinking: true)
    }
}

private struct TestKey: APIKeyStoring {
    func load() throws -> String? { "fake-key" }
    func containsKey() throws -> Bool { true }
    func save(_ key: String) throws { }
}
