import SwiftUI

struct SettingsView: View {
    @Bindable var store: KagamiStore
    @State private var testWord = ""

    var body: some View {
        Form {
            Section("Ollama") {
                Picker("默认模型", selection: $store.preferences.modelName) {
                    if !store.modelNames.contains(store.preferences.modelName) { Text(store.preferences.modelName).tag(store.preferences.modelName) }
                    ForEach(store.modelNames, id: \.self) { Text($0).tag($0) }
                }
                HStack {
                    Button("读取本地模型") { Task { await store.refreshOllama() } }
                    Text("推荐 qwen3:4b-instruct")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("AnkiConnect") {
                Picker("默认卡组", selection: $store.preferences.defaultDeck) {
                    Text("请选择").tag("")
                    ForEach(store.deckNames, id: \.self) { Text($0).tag($0) }
                }
                Picker("笔记类型", selection: $store.preferences.noteType) {
                    Text("请选择").tag("")
                    ForEach(store.noteTypeNames, id: \.self) { Text($0).tag($0) }
                }
                HStack {
                    Button("连接并刷新") { Task { await store.refreshAnki() } }
                    Button("刷新字段") { Task { await store.performFieldRefresh() } }
                        .disabled(store.preferences.noteType.isEmpty)
                }
                if !store.fieldNames.isEmpty {
                    Text("当前字段：\(store.fieldNames.joined(separator: "、"))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("AI 学习风格") {
                Text("此要求同时用于翻译和制卡。Kagami 会自动保证 JSON 格式与 Anki 字段名。")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $store.preferences.promptStyle).font(.body).frame(minHeight: 100)
            }
            Section("模板测试") {
                TextField("输入单词或短语", text: $testWord)
                HStack {
                    Button("生成字段预览") { Task { await store.testTemplate(word: testWord) } }
                        .disabled(testWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isWorking)
                    if store.isWorking { ProgressView().controlSize(.small) }
                }
                if !store.previewFields.isEmpty {
                    ForEach(store.fieldNames, id: \.self) { name in
                        LabeledContent(name, value: store.previewFields[name, default: ""])
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("无法完成操作", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.clearError() } })) {
            Button("好", role: .cancel) { store.clearError() }
        } message: { Text(store.error?.localizedDescription ?? "未知错误") }
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
