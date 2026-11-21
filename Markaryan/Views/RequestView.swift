import SwiftUI
import UIKit
import MessageUI

struct RequestView: View {
    @EnvironmentObject private var store: AppStore
    @State private var stage = 0
    @State private var message: String?
    @State private var showMail = false
    @State private var clear = false
    @State private var isSending = false
    @State private var sentOrder: WorkOrder?
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 24) {
            SectionTitle(eyebrow: "Начнём с вашей задачи", title: "Расскажите\nоб объекте.")
            Picker("Этап заявки", selection: $stage) { Text("1. Работы").tag(0); Text("2. Объект").tag(1); Text("3. Связь").tag(2) }.pickerStyle(.segmented)
            if stage == 0 {
                Text("Какие работы нужны?").font(.title3.bold())
                ForEach(store.services) { service in
                    Button {
                        if store.draft.services.contains(service.title) { store.draft.services.remove(service.title) } else { store.draft.services.insert(service.title) }
                    } label: {
                        HStack { Text(service.title).foregroundStyle(.white); Spacer(); Image(systemName: store.draft.services.contains(service.title) ? "checkmark.circle.fill" : "circle").foregroundStyle(Theme.orange) }.padding(16).panelCard(14).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityAddTraits(store.draft.services.contains(service.title) ? .isSelected : [])
                }
                PrimaryButton(title: "Далее: об объекте", icon: "chevron.right") { stage = 1 }
            } else if stage == 1 {
                input("Адрес или район", text: $store.draft.address, placeholder: "Сочи, Хоста…")
                Picker("Стадия", selection: $store.draft.stage) { ForEach(["Планирование", "Проект готов", "Строительство", "Ремонт и реконструкция"], id: \.self) { Text($0) } }.pickerStyle(.menu)
                Text("Задача и расчёты").font(.subheadline).foregroundStyle(Theme.muted)
                TextEditor(text: $store.draft.details).frame(minHeight: 200).padding(10).scrollContentBackground(.hidden).panelCard(14)
                Text("Укажите размеры, желаемые сроки и особенности площадки. Сохранённые расчёты можно добавить из раздела «Расчёты».").font(.footnote).foregroundStyle(Theme.muted)
                PrimaryButton(title: "Далее: контакты", icon: "chevron.right") { stage = 2 }
            } else {
                input("Ваше имя", text: $store.draft.name, placeholder: "Как к вам обращаться")
                input("Телефон", text: $store.draft.phone, placeholder: "+7 ___ ___-__-__", phone: true)
                if let sentOrder {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Заявка отправлена в АртСтрой", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(Theme.success)
                        Text("Мы свяжемся с вами по телефону \(store.draft.phone). Переписка по заявке — в «Профиле», раздел «Мои заявки и чаты».").font(.footnote).foregroundStyle(Theme.muted)
                        NavigationLink { WorkOrderChatView(order: sentOrder) } label: { SecondaryActionLabel(title: "Открыть чат заявки", icon: "bubble.left.and.bubble.right.fill") }
                    }
                    .padding(16).panelCard(16)
                } else {
                    PrimaryButton(title: isSending ? "Отправляем…" : "Отправить заявку", icon: isSending ? "hourglass" : "paperplane.fill") { Task { await sendInApp() } }
                        .disabled(isSending)
                }
                Text("Или удобным способом:").font(.footnote).foregroundStyle(Theme.muted)
                HStack(spacing: 10) {
                    Button { sendWhatsApp() } label: { SecondaryActionLabel(title: "WhatsApp", icon: "message.fill") }.buttonStyle(PremiumPressStyle())
                    Button { sendMail() } label: { SecondaryActionLabel(title: "Почта", icon: "envelope.fill") }.buttonStyle(PremiumPressStyle())
                }
                HStack(spacing: 10) {
                    ShareLink(item: store.draft.text) { SecondaryActionLabel(title: "Поделиться", icon: "square.and.arrow.up") }.buttonStyle(PremiumPressStyle())
                    Link(destination: Brand.phoneURL) { SecondaryActionLabel(title: "Позвонить", icon: "phone.fill") }.buttonStyle(PremiumPressStyle())
                }
                Text("Передавая заявку, вы предоставляете указанные контакты для ответа по вашему обращению.").font(.caption).foregroundStyle(Theme.muted)
            }
            Text("Черновик сохраняется на этом iPhone.").font(.caption).foregroundStyle(Theme.muted)
            Button("Очистить черновик", role: .destructive) { clear = true }.font(.footnote)
        }.padding(20) }.background(Theme.background).navigationTitle("Заявка")
            .alert("Заявка", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("Понятно") { message = nil } } message: { Text(message ?? "") }
            .confirmationDialog("Очистить сохранённый черновик?", isPresented: $clear, titleVisibility: .visible) { Button("Очистить", role: .destructive) { store.draft = RequestDraft(); stage = 0; sentOrder = nil } }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Закрыть") { store.showRequest = false } } }
            .scrollDismissesKeyboard(.interactively)
            .onAppear { if store.draft.address.isEmpty { store.draft.address = store.passport.address } }
            .sheet(isPresented: $showMail) { MailComposer(body: store.draft.text) { result in
                showMail = false
                switch result { case .sent: message = "Письмо передано почтовой службе. Доставку можно проверить в вашей почте."; store.registerMeaningfulAction(); case .failed: message = "Не удалось передать письмо. Попробуйте поделиться заявкой или позвонить."; default: break }
            } }
    }
    private func sendInApp() async {
        if let validation = store.draft.validation { message = validation; Haptics.warning(); return }
        isSending = true
        defer { isSending = false }
        do {
            let order = try await store.submitRequestDraft()
            Haptics.success()
            withAnimation(.snappy) { sentOrder = order }
        } catch {
            message = "Не удалось отправить через приложение: \(error.localizedDescription)\nОтправьте заявку через WhatsApp или позвоните — это займёт минуту."
        }
    }
    private func sendWhatsApp() {
        if let validation = store.draft.validation { message = validation; return }
        store.track("request_whatsapp")
        UIApplication.shared.open(Brand.whatsAppURL(text: store.draft.text))
    }
    private func sendMail() {
        if let validation = store.draft.validation { message = validation; return }
        if MFMailComposeViewController.canSendMail() { showMail = true }
        else { message = "Почта на iPhone не настроена. Используйте WhatsApp, «Поделиться» или позвоните нам." }
    }
    func input(_ label: String, text: Binding<String>, placeholder: String, phone: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 9) { Text(label).font(.subheadline).foregroundStyle(Theme.muted); TextField(placeholder, text: phone ? Binding(get: { text.wrappedValue }, set: { text.wrappedValue = PhoneMask.update(old: text.wrappedValue, new: $0) }) : text).keyboardType(phone ? .phonePad : .default).textContentType(phone ? .telephoneNumber : .name).padding(16).panelCard(14) }
    }
}
struct MailComposer: UIViewControllerRepresentable {
    let body: String
    let completion: (MFMailComposeResult) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController(); controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(["m.art.v@mail.ru"]); controller.setSubject("Заявка на строительные работы"); controller.setMessageBody(body, isHTML: false)
        return controller
    }
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let completion: (MFMailComposeResult) -> Void
        init(completion: @escaping (MFMailComposeResult) -> Void) { self.completion = completion }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) { completion(error == nil ? result : .failed) }
    }
}

/// Formats Russian phone numbers as «+7 900 123‑45‑67» while typing.
enum PhoneMask {
    /// Backspace over a separator removes the previous digit instead of getting stuck.
    static func update(old: String, new: String) -> String {
        let oldDigits = old.filter(\.isNumber), newDigits = new.filter(\.isNumber)
        if new.count < old.count && newDigits.count == oldDigits.count { return format(String(newDigits.dropLast())) }
        return format(new)
    }
    static func format(_ raw: String) -> String {
        var digits = raw.filter(\.isNumber)
        if digits.hasPrefix("8") { digits = "7" + digits.dropFirst() }
        guard digits.hasPrefix("7") || digits.hasPrefix("9") else { return String(raw.prefix(20)) }
        if digits.hasPrefix("9") { digits = "7" + digits }
        digits = String(digits.prefix(11))
        let body = Array(digits.dropFirst())
        var result = "+7"
        for (index, digit) in body.enumerated() {
            switch index {
            case 0: result += " "
            case 3: result += " "
            case 6, 8: result += "-"
            default: break
            }
            result.append(digit)
        }
        return result
    }
}
