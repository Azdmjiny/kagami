import Foundation
import Observation

@MainActor @Observable
final class KagamiStore {
    struct Preferences {
        private let defaults: UserDefaults
        var modelName: String { didSet { save() } }
        var cloudEnabled: Bool { didSet { save() } }
        var cloudBaseURL: String { didSet { save() } }
        var cloudModelName: String { didSet { save() } }
        var fallbackToLocal: Bool { didSet { save() } }
        var defaultDeck: String { didSet { save() } }
        var noteType: String { didSet { save() } }
        var promptStyle: String { didSet { save() } }
        var languageCode: String { didSet { save() } }
        var hasCompletedLanguageSetup: Bool { didSet { save() } }
        var usesDefaultPromptStyle: Bool { didSet { save() } }

        init(defaults: UserDefaults = .standard) {
            self.defaults = defaults
            modelName = defaults.string(forKey: "ollamaModel") ?? "qwen3:4b-instruct"
            cloudEnabled = defaults.bool(forKey: "cloudEnabled")
            cloudBaseURL = defaults.string(forKey: "cloudBaseURL") ?? "https://api.openai.com/v1"
            cloudModelName = defaults.string(forKey: "cloudModelName") ?? ""
            fallbackToLocal = defaults.object(forKey: "fallbackToLocal") as? Bool ?? true
            defaultDeck = defaults.string(forKey: "ankiDeck") ?? ""
            noteType = defaults.string(forKey: "ankiNoteType") ?? ""
            promptStyle = defaults.string(forKey: "promptStyle") ?? PromptFactory.defaultStyle
            languageCode = defaults.string(forKey: "languageCode") ?? AppLanguage.simplifiedChinese.rawValue
            hasCompletedLanguageSetup = defaults.object(forKey: "hasCompletedLanguageSetup") as? Bool ?? false
            usesDefaultPromptStyle = (defaults.object(forKey: "usesDefaultPromptStyle") as? Bool) ?? (defaults.string(forKey: "promptStyle") == nil)
        }

        private func save() {
            defaults.set(modelName, forKey: "ollamaModel")
            defaults.set(cloudEnabled, forKey: "cloudEnabled")
            defaults.set(cloudBaseURL, forKey: "cloudBaseURL")
            defaults.set(cloudModelName, forKey: "cloudModelName")
            defaults.set(fallbackToLocal, forKey: "fallbackToLocal")
            defaults.set(defaultDeck, forKey: "ankiDeck")
            defaults.set(noteType, forKey: "ankiNoteType")
            defaults.set(promptStyle, forKey: "promptStyle")
            defaults.set(languageCode, forKey: "languageCode")
            defaults.set(hasCompletedLanguageSetup, forKey: "hasCompletedLanguageSetup")
            defaults.set(usesDefaultPromptStyle, forKey: "usesDefaultPromptStyle")
        }
    }

    var preferences = Preferences()
    var language: AppLanguage { AppLanguage(rawValue: preferences.languageCode) ?? .simplifiedChinese }
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
    var modelStatus = ""
    private var hasRestoredSavedConnections = false
    private var cachedAPIKey: String?
    private(set) var hasStoredAPIKey = false

    private let ollama: any OllamaServing
    private let api: any APIModelServing
    private let apiKeyStore: any APIKeyStoring
    private let anki: any AnkiConnecting

    init(ollama: any OllamaServing = OllamaClient(), api: any APIModelServing = APIModelClient(), apiKeyStore: any APIKeyStoring = APIKeyStore(), anki: any AnkiConnecting = AnkiConnectClient(), preferences: Preferences = Preferences()) {
        self.ollama = ollama
        self.api = api
        self.apiKeyStore = apiKeyStore
        self.anki = anki
        self.preferences = preferences
    }

    var hasAvailableModel: Bool { !preferences.modelName.isEmpty || (preferences.cloudEnabled && !preferences.cloudModelName.isEmpty) }
    var canTranslate: Bool { !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasAvailableModel && !isWorking }
    var canCreateCard: Bool { !input.isEmpty && !translation.isEmpty && !preferences.noteType.isEmpty && !preferences.defaultDeck.isEmpty && !isWorking }

