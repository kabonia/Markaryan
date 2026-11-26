import SwiftUI
import PhotosUI
import UIKit

// MARK: - Helper: one AI assistant for the whole app

struct HelperMessage: Identifiable {
    enum Role { case user, helper }
    let id = UUID()
    let role: Role
    var text: String
    var image: UIImage? = nil
}

/// The in-app helper: knows which screen is open, answers with a cheap fast model, sees photos,
/// shows the tour and apologises when something breaks (the report goes to the developers).
@MainActor final class HelperCenter: ObservableObject {
    static let shared = HelperCenter()

    @Published var isOpen = false
    @Published private(set) var screen = "Главная"
    @Published private(set) var screenDetails = ""
    @Published var messages: [HelperMessage] = []
    @Published private(set) var isThinking = false
    /// Short apology shown on top of any screen after an error.
    @Published var notice: String?
    /// Последняя ошибка — нехватка кредитов: в сообщении кнопка «Пополнить».
    @Published var needsTopUp = false
    /// Tour: nil — off, -1 — the offer, 0… — steps.
    @Published var tourStep: Int?
    weak var store: AppStore?
    private var lastReports: [String: Date] = [:]

    func setScreen(_ title: String, details: String = "") {
        screen = title
        screenDetails = details
    }

    /// Questions that make sense on the current screen.
    var suggestions: [String] {
        let s = screen.lowercased()
        if s.contains("бетон") || s.contains("плит") || s.contains("фундамент") || s.contains("свай") {
            return ["Сколько бетона нужно на 1 м² плиты 20 см?", "Какую марку бетона взять для фундамента?", "Какой запас бетона закладывать?"]
        }
        if s.contains("кладк") || s.contains("блок") { return ["Сколько клея на куб газобетона?", "Нужен ли армопояс?", "Какой толщины делать шов?"] }
        if s.contains("плитк") { return ["Какой зуб шпателя выбрать?", "Сколько клея на м² плитки 60×60?", "Какой запас плитки брать?"] }
        if s.contains("смет") { return ["Почему такая цена за м²?", "Что можно удешевить без потери качества?", "Какие работы часто забывают в смете?"] }
        if s.contains("дизайн") || s.contains("визуал") { return ["Как сделать хорошее фото для дизайна?", "Какой стиль подойдёт маленькой комнате?", "Сколько стоит такой ремонт?"] }
        if s.contains("замер") || s.contains("ar") { return ["Как точнее замерить комнату?", "Почему AR ошибается в размерах?"] }
        return ["С чего начать ремонт?", "Как посчитать материалы на комнату?", "Сколько стоит ремонт м² под ключ?"]
    }

    func open(asking question: String? = nil) {
        isOpen = true
        if let question { Task { await ask(question) } }
    }

    // MARK: Questions

    private var systemPrompt: String {
        """
        Ты — ИИ‑помощник приложения «\(Brand.name)» для людей, которые строят и ремонтируют: опытный прораб, сметчик и дизайнер.
        Отвечай по‑русски, коротко и дружелюбно: сначала прямой ответ с цифрами, потом 2–4 пункта. Без воды.
        Давай нормы и расходы (бетон, арматура, клей, смеси, плитка, краска) с единицами и запасом; цены — только как ориентир‑диапазон.
        Если вопрос про то, как сделать что‑то в приложении, объясни, где это: вкладки «Главная», «Смета» (смета по документам — АР, КР, ТЗ, Excel или список работ; калькуляторы; типовая смета по рыночным ценам),
        «Дизайн» (скан помещения лидаром, планировка, стиль, визуализация, чертежи), «Проект» (объекты, бюджет, задачи, фото), «Профиль» (тарифы и баланс, город, настройки). Баланс кредитов и пополнение — справа вверху на главной.
        На главной: дизайн по фото, AR‑рулетка, «Сколько в пачке» (счёт по фото), визуализация дома и участка.
        Помещения бывают любые: квартира, дом, гараж, магазин, офис, кафе — подстраивайся.
        Для несущих конструкций напоминай, что решение принимает проектировщик.
        Город пользователя: \(store?.projectCity ?? Brand.city).
        Сейчас открыт экран: «\(screen)». \(screenDetails.isEmpty ? "" : "Данные экрана: \(screenDetails.prefix(1500))")
        Состояние: \(globalState())
        """
    }

