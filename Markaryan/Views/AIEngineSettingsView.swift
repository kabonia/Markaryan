import SwiftUI

/// Choice of AI engine and secure entry of the Claude API key.
struct AIEngineSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var keyInput = ""
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var workspaceInput = ""
    @State private var savedWorkspace = ClaudeClient.currentWorkspaceID

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: store.usesClaude ? "sparkles" : "server.rack").font(.title2).foregroundStyle(Theme.orange).frame(width: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Сейчас отвечает").font(.caption).foregroundStyle(Theme.muted)
                        Text(store.aiEngineTitle).font(.headline)
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                Picker("Движок", selection: $store.aiPreference) { ForEach(AIPreference.allCases) { Text($0.title).tag($0) } }
                Picker("Модель Claude", selection: $store.claudeModel) { ForEach(ClaudeModel.allCases) { Text($0.title).tag($0) } }
                    .disabled(store.aiPreference == .server)
            } header: { Text("ИИ‑движок") } footer: {
                Text("Claude отвечает с учётом всей переписки, видит фото, читает сметы и рисует расстановку мебели на плане комнаты. Без ключа работает сервер АртСтроя.")
            }
            Section {
                if ClaudeClient.bundledKey != nil && KeychainStore.read(ClaudeClient.keyAccount) == nil {
                    Label("Ключ встроен в эту сборку (ClaudeKey.plist)", systemImage: "shippingbox.fill").foregroundStyle(Theme.success)
                } else if store.hasClaudeKey {
                    Label("Ключ сохранён в Связке ключей iPhone", systemImage: "lock.fill").foregroundStyle(Theme.success)
                    Button("Удалить ключ", role: .destructive) { store.setClaudeKey(""); testResult = nil }
                } else {
                    SecureField("sk-ant-… или sk-or-… (OpenRouter)", text: $keyInput).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Сохранить ключ") { store.setClaudeKey(keyInput); keyInput = ""; Haptics.success() }
                        .disabled(!["sk-ant-", "sk-or-"].contains { keyInput.trimmingCharacters(in: .whitespaces).hasPrefix($0) })
                }
                Button {
                    isTesting = true
                    Task { testResult = await store.testClaude(); isTesting = false }
                } label: { HStack { Text("Проверить Claude"); Spacer(); if isTesting { ProgressView() } } }
                .disabled(!store.hasClaudeKey || isTesting)
                if let testResult { Text(testResult).font(.footnote).foregroundStyle(Theme.muted) }
                if let savedWorkspace {
                    LabeledContent("Workspace", value: savedWorkspace).font(.footnote)
                    Button("Убрать Workspace ID", role: .destructive) { KeychainStore.delete(ClaudeClient.workspaceAccount); self.savedWorkspace = ClaudeClient.currentWorkspaceID; testResult = nil }
                } else {
                    TextField("Workspace ID: wrkspc_…", text: $workspaceInput).textInputAutocapitalization(.never).autocorrectionDisabled().font(.footnote)
                    Button("Сохранить Workspace ID") {
                        KeychainStore.save(workspaceInput, account: ClaudeClient.workspaceAccount)
                        workspaceInput = ""
                        savedWorkspace = ClaudeClient.currentWorkspaceID
                        testResult = nil
                        Haptics.success()
                    }
                    .disabled(!workspaceInput.trimmingCharacters(in: .whitespaces).hasPrefix("wrkspc_"))
                }
                Link("Получить ключ на console.anthropic.com", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
            } header: { Text("Ключ Claude API") } footer: {
                Text("Ключ хранится только в зашифрованной Связке ключей этого iPhone и отправляется только на api.anthropic.com. Не публикуйте сборку для клиентов с вашим ключом: для App Store ключ должен лежать на сервере АртСтроя.")
            }
            Section("Что умеет ИИ") {
                Label("Отвечает потоком, как в чате, и помнит контекст разговора", systemImage: "text.bubble")
                Label("Разбирает фото объекта: трещины, кладка, кровля", systemImage: "photo")
                Label("Расставляет мебель и зонирует комнату по скану", systemImage: "square.split.bottomrightquarter")
                Label("Объясняет смету и ищет, где сэкономить", systemImage: "rublesign.circle")
            }
            .font(.subheadline)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("ИИ‑движок")
        .navigationBarTitleDisplayMode(.inline)
    }
}
