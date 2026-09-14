import SwiftUI

struct ContentView: View {
    @Bindable var store: KagamiStore
    @State private var showAddSheet = false
    @State private var showPreview = false
    @State private var chosenDeck = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            GroupBox("输入") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("输入单词或短语", text: $store.input)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            guard store.canTranslate else { return }
                            Task { await store.translate() }
                        }
                    HStack {
                        Text("自动识别语言，翻译为简体中文")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("生成翻译") { Task { await store.translate() } }
                            .disabled(!store.canTranslate)
                    }
                }
                .padding(4)
            }

            GroupBox("翻译") {
                TextEditor(text: $store.translation)
                    .font(.body)
                    .frame(minHeight: 150)
                    .overlay(alignment: .topLeading) {
                        if store.translation.isEmpty {
                            Text("翻译结果将在这里出现，并且可以手动修改。")
                                .foregroundStyle(.tertiary)
                                .padding(8)
                                .allowsHitTesting(false)
                        }
                    }
            }

            Spacer(minLength: 0)
            HStack {
                if store.isWorking { ProgressView().controlSize(.small) }
                Spacer()
                Button("添加到 Anki") {
                    chosenDeck = store.preferences.defaultDeck
                    showAddSheet = true
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(!store.canCreateCard)
            }
        }
        .padding(24)
        .toolbar { ToolbarItem(placement: .primaryAction) { SettingsLink { Label("设置", systemImage: "gearshape") } } }
        .task { await store.restoreSavedConnections() }
        .sheet(isPresented: $showAddSheet) {
            AddCardSheet(store: store, deck: $chosenDeck) {
                showAddSheet = false
                showPreview = true
            }
        }
        .sheet(isPresented: $showPreview) {
            CardPreviewSheet(store: store, deck: $chosenDeck) { showPreview = false }
        }
        .alert("无法完成操作", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.clearError() } })) {
            Button("好", role: .cancel) { store.clearError() }
        } message: { Text(store.error?.localizedDescription ?? "未知错误") }
        .alert("Kagami", isPresented: Binding(get: { store.successMessage != nil }, set: { if !$0 { store.successMessage = nil } })) {
            Button("好") { store.successMessage = nil }
        } message: { Text(store.successMessage ?? "") }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Kagami").font(.largeTitle.weight(.semibold))
                Text("翻译、确认，再写入你的 Anki 卡组。")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

private struct AddCardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: KagamiStore
    @Binding var deck: String
    let onPreview: () -> Void
    @State private var example = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("准备卡片").font(.title2.weight(.semibold))
            Picker("写入卡组", selection: $deck) {
                ForEach(store.deckNames, id: \.self) { Text($0).tag($0) }
            }
            TextField("例句（可选，留空则由 AI 生成）", text: $example, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
            Text("下一步将按当前 Anki 笔记类型的字段名生成内容，供你确认。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("生成卡片预览") {
                    Task { if await store.generateCard(example: example) { onPreview() } }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isWorking || deck.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}

private struct CardPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: KagamiStore
    @Binding var deck: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("确认写入内容").font(.title2.weight(.semibold))
            Picker("目标卡组", selection: $deck) { ForEach(store.deckNames, id: \.self) { Text($0).tag($0) } }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(store.fieldNames, id: \.self) { name in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(name).font(.headline)
                            TextEditor(text: Binding(get: { store.previewFields[name, default: ""] }, set: { store.previewFields[name] = $0 }))
                                .font(.body).frame(minHeight: 64).padding(4)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                        }
                    }
                }
            }
            HStack {
                Button("取消") { onClose(); dismiss() }
                Spacer()
                Button("确认添加") {
                    Task { if await store.addCurrentCard(to: deck) { onClose(); dismiss() } }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isWorking || deck.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 600, height: 620)
    }
}