    /// Глобальное состояние для контекста ответа: кредиты, план, сметы в работе.
    private func globalState() -> String {
        var parts: [String] = []
        if let me = BillingCenter.shared.me {
            parts.append("кредитов на балансе: \(me.credits)")
            if let plan = me.plan { parts.append("план «\(plan.id)» до \(plan.until)") }
        }
        for job in DocEstimateCenter.shared.running {
            if let error = job.error {
                parts.append("смета «\(job.title)» — ошибка: \(error)")
            } else {
                parts.append("смета «\(job.title)» в работе: \(job.stageTitle), \(Int(job.progress * 100))%")
            }
        }
        return parts.isEmpty ? "активных задач нет" : parts.joined(separator: "; ")
    }

    func ask(_ text: String, image: UIImage? = nil) async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty || image != nil, !isThinking else { return }
        if clean.lowercased().contains("покажи, что где") || clean.lowercased().contains("экскурс") {
            isOpen = false
            startTour()
            return
        }
        messages.append(HelperMessage(role: .user, text: clean, image: image))
        guard let engine = store?.helperEngine else {
            messages.append(HelperMessage(role: .helper, text: "Помощник пока не подключён к серверу. Калькуляторы, сметы и замеры работают и без него."))
            return
        }
        isThinking = true
        defer { isThinking = false }
        // The conversation must start with the user; the last 12 turns are enough for context and keep it cheap.
        var history = Array(messages.suffix(12))
        while history.first?.role == .helper { history.removeFirst() }
        let turns = history.map { ClaudeTurn(role: $0.role == .user ? .user : .assistant, text: $0.text.isEmpty ? "Посмотри фото." : $0.text, image: $0.image) }
        messages.append(HelperMessage(role: .helper, text: ""))
        let index = messages.count - 1
        do {
            for try await chunk in engine.stream(system: systemPrompt, turns: turns, maxTokens: 900) { messages[index].text += chunk }
            if messages[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw ClaudeError.emptyAnswer }
        } catch {
            // Fix it ourselves first: one quiet retry without streaming.
            do {
                messages[index].text = try await engine.complete(system: systemPrompt, turns: turns, maxTokens: 900)
                report(error, action: "Вопрос помощнику", autoFixed: true)
            } catch {
                messages[index].text = apology(for: error, action: "ответить")
                report(error, action: "Вопрос помощнику", autoFixed: false)
            }
        }
    }

    // MARK: Errors: apology for the user, report for the developers

    /// Call from any `catch`: shows a short apology with what to do next and sends a report.
    nonisolated func failed(_ error: Error, action: String? = nil) {
        let description = error.localizedDescription
        Task { @MainActor in self.handleFailure(description: description, action: action) }
    }

    private func handleFailure(description: String, action: String?) {
        if description.lowercased().contains("отмен") || description.lowercased().contains("cancel") { return }
        let text = apology(description: description, action: action)
        // Кончились кредиты — в сообщении сразу кнопка «Пополнить», а не только текст «зайдите в Профиль…».
        let lower = description.lowercased()
        needsTopUp = lower.contains("кредит") && (lower.contains("недостаточно") || lower.contains("пополните"))
        notice = text
        messages.append(HelperMessage(role: .helper, text: text))
        send(description: description, action: action, autoFixed: false)
    }

    private func report(_ error: Error, action: String, autoFixed: Bool) {
        send(description: error.localizedDescription, action: action, autoFixed: autoFixed)
    }

    private func apology(for error: Error, action: String) -> String { apology(description: error.localizedDescription, action: action) }

    private func apology(description: String, action: String?) -> String {
        let lower = description.lowercased()
        let advice: String
        if lower.contains("интернет") || lower.contains("offline") || lower.contains("connection") || lower.contains("сеть") || lower.contains("timed out") || lower.contains("время ожидания") {
            advice = "Похоже, пропал интернет. Проверьте связь и нажмите ещё раз — всё, что вы ввели, сохранилось."
        } else if lower.contains("лимит") || lower.contains("429") {
            advice = "Сегодняшний лимит ИИ закончился. Калькуляторы и сметы работают как обычно, а ИИ снова будет доступен завтра."
        } else if lower.contains("камер") || lower.contains("доступ") || lower.contains("разреш") {
            advice = "Нужно разрешение. Откройте Настройки → \(Brand.name) и включите доступ, затем вернитесь сюда."
        } else {
            advice = "Попробуйте ещё раз через минуту. Если повторится — мы уже получили отчёт и исправим это."
        }
        return "Извините, \(action.map { "не получилось \($0.lowercased())" } ?? "что‑то пошло не так"). \(advice)"
    }

    private func send(description: String, action: String?, autoFixed: Bool) {
        // The same error from the same screen at most once in 10 minutes.
        let key = screen + "|" + description
        if let last = lastReports[key], Date().timeIntervalSince(last) < 600 { return }
        lastReports[key] = Date()
        guard let base = AIServerConfig.marketURL else { return }
        var request = URLRequest(url: base.appendingPathComponent("v1/report"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["screen": screen, "action": action ?? "", "error": String(description.prefix(600)),
                                   "autoFixed": autoFixed, "appVersion": Brand.appVersion, "device": UIDevice.current.model]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        Task { _ = try? await URLSession.shared.data(for: request) }
    }

    // MARK: Tour

    struct TourStep { let tab: Int?; let icon: String; let title: String; let text: String }
    let tour: [TourStep] = [
        TourStep(tab: 0, icon: "house.fill", title: "Главная", text: "Самое нужное в одном месте: дизайн по фото, AR‑рулетка, счёт по фото и быстрые калькуляторы."),
        TourStep(tab: 1, icon: "function", title: "Смета", text: "Калькуляторы материалов и полная смета объекта по рыночным ценам вашего города — с вилкой «дёшево — дорого»."),
        TourStep(tab: 2, icon: "cube.transparent.fill", title: "Дизайн", text: "Сканируйте любое помещение — комнату, гараж, магазин. Получите план, стиль, визуализацию и чертежи."),
        TourStep(tab: 3, icon: "folder.fill", title: "Проект", text: "Ваши объекты: этапы, бюджет план/факт, задачи, фото и журнал решений."),
        TourStep(tab: 4, icon: "person.crop.circle", title: "Профиль", text: "Город для цен, настройки и сведения о приложении."),
        TourStep(tab: nil, icon: "sparkles", title: "Я всегда рядом", text: "Кнопка помощника есть на каждом экране. Спросите что угодно: нормы расхода, как пользоваться, что значит строка сметы — или пришлите фото."),
    ]

    func offerTour() { tourStep = -1 }
    func startTour() { tourStep = 0; applyTourTab() }
    func nextTourStep() {
        guard let step = tourStep else { return }
        if step + 1 < tour.count { tourStep = step + 1; applyTourTab() } else { tourStep = nil }
    }
    func endTour() { tourStep = nil }
    private func applyTourTab() {
        if let step = tourStep, step >= 0, let tab = tour[step].tab { store?.tab = tab }
    }
}

extension View {
    /// Tells the helper which screen is open (and its data), so answers are about it.
    func helperScreen(_ title: String, details: String = "") -> some View {
        onAppear { HelperCenter.shared.setScreen(title, details: details) }
    }
}

// MARK: - Views

/// Round button in the corner of every screen.
struct HelperButton: View {
    @ObservedObject var helper = HelperCenter.shared
    var body: some View {
        Button { Haptics.tap(); helper.isOpen = true } label: {
            Image(systemName: "sparkles")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.goldLight)
                .frame(width: 54, height: 54)
                .background(Theme.heroGradient, in: Circle())
                .overlay(Circle().strokeBorder(Theme.goldHairline, lineWidth: 1))
                .shadow(color: Theme.orange.opacity(0.35), radius: 14, y: 6)
        }
        .accessibilityLabel("ИИ‑помощник")
    }
}