    func clearError() { error = nil }

    func selectLanguage(_ language: AppLanguage, completingSetup: Bool = false) {
        preferences.languageCode = language.rawValue
        if preferences.usesDefaultPromptStyle { preferences.promptStyle = language.defaultPromptStyle }
        if completingSetup { preferences.hasCompletedLanguageSetup = true }
    }

    func markPromptStyleAsCustom() { preferences.usesDefaultPromptStyle = false }

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
            let answer = try await self.generate(prompt: PromptFactory.translation(word: word, style: self.preferences.promptStyle, targetLanguage: self.language), system: PromptFactory.translationSystem(targetLanguage: self.language))
            self.translation = try TranslationExtractor.extract(from: answer)
        }
    }

    func generateCard(example: String) async -> Bool {
        let word = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let translated = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        var succeeded = false
        await perform {
            guard !self.fieldNames.isEmpty else { throw KagamiError.configuration("请在设置中选择 Anki 笔记类型，并刷新字段。") }
            let prompt = PromptFactory.card(word: word, translation: translated, example: example, fields: self.fieldNames, style: self.preferences.promptStyle, targetLanguage: self.language)
            let answer = try await self.generate(prompt: prompt, system: nil)
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
        modelStatus = ""
        isWorking = true
        defer { isWorking = false }
        do { try await work() }
        catch let known as KagamiError { self.error = known }
        catch let unexpected { self.error = .connection(service: "本地服务", detail: unexpected.localizedDescription) }
    }

    /// Only explicit work reads the secret. Successful authorization is reused until quit.
    func loadAPIKey() throws -> String {
        if let cachedAPIKey { return cachedAPIKey }
        let key = try apiKeyStore.load() ?? ""
        hasStoredAPIKey = !key.isEmpty
        if !key.isEmpty { cachedAPIKey = key }
        return key
    }

    func refreshAPIKeyStatus() {
        do { hasStoredAPIKey = try apiKeyStore.containsKey() }
        catch let known as KagamiError { error = known }
        catch { self.error = .configuration(error.localizedDescription) }
    }

    @discardableResult
    func updateAPIKey(_ key: String) -> Bool {
        let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try apiKeyStore.save(cleaned)
            cachedAPIKey = cleaned.isEmpty ? nil : cleaned
            hasStoredAPIKey = !cleaned.isEmpty
            error = nil
            return true
        } catch let known as KagamiError { error = known }
        catch { self.error = .configuration(error.localizedDescription) }
        return false
    }

    private func generate(prompt: String, system: String?) async throws -> String {
        if preferences.cloudEnabled {
            // Authorization failures must reach the UI, not silently fall back to a local model.
            let apiKey = preferences.cloudModelName.isEmpty ? "" : try loadAPIKey()
            if !preferences.cloudModelName.isEmpty, !apiKey.isEmpty {
                do {
                    let answer = try await api.generate(baseURL: preferences.cloudBaseURL, apiKey: apiKey, model: preferences.cloudModelName, prompt: prompt, system: system)
                    modelStatus = "已使用云端模型：\(preferences.cloudModelName)"
                    return answer
                } catch {
                    guard preferences.fallbackToLocal, !preferences.modelName.isEmpty else { throw error }
                    modelStatus = "云端不可用，已回退本地模型：\(preferences.modelName)"
                }
            } else if !preferences.fallbackToLocal {
                throw KagamiError.configuration("请在设置中填写云端模型和 API 密钥，或开启本地回退。")
            }
        }
        guard !preferences.modelName.isEmpty else { throw KagamiError.configuration("没有可用模型。请配置云端 API，或选择本地 Ollama 模型。") }
        let answer = try await ollama.generate(model: preferences.modelName, prompt: prompt, system: system)
        if modelStatus.isEmpty { modelStatus = "已使用本地模型：\(preferences.modelName)" }
        return answer
    }
}
