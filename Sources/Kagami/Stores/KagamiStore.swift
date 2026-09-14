import Foundation
import Observation

@MainActor @Observable
final class KagamiStore {
    struct Preferences {
        private let defaults: UserDefaults
        var modelName: String { didSet { save() } }
        var defaultDeck: String { didSet { save() } }
        var noteType: String { didSet { save() } }
        var promptStyle: String { didSet { save() } }

        init(defaults: UserDefaults = .standard) {
            self.defaults = defaults
            modelName = defaults.string(forKey: "ollamaModel") ?? "qwen3:4b-instruct"
            defaultDeck = defaults.string(forKey: "ankiDeck") ?? ""
            noteType = defaults.string(forKey: "ankiNoteType") ?? ""
            promptStyle = defaults.string(forKey: "promptStyle") ?? PromptFactory.defaultStyle
        }

        private func save() {
            defaults.set(modelName, forKey: "ollamaModel")
            defaults.set(defaultDeck, forKey: "ankiDeck")
            defaults.set(noteType, forKey: "ankiNoteType")
            defaults.set(promptStyle, forKey: "promptStyle")
        }
    }

    var preferences = Preferences()
    var input = ""
    var translation = ""
    var modelNames: [String] = []
    var deckNames: [String] = []
    var noteTypeNames: [String] = []
    var fieldNames: [String] = []
    var previewFields: [String: String] = [:]
    var isWorking = false
    var error: KagamiError?
    var successMessage: String?
    private var hasRestoredSavedConnections = false

    private let ollama: any OllamaServing
    private let anki: any AnkiConnecting

    init(ollama: any OllamaServing = OllamaClient(), anki: any AnkiConnecting = AnkiConnectClient(), preferences: Preferences = Preferences()) {
        self.ollama = ollama
        self.anki = anki
        self.preferences = preferences
    }

    var canTranslate: Bool { !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !preferences.modelName.isEmpty && !isWorking }
    var canCreateCard: Bool { !input.isEmpty && !translation.isEmpty && !preferences.noteType.isEmpty && !preferences.defaultDeck.isEmpty && !isWorking }

    func clearError() { error = nil }

    /// Rehydrates the saved model, deck, note type, and fields when the app opens.
    /// Startup failures stay quiet: the Settings screen still provides explicit repair actions.
    func restoreSavedConnections() async {
        guard !hasRestoredSavedConnections else { return }
        hasRestoredSavedConnections = true
        isWorking = true
        defer { isWorking = false }

        do {
            modelNames = try await ollama.fetchModels()
        } catch {
            // Ollama may simply not be running yet; preserve the user's saved choice.
        }

        do {
            async let decks = anki.deckNames()
            async let models = anki.modelNames()
            deckNames = try await decks.sorted()
            noteTypeNames = try await models.sorted()
            if !preferences.noteType.isEmpty {
                fieldNames = try await anki.fieldNames(for: preferences.noteType)
            }
        } catch {
            // Anki may not be open yet; Settings > 连接并刷新 remains available.
        }
    }

    func refreshOllama() async {
        await perform {
            self.modelNames = try await self.ollama.fetchModels()
            if self.modelNames.contains(self.preferences.modelName) == false, let first = self.modelNames.first { self.preferences.modelName = first }
            self.successMessage = "已读取 \(self.modelNames.count) 个本地模型。"
        }
    }

    func refreshAnki() async {
        await perform {
            async let decks = self.anki.deckNames()
            async let models = self.anki.modelNames()
            self.deckNames = try await decks.sorted()
            self.noteTypeNames = try await models.sorted()
            if !self.deckNames.contains(self.preferences.defaultDeck) { self.preferences.defaultDeck = self.deckNames.first ?? "" }
            if !self.noteTypeNames.contains(self.preferences.noteType) { self.preferences.noteType = self.noteTypeNames.first ?? "" }
            try await self.refreshFields()
            self.successMessage = "已连接 AnkiConnect。"
        }
    }

    func refreshFields() async throws {
        guard !preferences.noteType.isEmpty else { fieldNames = []; return }
        fieldNames = try await anki.fieldNames(for: preferences.noteType)
    }

    func translate() async {
        let word = input.trimmingCharacters(in: .whitespacesAndNewlines)
        await perform {
            guard !self.preferences.modelName.isEmpty else { throw KagamiError.configuration("请先在设置中选择 Ollama 模型。") }
            let answer = try await self.ollama.generate(model: self.preferences.modelName, prompt: PromptFactory.translation(word: word, style: self.preferences.promptStyle), system: PromptFactory.translationSystem)
            self.translation = try TranslationExtractor.extract(from: answer)
        }
    }

    func generateCard(example: String) async -> Bool {
        let word = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let translated = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        var succeeded = false
        await perform {
            guard !self.preferences.modelName.isEmpty else { throw KagamiError.configuration("请先选择 Ollama 模型。") }
            guard !self.fieldNames.isEmpty else { throw KagamiError.configuration("请在设置中选择 Anki 笔记类型，并刷新字段。") }
            let prompt = PromptFactory.card(word: word, translation: translated, example: example, fields: self.fieldNames, style: self.preferences.promptStyle)
            let answer = try await self.ollama.generate(model: self.preferences.modelName, prompt: prompt, system: nil)
            self.previewFields = try JSONFieldDecoder.decodeFields(from: answer, requiredKeys: self.fieldNames)
            succeeded = true
        }
        return succeeded
    }

    func addCurrentCard(to deck: String) async -> Bool {
        var succeeded = false
        let fields = previewFields
        await perform {
            guard !deck.isEmpty, !self.preferences.noteType.isEmpty else { throw KagamiError.configuration("请选择卡组和笔记类型。") }
            try await self.anki.addNote(deck: deck, model: self.preferences.noteType, fields: fields)
            self.successMessage = "已添加到“\(deck)”。"
            succeeded = true
        }
        return succeeded
    }

    func testTemplate(word: String) async {
        let previousInput = input
        let previousTranslation = translation
        input = word
        await translate()
        if error == nil { _ = await generateCard(example: "") }
        input = previousInput
        translation = previousTranslation
    }

    private func perform(_ work: () async throws -> Void) async {
        error = nil
        successMessage = nil
        isWorking = true
        defer { isWorking = false }
        do { try await work() }
        catch let known as KagamiError { self.error = known }
        catch let unexpected { self.error = .connection(service: "本地服务", detail: unexpected.localizedDescription) }
    }
}
