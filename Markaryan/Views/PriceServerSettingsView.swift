import SwiftUI

/// Server and price-book settings. Used both as a pushed screen and inside a sheet
/// (the presenter supplies the NavigationStack), so it never nests navigation stacks.
struct PriceServerSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var address = ""
    @State private var checkResult: String?
    @State private var isChecking = false
    @State private var isRefreshing = false

    private var isValid: Bool {
        let clean = address.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.lowercased().hasPrefix("https://") && URL(string: clean)?.host != nil
    }

    var body: some View {
        Form {
            Section("Прайс-лист") {
                LabeledContent("Позиций", value: "\(store.priceBook.lines.count)")
                LabeledContent("Версия прайса", value: store.priceBook.updatedAt.formatted(date: .abbreviated, time: .shortened))
                if let sync = store.lastPriceSync { LabeledContent("Синхронизация", value: sync.formatted(date: .abbreviated, time: .shortened)) }
                Button {
                    isRefreshing = true
                    Task { await store.refreshPriceBook(); isRefreshing = false }
                } label: {
                    HStack { Text("Обновить цены сейчас"); Spacer(); if isRefreshing { ProgressView() } }
                }
                .disabled(isRefreshing)
            }
            Section {
                TextField("https://example.ru", text: $address).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                if !address.isEmpty && !isValid { Text("Адрес должен начинаться с https://").font(.footnote).foregroundStyle(Theme.danger) }
                Button {
                    isChecking = true
                    let candidate = address
                    Task {
                        checkResult = await store.checkServer(candidate)
                        isChecking = false
                    }
                } label: { HStack { Text("Проверить соединение"); Spacer(); if isChecking { ProgressView() } } }
                .disabled(!isValid || isChecking)
                if let checkResult { Text(checkResult).font(.footnote).foregroundStyle(Theme.muted) }
                if address.trimmingCharacters(in: .whitespacesAndNewlines) != AppStore.productionServerURL {
                    Button("Вернуть сервер по умолчанию") { address = AppStore.productionServerURL; checkResult = nil }
                }
            } header: { Text("Адрес сервера") } footer: {
                Text("Сервер нужен для автоматического обновления цен, заявок, ИИ‑помощника и визуализаций. Ключ модели хранится только на сервере. Без сервера прайс можно импортировать JSON‑файлом в полной смете.")
            }
            Section { Button("Сохранить") { save() }.fontWeight(.semibold).disabled(!isValid) }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Цены и сервер")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { address = store.priceServerURL }
        .alert("Прайс", isPresented: Binding(get: { store.priceSyncMessage != nil }, set: { if !$0 { store.priceSyncMessage = nil } })) {
            Button("Понятно") { store.priceSyncMessage = nil }
        } message: { Text(store.priceSyncMessage ?? "") }
    }

    private func save() {
        store.priceServerURL = address.trimmingCharacters(in: .whitespacesAndNewlines)
        Haptics.success()
        Task { await store.refreshPriceBook(silent: true) }
        dismiss()
    }
}
