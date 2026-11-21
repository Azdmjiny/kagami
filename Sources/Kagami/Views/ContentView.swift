import SwiftUI

struct ContentView: View {
    @Bindable var store: KagamiStore
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            GroupBox(store.text("输入")) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField(store.text("输入单词或短语"), text: $store.input)
                        .textFieldStyle(.roundedBorder)
                        .focused($inputFocused)
                        .onSubmit(generate)
                    HStack {
                        Text(store.text("按回车生成卡片；不需要时直接输入下一个单词"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(store.text("生成卡片"), action: generate)
                            .disabled(!store.canGenerate)
                    }
                }
                .padding(4)
            }

            GroupBox {
                result
            } label: {
                HStack {
                    Text(store.text("卡片"))
                    if !store.resultWord.isEmpty {
                        Text(store.resultWord).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            footer
        }
        .padding(24)
        .toolbar { ToolbarItem(placement: .primaryAction) { SettingsLink { Label(store.text("设置"), systemImage: "gearshape") } } }
        .task {
            inputFocused = true
            await store.restoreSavedConnections()
        }
        .alert(store.text("无法完成操作"), isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.clearError() } })) {
            Button(store.text("好"), role: .cancel) { store.clearError() }
        } message: { Text(store.error?.localizedDescription ?? store.text("未知错误")) }
    }

    private func generate() {
        guard store.canGenerate else { return }
        Task { await store.generateCard() }
    }

    @ViewBuilder
    private var result: some View {
        if store.hasCard {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(store.fieldNames, id: \.self) { name in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(name).font(.headline)
                            TextEditor(text: Binding(get: { store.previewFields[name, default: ""] }, set: { store.previewFields[name] = $0 }))
                                .font(.body).frame(minHeight: 56)
                                .padding(4)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                        }
                    }
                }
                .padding(4)
            }
        } else if !store.translation.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $store.translation).font(.body)
                Text(store.text("未读取到 Anki 笔记字段，仅显示翻译。请在设置中连接 Anki 并选择笔记类型。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Text(store.text("卡片内容将在这里出现，可直接修改后添加到 Anki。"))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if store.isWorking { ProgressView().controlSize(.small) }
            if let message = store.successMessage {
                Label(message, systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
            } else if !store.modelStatus.isEmpty {
                Label(store.modelStatus, systemImage: store.modelStatus.contains("回退") ? "arrow.triangle.2.circlepath" : "cpu")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Picker(store.text("写入卡组"), selection: $store.preferences.defaultDeck) {
                if !store.deckNames.contains(store.preferences.defaultDeck) {
                    Text(store.preferences.defaultDeck.isEmpty ? store.text("请选择") : store.preferences.defaultDeck).tag(store.preferences.defaultDeck)
                }
                ForEach(store.deckNames, id: \.self) { Text($0).tag($0) }
            }
            .fixedSize()
            Button(store.text("添加到 Anki")) {
                Task {
                    if await store.addCurrentCard(to: store.preferences.defaultDeck) { inputFocused = true }
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(!store.canAddCard)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Kagami").font(.largeTitle.weight(.semibold))
                Text(store.text("输入单词，回车生成卡片，需要时一键加入 Anki。"))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
