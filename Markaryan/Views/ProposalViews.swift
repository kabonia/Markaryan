import SwiftUI
import PhotosUI

/// «Реквизиты для КП»: the person's company in the header of commercial proposals instead of «СметаПро».
struct ProposalProfileView: View {
    @ObservedObject private var store = ProposalProfileStore.shared
    @State private var logoItem: PhotosPickerItem?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Group {
                        if let logo = store.logo {
                            Image(uiImage: logo).resizable().scaledToFit()
                        } else {
                            Image(systemName: "building.2").font(.title2).foregroundStyle(Theme.muted)
                        }
                    }
                    .frame(width: 56, height: 56)
                    .background(Theme.panelRaised.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 6) {
                        PhotosPicker(selection: $logoItem, matching: .images) {
                            Text(store.logo == nil ? "Добавить логотип" : "Заменить логотип")
                        }
                        if store.logo != nil {
                            Button("Убрать логотип", role: .destructive) { store.setLogo(nil) }.font(.footnote)
                        }
                    }
                }
                field("Название: ООО «…» или ИП …", \.company)
                field("ИНН", \.inn, keyboard: .numberPad)
                field("КПП (для ООО)", \.kpp, keyboard: .numberPad)
                field("ОГРН / ОГРНИП", \.ogrn, keyboard: .numberPad)
                field("Адрес", \.address)
            } header: {
                Text("Компания")
            } footer: {
                Text("Пока название пустое, предложения выходят под «\(Brand.name)». Оформление документа не меняется — меняются только данные в шапке и подписи.")
            }

            Section("Контакты") {
                field("Телефон", \.phone, keyboard: .phonePad)
                field("Эл. почта", \.email, keyboard: .emailAddress)
                field("Сайт", \.website, keyboard: .URL)
            }

            Section("Подписант") {
                field("ФИО, например Иванов И. И.", \.signerName)
                field("Должность", \.signerPosition)
            }

            Section {
                field("Банк", \.bankName)
                field("Расчётный счёт", \.account, keyboard: .numberPad)
                field("Корр. счёт", \.corrAccount, keyboard: .numberPad)
                field("БИК", \.bik, keyboard: .numberPad)
            } header: {
                Text("Банковские реквизиты")
            } footer: {
                Text("Необязательно. Если указан расчётный счёт — реквизиты попадут в раздел «Условия».")
            }

            Section("Условия по умолчанию") {
                TextField("Порядок оплаты", text: $store.profile.paymentTerms, axis: .vertical).lineLimit(2...4)
                TextField("Гарантия", text: $store.profile.warranty, axis: .vertical).lineLimit(2...4)
                Stepper("Срок действия предложения: \(store.profile.validityDays) дн.", value: $store.profile.validityDays, in: 1...90)
            }

            Section {
                Text("Реквизиты и логотип хранятся только на этом iPhone.").font(.footnote).foregroundStyle(Theme.muted)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Реквизиты для КП")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: logoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    await MainActor.run { store.setLogo(image) }
                }
                await MainActor.run { logoItem = nil }
            }
        }
    }

    private func field(_ title: String, _ key: WritableKeyPath<ProposalProfile, String>, keyboard: UIKeyboardType = .default) -> some View {
        TextField(title, text: Binding(get: { store.profile[keyPath: key] }, set: { store.profile[keyPath: key] = $0 }))
            .keyboardType(keyboard)
            .textInputAutocapitalization(keyboard == .emailAddress || keyboard == .URL ? .never : .sentences)
            .autocorrectionDisabled(keyboard != .default)
    }
}

/// Asked right before the PDF: who the proposal is for, the address, the term — then the document is made and shared.
struct ProposalExportSheet: View {
    let result: DocEstimateResult
    @ObservedObject private var store = ProposalProfileStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var details: ProposalDetails
    @State private var shareFile: SharedFile?
    @State private var failed = false

    init(result: DocEstimateResult) {
        self.result = result
        _details = State(initialValue: ProposalDetails(number: ProposalDetails.defaultNumber(for: result)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Предложение") {
                    LabeledContent("Номер") { TextField("Номер", text: $details.number).multilineTextAlignment(.trailing) }
                    TextField("Заказчик: ФИО или компания", text: $details.client)
                    TextField("Адрес объекта", text: $details.address)
                    TextField("Срок работ, например «45 рабочих дней»", text: $details.term)
                }
                Section {
                    Toggle("Материалы построчно", isOn: $details.detailed)
                    Toggle("Примечания сметчика", isOn: $details.includeNotes)
                } footer: {
                    Text("«Материалы построчно» выключено — в смете-приложении только работы, материалы одной суммой по разделу. «Примечания сметчика» — допущения расчёта в конце документа.")
                }
                Section {
                    NavigationLink { ProposalProfileView() } label: {
                        Label(store.profile.isFilled ? store.profile.company : "Указать свои реквизиты", systemImage: "building.2")
                    }
                } header: {
                    Text("Исполнитель")
                } footer: {
                    Text(store.profile.isFilled
                         ? "В шапке — ваши название, логотип и реквизиты."
                         : "Сейчас в шапке «\(Brand.name)». Впишите свою компанию — оформление останется тем же.")
                }
                Section {
                    Button {
                        if let url = CommercialProposalPDF.make(result, profile: store.profile, logo: store.logo, details: details) {
                            Haptics.success()
                            shareFile = SharedFile(url: url)
                        } else {
                            failed = true
                        }
                    } label: {
                        Label("Сформировать PDF", systemImage: "doc.richtext").font(.headline)
                    }
                    .disabled(details.number.trimmingCharacters(in: .whitespaces).isEmpty)
                    if failed { Text("Не удалось сохранить PDF. Попробуйте ещё раз.").font(.footnote).foregroundStyle(Theme.danger) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Коммерческое предложение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
            .sheet(item: $shareFile) { file in ActivityShareSheet(items: [file.url]) }
        }
    }
}
