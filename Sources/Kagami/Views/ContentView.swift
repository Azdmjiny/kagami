import SwiftUI

struct ContentView: View {
    @Bindable var store: KagamiStore
    @State private var showAddSheet = false
    @State private var showPreview = false
    @State private var chosenDeck = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            GroupBox(store.text("输入")) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField(store.text("输入单词或短语"), text: $store.input)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            guard store.canTranslate else { return }
                            Task { await store.translate() }
                        }
                    HStack {
                        Text(store.text("自动识别语言，翻译为所选语言"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(store.text("生成翻译")) { Task { await store.translate() } }
                            .disabled(!store.canTranslate)
                    }
                }
                .padding(4)
            }

            GroupBox(store.text("翻译")) {
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $store.translation)
                        .font(.body)
                        .frame(minHeight: 150)
                        .overlay(alignment: .topLeading) {
                            if store.translation.isEmpty {
                                Text(store.text("翻译结果将在这里出现，并且可以手动修改。"))
                                    .foregroundStyle(.tertiary)
                                    .padding(8)
                                    .allowsHitTesting(false)
                            }
                        }
                    if !store.modelStatus.isEmpty {
                        Label(store.modelStatus, systemImage: store.modelStatus.contains("回退") ? "arrow.triangle.2.circlepath" : "cpu")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)
            HStack {
                if store.isWorking { ProgressView().controlSize(.small) }
                Spacer()
                Button(store.text("添加到 Anki")) {
                    chosenDeck = store.preferences.defaultDeck
                    showAddSheet = true
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(!store.canCreateCard)
            }
        }
        .padding(24)
        .toolbar { ToolbarItem(placement: .primaryAction) { SettingsLink { Label(store.text("设置"), systemImage: "gearshape") } } }
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
        .alert(store.text("无法完成操作"), isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.clearError() } })) {
            Button(store.text("好"), role: .cancel) { store.clearError() }
        } message: { Text(store.error?.localizedDescription ?? store.text("未知错误")) }
        .alert("Kagami", isPresented: Binding(get: { store.successMessage != nil }, set: { if !$0 { store.successMessage = nil } })) {
            Button(store.text("好")) { store.successMessage = nil }
        } message: { Text(store.successMessage ?? "") }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Kagami").font(.largeTitle.weight(.semibold))
                Text(store.text("翻译、确认，再写入你的 Anki 卡组。"))
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
            Text(store.text("准备卡片")).font(.title2.weight(.semibold))
            Picker(store.text("写入卡组"), selection: $deck) {
                ForEach(store.deckNames, id: \.self) { Text($0).tag($0) }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(store.text("例句（可选，留空则由 AI 生成）"))
                    .font(.subheadline)
                TextEditor(text: $example)
                    .font(.body)
                    .frame(height: 160)
                    .padding(4)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                    .accessibilityLabel(store.text("例句（可选，留空则由 AI 生成）"))
            }
            Text(store.text("下一步将按当前 Anki 笔记类型的字段名生成内容，供你确认。"))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(store.text("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(store.text("生成卡片预览")) {
                    Task { if await store.generateCard(example: example) { onPreview() } }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isWorking || deck.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 600)
    }
}

private struct CardPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: KagamiStore
    @Binding var deck: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(store.text("确认写入内容")).font(.title2.weight(.semibold))
            Picker(store.text("目标卡组"), selection: $deck) { ForEach(store.deckNames, id: \.self) { Text($0).tag($0) } }
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
                Button(store.text("取消")) { onClose(); dismiss() }
                Spacer()
                Button(store.text("确认添加")) {
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
