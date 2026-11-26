import SwiftUI
import PhotosUI

/// «Поддержка»: обращения и переписка с менеджером.
struct SupportView: View {
    @ObservedObject private var support = SupportCenter.shared
    @State private var composing = false
    var presetTopic: String? = nil
    var presetFeature: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ПОДДЕРЖКА").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.goldLight)
                    Text("Напишите менеджеру").font(.system(.title2, design: .serif, weight: .bold)).foregroundStyle(.white)
                    Text("Что‑то не работает, оплатили функцию и не получили результат или не разобрались — опишите, что случилось. Менеджер видит ваш аккаунт и списания, ответ придёт сюда. Если функция сломалась по нашей вине — вернём кредиты.")
                        .font(.footnote).foregroundStyle(.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                PrimaryButton(title: "Новое обращение", icon: "square.and.pencil") { composing = true }

                if support.tickets.isEmpty {
                    if support.loading { ProgressView().frame(maxWidth: .infinity).padding(.top, 20) }
                    else {
                        Text("Обращений пока нет. Обычно отвечаем в течение часа в рабочее время.")
                            .font(.footnote).foregroundStyle(Theme.muted).padding(.top, 4)
                    }
                } else {
                    Text("МОИ ОБРАЩЕНИЯ").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold).padding(.top, 4)
                    ForEach(support.tickets) { ticket in
                        NavigationLink { SupportTicketView(ticketID: ticket.id) } label: { SupportTicketRow(ticket: ticket, unread: support.isUnread(ticket)) }
                            .buttonStyle(PremiumCardPressStyle())
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Поддержка")
        .featureIntro(.support)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await support.refresh() }
        .task { await support.refresh() }
        .sheet(isPresented: $composing) {
            NavigationStack { SupportComposeView(topic: presetTopic ?? "broken", feature: presetFeature) }
        }
        .onAppear { if presetTopic != nil && support.tickets.isEmpty { composing = true } }
    }
}

struct SupportTicketRow: View {
    let ticket: SupportTicket
    let unread: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: SupportCenter.topics.first { $0.key == ticket.topic }?.icon ?? "bubble.left.fill")
                .font(.body.weight(.semibold)).foregroundStyle(Theme.orange)
                .frame(width: 40, height: 40).background(Theme.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("№\(ticket.number) · \(ticket.topicTitle.tr)").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                    Spacer(minLength: 4)
                    if unread { Circle().fill(Theme.danger).frame(width: 9, height: 9).accessibilityLabel("Новый ответ") }
                }
                Text(ticket.messages.last?.text ?? "").font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
                Text(ticket.statusTitle.tr).font(.caption2.weight(.bold)).foregroundStyle(ticket.statusColor)
            }
        }
        .padding(14).panelCard(18)
    }
}

/// Новое обращение: тема, функция, описание, снимок экрана, контакт.
struct SupportComposeView: View {
    @ObservedObject private var support = SupportCenter.shared
    @Environment(\.dismiss) private var dismiss
    @State var topic: String
    @State var feature: String?
    @State private var text = ""
    @State private var contact = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var sending = false
    @State private var created: SupportTicket?

    var body: some View {
        Form {
            Section("Что случилось") {
                Picker("Тема", selection: $topic) {
                    ForEach(SupportCenter.topics, id: \.key) { t in Label(t.title.tr, systemImage: t.icon).tag(t.key) }
                }
                Picker("Функция", selection: $feature) {
                    Text("Не выбрана").tag(String?.none)
                    ForEach(SupportCenter.features, id: \.self) { Text($0.tr).tag(String?.some($0)) }
                }
            }
            Section {
                TextField("Опишите: что делали, что ожидали и что получилось", text: $text, axis: .vertical)
                    .lineLimit(4...10)
            } header: { Text("Описание") } footer: {
                Text(topic == "paid" ? "Менеджер видит ваши списания — проверит и вернёт кредиты, если результат не получен." : "Чем подробнее, тем быстрее поможем.")
            }
            Section {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(photo == nil ? "Приложить снимок экрана" : "Заменить снимок", systemImage: "photo.on.rectangle")
                }
                if let photo {
                    HStack {
                        Image(uiImage: photo).resizable().scaledToFit().frame(height: 90).clipShape(RoundedRectangle(cornerRadius: 10))
                        Spacer()
                        Button(role: .destructive) { self.photo = nil; pickerItem = nil } label: { Image(systemName: "trash") }
                    }
                }
            } footer: { Text("Необязательно. Снимок экрана помогает понять, что пошло не так.") }
            Section {
                TextField("Телефон, Telegram или e‑mail", text: $contact).textContentType(.emailAddress).autocorrectionDisabled()
            } header: { Text("Как с вами связаться") } footer: {
                Text("Необязательно: ответ в любом случае придёт сюда, в «Поддержку».")
            }
            if let error = support.error { Section { Text(error).foregroundStyle(Theme.danger).font(.footnote) } }
        }
        .navigationTitle("Новое обращение")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                if sending { ProgressView() } else {
                    Button("Отправить") { Task { await send() } }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                }
            }
        }
        .onChange(of: pickerItem) { _, item in
            Task { if let data = try? await item?.loadTransferable(type: Data.self) { photo = UIImage(data: data) } }
        }
        .alert("Обращение отправлено", isPresented: Binding(get: { created != nil }, set: { if !$0 { created = nil; dismiss() } })) {
            Button("Хорошо") { created = nil; dismiss() }
        } message: {
            Text("Номер обращения — \(created?.number ?? 0). Менеджер ответит здесь, в «Поддержке».")
        }
    }

    private func send() async {
        sending = true; defer { sending = false }
        let ticket = await support.create(topic: topic, feature: feature, text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                          contact: contact.trimmingCharacters(in: .whitespacesAndNewlines), photo: photo)
        if let ticket { Haptics.success(); created = ticket }
    }
}

