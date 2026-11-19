import SwiftUI
import UIKit

enum HubTab: Hashable { case orders, market }

struct PerformersHubView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showCreate = false
    @State private var tab: HubTab = .orders

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(eyebrow: "Мои заявки и чаты", title: "Отправьте задачу —\nсогласуйте работы.")
                Text("Прикрепите смету, описание проекта или визуализацию. Заявка попадёт в рабочий кабинет АртСтрой, а ответы будут в чате этой заявки.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)

                Picker("Раздел", selection: $tab) {
                    Text("Мои заявки").tag(HubTab.orders)
                    Text("Резюме мастеров").tag(HubTab.market)
                }
                .pickerStyle(.segmented)

                if tab == .orders {
                    Button { showCreate = true } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "person.3.fill")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.black)
                                .frame(width: 48, height: 48)
                                .background(Theme.orange, in: RoundedRectangle(cornerRadius: 16))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Найти исполнителя").font(.headline).foregroundStyle(.white)
                                Text("Опишите работы, город и ориентир по бюджету").font(.caption).foregroundStyle(Theme.muted)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right").font(.headline).foregroundStyle(Theme.orange)
                        }
                        .padding(18)
                        .panelCard(22)
                    }
                    .buttonStyle(PremiumCardPressStyle())

                    HStack {
                        Text("МОИ ЗАЯВКИ").font(.caption.weight(.bold)).tracking(1.3).foregroundStyle(Theme.orange)
                        Spacer()
                        if store.workOrdersLoading { ProgressView().tint(Theme.orange).controlSize(.small) }
                    }

                    if store.workOrders.isEmpty && !store.workOrdersLoading {
                        VStack(spacing: 12) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.title2)
                                .foregroundStyle(Theme.orange)
                            Text("Заявок пока нет").font(.headline)
                            Text("Рассчитайте смету, создайте проект или визуализацию — затем отправьте материалы на согласование исполнителям.")
                                .font(.caption)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .panelCard(20)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(store.workOrders) { order in
                                NavigationLink { WorkOrderChatView(order: order) } label: {
                                    WorkOrderCard(order: order)
                                }
                                .buttonStyle(PremiumCardPressStyle())
                            }
                        }
                    }

                    InfoNote(text: "Вы сами выбираете, какие материалы отправить. Сметы, фото и визуализации передаются только после нажатия «Отправить исполнителям». Вы можете продолжить согласование в чате заявки.")
                } else {
                    ResumeSearchSection()
                }
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Заявки")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.refreshWorkOrders() }
        .refreshable { await store.refreshWorkOrders() }
        .sheet(isPresented: $showCreate) {
            NavigationStack { CreateWorkOrderView(prefill: .empty) }
        }
    }
}

struct WorkOrderCard: View {
    let order: WorkOrder

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: order.attachmentBase64 == nil ? "hammer.fill" : "photo.fill")
                .font(.title3)
                .foregroundStyle(Theme.orange)
                .frame(width: 42, height: 42)
                .background(Theme.orange.opacity(0.11), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(order.category).font(.headline).foregroundStyle(.white).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(order.statusTitle).font(.caption2.weight(.bold)).foregroundStyle(Theme.orange).lineLimit(1)
                }
                Text(order.city + (order.budget.isEmpty ? "" : " · " + order.budget))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                Text(order.details.replacingOccurrences(of: "\n", with: " "))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(2)
            }
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.muted).padding(.top, 5)
        }
        .padding(16)
        .panelCard(18)
    }
}