/// Apology after an error; tap to open the helper.
struct HelperNoticeBanner: View {
    @ObservedObject var helper = HelperCenter.shared
    @State private var showBilling = false
    @State private var showSupport = false
    var body: some View {
        // Окна — снаружи плашки: она исчезает при нажатии, а окно должно остаться.
        ZStack { banner }
            .sheet(isPresented: $showBilling) { NavigationStack { BillingView() } }
            .sheet(isPresented: $showSupport) { NavigationStack { SupportView(presetTopic: "broken", presetFeature: nil) } }
    }

    @ViewBuilder private var banner: some View {
        if let notice = helper.notice {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: helper.needsTopUp ? "creditcard.fill" : "sparkles").foregroundStyle(Theme.orange)
                VStack(alignment: .leading, spacing: 8) {
                    Text(notice).font(.footnote).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    if helper.needsTopUp {
                        Button { helper.notice = nil; showBilling = true } label: {
                            Label("Пополнить баланс", systemImage: "plus.circle.fill").font(.footnote.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 8).foregroundStyle(Theme.onAccent)
                                .background(Theme.orange, in: Capsule())
                        }
                    } else {
                        Button { helper.notice = nil; showSupport = true } label: {
                            Label("Написать в поддержку", systemImage: "bubble.left.and.bubble.right.fill").font(.footnote.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 8).foregroundStyle(Theme.orange)
                                .background(Theme.accentTint, in: Capsule())
                        }
                    }
                }
                Spacer(minLength: 0)
                Button { helper.notice = nil } label: { Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(Theme.muted).padding(4) }
                    .accessibilityLabel("Скрыть")
            }
            .padding(14)
            .panelCard(18)
            .padding(.horizontal, 16)
            .onTapGesture { helper.notice = nil; if !helper.needsTopUp { helper.isOpen = true } }
            .transition(.move(edge: .top).combined(with: .opacity))
            .task(id: notice) { try? await Task.sleep(for: .seconds(9)); if helper.notice == notice { withAnimation { helper.notice = nil } } }
        }
    }
}

