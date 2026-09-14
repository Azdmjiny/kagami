import Foundation

@main
struct KagamiModelChecks {
    static func main() async {
        do {
            let fenced = try JSONFieldDecoder.decodeFields(from: "```json\n{\"正面\":\"apple\",\"背面\":\"苹果\"}\n```")
            try require(fenced["正面"] == "apple", "无法解析 Markdown JSON。")
            try require(fenced["背面"] == "苹果", "无法解析中文字段。")
            let nestedTranslation = try TranslationExtractor.extract(from: "{\"translation\":\"{\\\"translation\\\":\\\"避孕套\\\"}\"}")
            try require(nestedTranslation == "避孕套", "未清理嵌套的翻译 JSON。")

            do {
                _ = try JSONFieldDecoder.decodeFields(from: "{\"正面\":\"apple\"}", requiredKeys: ["正面", "背面"])
                throw CheckFailure(message: "缺少字段时未拒绝模型输出。")
            } catch is KagamiError { }

            let prompt = PromptFactory.card(word: "apple", translation: "苹果", example: "", fields: ["Front", "Back"], style: "简洁")
            try require(prompt.contains("\"Front\"") && prompt.contains("\"Back\""), "提示词未包含全部 Anki 字段。")
            try require(prompt.contains("自行生成自然例句"), "跳过例句时提示词不完整。")

            try await verifiesCardWorkflowWithMockServices()
            try await verifiesSavedConnectionRestore()
            try await verifiesServiceFailuresReachTheUIState()
            print("Kagami model checks passed")
        } catch {
            fputs("Kagami model checks failed: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw CheckFailure(message: message) }
    }

    @MainActor
    private static func verifiesCardWorkflowWithMockServices() async throws {
        let ollama = MockOllama(responses: ["{\"translation\":\"苹果\"}", "{\"Front\":\"apple\",\"Back\":\"苹果；一种水果\"}"])
        let anki = MockAnki()
        let store = makeTestStore(ollama: ollama, anki: anki)
        await store.refreshOllama()
        await store.refreshAnki()
        store.input = "apple"
        await store.translate()
        try require(store.translation == "苹果", "翻译结果未写回主界面。")
        try require(await store.generateCard(example: "I ate an apple."), "无法生成字段预览。")
        try require(store.previewFields["Back"] == "苹果；一种水果", "字段预览内容错误。")
        try require(await store.addCurrentCard(to: "词汇"), "无法确认写入卡片。")
        let note = await anki.lastNote
        try require(note?.deck == "词汇" && note?.model == "词汇卡", "写入卡组或笔记类型错误。")
        try require(note?.fields["Front"] == "apple", "写入 Anki 的字段错误。")
    }

    @MainActor
    private static func verifiesServiceFailuresReachTheUIState() async throws {
        let store = makeTestStore(ollama: FailingOllama(), anki: MockAnki())
        store.input = "apple"
        await store.translate()
        try require(store.error != nil, "Ollama 失败没有显示给界面。")
    }

    @MainActor
    private static func verifiesSavedConnectionRestore() async throws {
        let store = makeTestStore(ollama: MockOllama(responses: []), anki: MockAnki())
        store.preferences.modelName = "qwen3:4b-instruct"
        store.preferences.defaultDeck = "词汇"
        store.preferences.noteType = "词汇卡"
        await store.restoreSavedConnections()
        try require(store.modelNames.contains("qwen3:4b-instruct"), "启动时没有恢复 Ollama 模型列表。")
        try require(store.deckNames.contains("词汇"), "启动时没有恢复 Anki 卡组。")
        try require(store.fieldNames == ["Front", "Back"], "启动时没有恢复笔记类型字段。")
    }

    @MainActor
    private static func makeTestStore(ollama: any OllamaServing, anki: any AnkiConnecting) -> KagamiStore {
        let suiteName = "KagamiModelChecks"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return KagamiStore(ollama: ollama, anki: anki, preferences: .init(defaults: defaults))
    }
}

private struct CheckFailure: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private actor MockOllama: OllamaServing {
    private var responses: [String]
    init(responses: [String]) { self.responses = responses }
    func fetchModels() async throws -> [String] { ["qwen3:4b-instruct"] }
    func generate(model: String, prompt: String, system: String?) async throws -> String {
        guard !responses.isEmpty else { throw KagamiError.invalidModelResponse }
        return responses.removeFirst()
    }
}

private actor FailingOllama: OllamaServing {
    func fetchModels() async throws -> [String] { throw KagamiError.connection(service: "Ollama", detail: "未运行") }
    func generate(model: String, prompt: String, system: String?) async throws -> String { throw KagamiError.connection(service: "Ollama", detail: "未运行") }
}

private actor MockAnki: AnkiConnecting {
    struct SavedNote: Sendable { let deck: String; let model: String; let fields: [String: String] }
    var lastNote: SavedNote?
    func checkConnection() async throws {}
    func deckNames() async throws -> [String] { ["词汇"] }
    func modelNames() async throws -> [String] { ["词汇卡"] }
    func fieldNames(for model: String) async throws -> [String] { ["Front", "Back"] }
    func addNote(deck: String, model: String, fields: [String: String]) async throws { lastNote = SavedNote(deck: deck, model: model, fields: fields) }
}