struct CreateWorkOrderView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let prefill: WorkOrderDraft
    @State private var category: String
    @State private var city: String
    @State private var details: String
    @State private var budget: String
    @State private var isSending = false
    @State private var error: String?
    @State private var sentOrder: WorkOrder?

    private let categories = [
        "Строительные работы", "Фундамент и монолит", "Коробка и кровля", "Фасад и благоустройство",
        "Ремонт и отделка", "Инженерные работы", "Металлоконструкции", "Другое"
    ]

    init(prefill: WorkOrderDraft) {
        self.prefill = prefill
        _category = State(initialValue: prefill.category)
        _city = State(initialValue: prefill.city)
        _details = State(initialValue: prefill.details)
        _budget = State(initialValue: prefill.budget)
    }

    var body: some View {
        Group {
            if let sentOrder { sentState(sentOrder) } else { form }
        }
        .background(Theme.background)
        .navigationTitle("Заявка")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(sentOrder == nil ? "Отмена" : "Готово") { dismiss() } } }
    }

    private func sentState(_ order: WorkOrder) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 64)).foregroundStyle(Theme.success).padding(.top, 40)
                Text("Заявка отправлена").font(.title.bold())
                Text("Она уже в рабочем кабинете АртСтроя. Ответ придёт в чат этой заявки — обычно в течение рабочего дня.").multilineTextAlignment(.center).foregroundStyle(Theme.muted)
                NavigationLink { WorkOrderChatView(order: order) } label: { SecondaryActionLabel(title: "Открыть чат заявки", icon: "bubble.left.and.bubble.right.fill") }.buttonStyle(PremiumPressStyle())
                HHOrderCard(order: order)
                Link(destination: Brand.phoneURL) { SecondaryActionLabel(title: "Позвонить, если срочно", icon: "phone.fill") }.buttonStyle(PremiumPressStyle())
            }
            .padding(24)
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(eyebrow: "Новая заявка", title: "Что нужно\nвыполнить?")
                Text("Смета или описание уже добавлены. Проверьте данные, чтобы исполнитель мог дать предметный ответ.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Тип работ").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                    Menu {
                        ForEach(categories, id: \.self) { value in Button(value) { category = value } }
                    } label: {
                        HStack { Text(category).foregroundStyle(.white); Spacer(); Image(systemName: "chevron.up.chevron.down").foregroundStyle(Theme.orange) }
                            .padding(16).panelCard(15)
                    }
                }
                field("Город или район", text: $city, placeholder: "Например, Сочи, Адлер")
                field("Ориентир по бюджету", text: $budget, placeholder: "Например, 2 450 000 ₽")

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Задача для исполнителя").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                        Spacer()
                        Text("\(details.count)/1600").font(.caption2).foregroundStyle(details.count > 1600 ? Theme.danger : Theme.muted)
                    }
                    TextEditor(text: $details)
                        .frame(minHeight: 190)
                        .padding(11)
                        .scrollContentBackground(.hidden)
                        .panelCard(15)
                }

                if let image = prefill.attachment {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("Визуализация прикреплена к заявке", systemImage: "photo.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.orange)
                        Image(uiImage: image).resizable().scaledToFill().frame(height: 170).frame(maxWidth: .infinity).clipped().clipShape(RoundedRectangle(cornerRadius: 17))
                    }
                    .padding(12)
                    .panelCard(18)
                }

                if let error { Label(error, systemImage: "exclamationmark.circle.fill").font(.footnote).foregroundStyle(.red) }

                PrimaryButton(title: isSending ? "Отправляем…" : "Отправить исполнителям", icon: isSending ? "hourglass" : "paperplane.fill") {
                    Task { await send() }
                }
                .disabled(isSending)

                InfoNote(text: "После отправки заявка появится в рабочем кабинете АртСтрой. Все сообщения по ней останутся в приложении.")
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func field(_ title: String, text: Binding<String>, placeholder: String, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
            TextField(placeholder, text: text).keyboardType(keyboard).padding(16).panelCard(15)
        }
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        do {
            let order = try await store.publishWorkOrder(WorkOrderDraft(category: category, city: city, details: details, budget: budget, attachment: prefill.attachment))
            Haptics.success()
            withAnimation(.snappy) { sentOrder = order }
        } catch { self.error = error.localizedDescription; Haptics.warning() }
    }
}