/// The helper chat: suggestions for this screen, photo, streaming answers.
struct HelperChatView: View {
    @ObservedObject var helper = HelperCenter.shared
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var photo: PhotosPickerItem?
    @State private var image: UIImage?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if helper.messages.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                AppMark(size: 48)
                                Text("Чем помочь?").font(.title2.bold()).foregroundStyle(Theme.ink)
                                Text("Отвечу про нормы и расход материалов, разберу смету или фото, подскажу, где что в приложении. Сейчас открыто: «\(helper.screen)».")
                                    .font(.subheadline).foregroundStyle(Theme.muted)
                            }
                            .padding(.bottom, 6)
                        }
                        ForEach(helper.messages) { message in bubble(message).id(message.id) }
                        if helper.isThinking && helper.messages.last?.text.isEmpty == true {
                            HStack(spacing: 8) { ProgressView(); Text("Думаю…").font(.footnote).foregroundStyle(Theme.muted) }
                        }
                        if !helper.isThinking {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(helper.suggestions, id: \.self) { question in
                                    Button { Task { await helper.ask(question) } } label: {
                                        Text(question).font(.subheadline).foregroundStyle(Theme.orange).multilineTextAlignment(.leading)
                                            .padding(.horizontal, 14).padding(.vertical, 10)
                                            .background(Theme.accentTint, in: Capsule())
                                    }
                                }
                                Button { helper.isOpen = false; helper.startTour() } label: {
                                    Label("Показать, что где в приложении", systemImage: "map").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                                        .padding(.horizontal, 14).padding(.vertical, 10).background(Theme.panelRaised, in: Capsule())
                                }
                            }
                            .padding(.top, 4)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(16)
                }
                .onChange(of: helper.messages.last?.text) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            }
            .background(Theme.background)
            .safeAreaInset(edge: .bottom) { composer }
            .navigationTitle("ИИ‑помощник").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } }
                if !helper.messages.isEmpty {
                    ToolbarItem(placement: .topBarLeading) { Button("Очистить") { helper.messages.removeAll() } }
                }
            }
            .onChange(of: photo) { _, item in
                Task { if let data = try? await item?.loadTransferable(type: Data.self) { image = UIImage(data: data) } }
            }
        }
        .tint(Theme.orange)
    }

    private func bubble(_ message: HelperMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 8) {
                if let image = message.image {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: 180, height: 130).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                if !message.text.isEmpty {
                    Text(LocalizedStringKey(message.text)).font(.subheadline)
                        .foregroundStyle(message.role == .user ? Theme.onAccent : Theme.ink)
                        .textSelection(.enabled)
                }
            }
            .padding(12)
            .background(message.role == .user ? AnyShapeStyle(Theme.orange) : AnyShapeStyle(Theme.panel), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(message.role == .user ? 0 : 0.05), radius: 6, y: 2)
            if message.role == .helper { Spacer(minLength: 40) }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if let image {
                HStack {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 10))
                    Text("Фото прикреплено").font(.footnote).foregroundStyle(Theme.muted)
                    Spacer()
                    Button { self.image = nil; photo = nil } label: { Image(systemName: "xmark.circle.fill").accessibilityLabel("Очистить").foregroundStyle(Theme.muted) }
                }
            }
            HStack(spacing: 10) {
                PhotosPicker(selection: $photo, matching: .images) {
                    Image(systemName: "photo").font(.title3).foregroundStyle(Theme.orange).frame(width: 40, height: 40)
                }
                .accessibilityLabel("Прикрепить фото")
                TextField("Спросите что угодно…", text: $text, axis: .vertical)
                    .lineLimit(1...4).focused($focused)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                Button {
                    let question = text; let picture = image
                    text = ""; image = nil; photo = nil
                    Task { await helper.ask(question, image: picture) }
                } label: {
                    Image(systemName: "arrow.up").font(.headline).foregroundStyle(Theme.onAccent)
                        .frame(width: 40, height: 40).background(Theme.orange, in: Circle())
                }
                .disabled((text.trimmingCharacters(in: .whitespaces).isEmpty && image == nil) || helper.isThinking)
                .accessibilityLabel("Отправить")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(.bar)
    }
}

