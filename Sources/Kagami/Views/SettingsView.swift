import SwiftUI

struct SettingsView: View {
    @Bindable var store: KagamiStore
    let updateManager: UpdateManager
    @State private var testWord = ""
    @State private var apiKey = ""

    var body: some View {
        Form {
            Section(store.text("语言")) {
                Picker(store.text("界面与翻译语言"), selection: Binding(get: { store.preferences.languageCode }, set: { value in
                    if let language = AppLanguage(rawValue: value) { store.selectLanguage(language) }
                })) {
                    ForEach(AppLanguage.allCases) { language in Text(language.nativeName).tag(language.rawValue) }
                }
                Text(store.text("更改语言立即生效；新生成的翻译和卡片将使用该语言。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Ollama") {
                Picker(store.text("默认模型"), selection: $store.preferences.modelName) {
                    if !store.modelNames.contains(store.preferences.modelName) { Text(store.preferences.modelName).tag(store.preferences.modelName) }
                    ForEach(store.modelNames, id: \.self) { Text($0).tag($0) }
                }
                HStack {
                    Button(store.text("读取本地模型")) { Task { await store.refreshOllama() } }
                    Text(store.text("推荐 qwen3:4b-instruct"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section(store.text("云端 API")) {
                Toggle(store.text("优先使用云端模型"), isOn: $store.preferences.cloudEnabled)
                Text(store.text("联网时优先调用云端；连接超时、断网或请求失败时可自动改用下方的本地 Ollama 模型。"))
                    .font(.caption).foregroundStyle(.secondary)
                TextField(store.text("兼容 API 地址"), text: $store.preferences.cloudBaseURL)
                    .textFieldStyle(.roundedBorder)
                TextField(store.text("云端模型名称"), text: $store.preferences.cloudModelName)
                    .textFieldStyle(.roundedBorder)
                SecureField(store.text(store.hasStoredAPIKey ? "已保存；输入新密钥以替换" : "API 密钥（保存在 macOS 钥匙串）"), text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button(store.text("保存 API 密钥")) {
                        if store.updateAPIKey(apiKey) { apiKey = "" }
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if store.hasStoredAPIKey {
                        Button(store.text("移除已保存的 API 密钥"), role: .destructive) {
                            if store.updateAPIKey("") { apiKey = "" }
                        }
                    }
                }
                Toggle(store.text("云端失败时回退本地模型"), isOn: $store.preferences.fallbackToLocal)
                Text(store.text("默认接口是 OpenAI 兼容的 Chat Completions：例如 https://api.openai.com/v1。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("AnkiConnect") {
                Picker(store.text("默认卡组"), selection: $store.preferences.defaultDeck) {
                    Text(store.text("请选择")).tag("")
                    ForEach(store.deckNames, id: \.self) { Text($0).tag($0) }
                }
                Picker(store.text("笔记类型"), selection: $store.preferences.noteType) {
                    Text(store.text("请选择")).tag("")
                    ForEach(store.noteTypeNames, id: \.self) { Text($0).tag($0) }
                }
                HStack {
                    Button(store.text("连接并刷新")) { Task { await store.refreshAnki() } }
                    Button(store.text("刷新字段")) { Task { await store.performFieldRefresh() } }
                        .disabled(store.preferences.noteType.isEmpty)
                }
                if !store.fieldNames.isEmpty {
                    Text(store.text("当前字段：%@", store.fieldNames.joined(separator: ", ")))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section(store.text("AI 学习风格")) {
                Text(store.text("此要求同时用于翻译和制卡。Kagami 会自动保证 JSON 格式与 Anki 字段名。"))
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: Binding(get: { store.preferences.promptStyle }, set: { value in
                    store.preferences.promptStyle = value
                    store.markPromptStyleAsCustom()
                })).font(.body).frame(minHeight: 100)
            }
            Section(store.text("模板测试")) {
                TextField(store.text("输入单词或短语"), text: $testWord)
                HStack {
                    Button(store.text("生成字段预览")) { Task { await store.testTemplate(word: testWord) } }
                        .disabled(testWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isWorking)
                    if store.isWorking { ProgressView().controlSize(.small) }
                }
                if !store.previewFields.isEmpty {
                    ForEach(store.fieldNames, id: \.self) { name in
                        LabeledContent(name, value: store.previewFields[name, default: ""])
                    }
                }
            }
            Section(store.text("更新")) {
                Button(store.text("检查更新")) { updateManager.checkForUpdates() }
                    .disabled(!updateManager.isConfigured)
                Text(store.text(updateManager.isConfigured ? "仅检查正式版。发现新版后可一键下载、安装并重启。" : "开发构建未配置更新签名；正式发布版会启用检查更新。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { store.refreshAPIKeyStatus() }
        .alert(store.text("无法完成操作"), isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.clearError() } })) {
            Button(store.text("好"), role: .cancel) { store.clearError() }
        } message: { Text(store.error?.localizedDescription ?? store.text("未知错误")) }
    }
}

private extension KagamiStore {
    func performFieldRefresh() async {
        error = nil
        isWorking = true
        defer { isWorking = false }
        do { try await refreshFields(); successMessage = "已刷新字段。" }
        catch let known as KagamiError { self.error = known }
        catch let unexpected { self.error = .connection(service: "AnkiConnect", detail: unexpected.localizedDescription) }
    }
}