struct WorkOrderChatView: View {
    @EnvironmentObject private var store: AppStore
    let order: WorkOrder
    @State private var messages: [WorkOrderMessage] = []
    @State private var text = ""
    @State private var isSending = false
    @State private var isLoading = true
    @State private var error: String?
    @State private var attachment: UIImage?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    WorkOrderChatHeader(order: order)
                    HHOrderCard(order: order)
                    if let image = attachment { Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)) }
                    if isLoading { ProgressView().tint(Theme.orange).frame(maxWidth: .infinity).padding(30) }
                    if messages.isEmpty && !isLoading {
                        Text("Пока нет сообщений. Напишите, что особенно важно согласовать по этой заявке.")
                            .font(.footnote).foregroundStyle(Theme.muted).padding(16)
                            .panelCard(16)
                    }
                    ForEach(messages) { message in WorkOrderMessageBubble(message: message).id(message.id) }
                    if let error { Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(Theme.danger) }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .onChange(of: messages.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }

            HStack(spacing: 10) {
                TextField("Написать по заявке…", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .panelCard(18)
                Button { Task { await send() } } label: {
                    Image(systemName: isSending ? "hourglass" : "arrow.up")
                        .font(.headline.weight(.bold)).foregroundStyle(.black)
                        .frame(width: 46, height: 46).background(Theme.orange, in: Circle())
                }
                .disabled(isSending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Theme.background)
        }
        .navigationTitle("Согласование")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let raw = order.attachmentBase64, !raw.isEmpty {
                // Decode the attachment once, off the main thread (previously it was decoded on every redraw).
                attachment = await Task.detached(priority: .userInitiated) { Data(base64Encoded: raw).flatMap(UIImage.init(data:)) }.value
            }
            await load()
            // Light polling while the chat is open, so replies appear without pulling to refresh.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { break }
                await load(silent: true)
            }
        }
        .refreshable { await load() }
    }

    private func load(silent: Bool = false) async {
        if !silent { isLoading = messages.isEmpty }
        defer { isLoading = false }
        do {
            let fresh = try await store.loadWorkOrderMessages(orderID: order.id)
            if fresh.count != messages.count || fresh.last?.id != messages.last?.id { messages = fresh }
            error = nil
        } catch let caughtError { if !silent { self.error = caughtError.localizedDescription } }
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        do {
            let message = try await store.sendWorkOrderMessage(orderID: order.id, text: text)
            messages.append(message); text = ""; error = nil
            Haptics.tap()
        } catch let caughtError { self.error = caughtError.localizedDescription }
    }
}

struct WorkOrderChatHeader: View {
    let order: WorkOrder
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack { Text(order.category).font(.headline).foregroundStyle(.white); Spacer(); Text(order.statusTitle).font(.caption.weight(.bold)).foregroundStyle(Theme.orange) }
            Text(order.city + (order.budget.isEmpty ? "" : " · " + order.budget)).font(.caption).foregroundStyle(Theme.muted)
            Text(order.details).font(.footnote).foregroundStyle(.white.opacity(0.82))
        }
        .padding(16).panelCard(18)
    }
}

struct WorkOrderMessageBubble: View {
    let message: WorkOrderMessage
    var body: some View {
        HStack {
            if message.isClient { Spacer(minLength: 42) }
            VStack(alignment: .leading, spacing: 5) {
                Text(message.isClient ? "Вы" : "АртСтрой").font(.caption2.weight(.bold)).foregroundStyle(message.isClient ? .black.opacity(0.68) : Theme.orange)
                Text(message.text).font(.subheadline).foregroundStyle(message.isClient ? .black : .white).textSelection(.enabled)
                if let time = message.displayTime { Text(time).font(.caption2).foregroundStyle(message.isClient ? .black.opacity(0.55) : Theme.muted) }
            }
            .padding(13)
            .background(message.isClient ? Theme.orange : Theme.panel, in: RoundedRectangle(cornerRadius: 17))
            if !message.isClient { Spacer(minLength: 42) }
        }
    }
}

extension WorkOrderMessage {
    private static let isoParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    var displayTime: String? {
        let date = Self.isoParser.date(from: createdAt) ?? ISO8601DateFormatter().date(from: createdAt)
        return date?.formatted(date: .abbreviated, time: .shortened)
    }
}