/// The tour: a card at the bottom that walks through the tabs.
struct HelperTourOverlay: View {
    @ObservedObject var helper = HelperCenter.shared
    var body: some View {
        if let step = helper.tourStep {
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.18).ignoresSafeArea().onTapGesture {}
                VStack(alignment: .leading, spacing: 12) {
                    if step < 0 {
                        Label("Показать, что где?", systemImage: "map").font(.headline).foregroundStyle(Theme.ink)
                        Text("Короткая экскурсия по разделам — меньше минуты. Её можно включить позже в профиле или спросить у помощника.")
                            .font(.subheadline).foregroundStyle(Theme.muted)
                        HStack(spacing: 10) {
                            Button("Не сейчас") { helper.endTour() }.buttonStyle(.bordered)
                            Button("Показать") { helper.startTour() }.buttonStyle(.borderedProminent)
                        }
                    } else {
                        let item = helper.tour[step]
                        HStack(spacing: 12) {
                            Image(systemName: item.icon).font(.title3.weight(.semibold)).foregroundStyle(Theme.onAccent)
                                .frame(width: 44, height: 44).background(Theme.orange, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(step + 1) из \(helper.tour.count)").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                                Text(item.title).font(.headline).foregroundStyle(Theme.ink)
                            }
                        }
                        Text(item.text).font(.subheadline).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Пропустить") { helper.endTour() }.foregroundStyle(Theme.muted)
                            Spacer()
                            Button(step + 1 < helper.tour.count ? "Далее" : "Понятно") { helper.nextTourStep() }.buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .panelCard(26)
                .padding(.horizontal, 14)
                .padding(.bottom, 96)
            }
            .tint(Theme.orange)
            .transition(.opacity)
        }
    }
}