/// Переписка по обращению; новые ответы подтягиваются, пока экран открыт.
struct SupportTicketView: View {
    let ticketID: String
    @ObservedObject private var support = SupportCenter.shared
    @State private var text = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var sending = false
    private var ticket: SupportTicket? { support.tickets.first { $0.id == ticketID } }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if let ticket {
                            HStack {
                                Text(ticket.topicTitle.tr).font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                                if let f = ticket.feature { Text("· \(f.tr)").font(.footnote).foregroundStyle(Theme.muted) }
                                Spacer()
                                Text(ticket.statusTitle.tr).font(.caption.weight(.bold)).foregroundStyle(ticket.statusColor)
                            }
                            ForEach(ticket.messages) { m in SupportBubble(message: m).id(m.id) }
                        }
                    }
                    .padding(16)
                }
                .onChange(of: ticket?.messages.count) { _, _ in
                    if let last = ticket?.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
                .onAppear { if let last = ticket?.messages.last { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
            if let error = support.error { Text(error).font(.caption).foregroundStyle(Theme.danger).padding(.horizontal, 16) }
            HStack(alignment: .bottom, spacing: 10) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Image(systemName: photo == nil ? "photo" : "photo.fill").font(.title3).foregroundStyle(Theme.orange)
                }
                .accessibilityLabel("Приложить снимок")
                TextField("Сообщение менеджеру", text: $text, axis: .vertical).lineLimit(1...5)
                    .padding(10).background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
                Button { Task { await send() } } label: {
                    if sending { ProgressView() } else { Image(systemName: "arrow.up.circle.fill").font(.title2).foregroundStyle(Theme.orange) }
                }
                .disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Отправить")
            }
            .padding(12).background(Theme.panelRaised.opacity(0.6))
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Обращение №\(ticket?.number ?? 0)")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pickerItem) { _, item in
            Task { if let data = try? await item?.loadTransferable(type: Data.self) { photo = UIImage(data: data) } }
        }
        .onChange(of: ticket) { _, t in if let t { support.markSeen(t) } }
        .task {
            if let ticket { support.markSeen(ticket) }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                await support.refresh()
            }
        }
    }

    private func send() async {
        guard let ticket else { return }
        sending = true; defer { sending = false }
        if await support.reply(ticket, text: text.trimmingCharacters(in: .whitespacesAndNewlines), photo: photo) {
            text = ""; photo = nil; pickerItem = nil
        }
    }
}

struct SupportBubble: View {
    let message: SupportTicket.Message
    var body: some View {
        HStack {
            if !message.isManager { Spacer(minLength: 40) }
            VStack(alignment: message.isManager ? .leading : .trailing, spacing: 4) {
                if message.isManager { Text("Менеджер").font(.caption2.weight(.bold)).foregroundStyle(Theme.gold) }
                Text(message.text).font(.subheadline).foregroundStyle(message.isManager ? Theme.ink : Theme.onAccent)
                    .fixedSize(horizontal: false, vertical: true)
                if let credits = message.credits {
                    Label("+\(credits) кредитов", systemImage: "gift.fill").font(.caption.weight(.semibold)).foregroundStyle(Theme.success)
                }
                HStack(spacing: 6) {
                    if message.photo == true { Image(systemName: "photo") }
                    if let date = message.date { Text(date.formatted(date: .abbreviated, time: .shortened)) }
                }
                .font(.caption2).foregroundStyle(message.isManager ? Theme.muted : Theme.onAccent.opacity(0.75))
            }
            .padding(12)
            .background(message.isManager ? Theme.panel : Theme.orange, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            if message.isManager { Spacer(minLength: 40) }
        }
    }
}
