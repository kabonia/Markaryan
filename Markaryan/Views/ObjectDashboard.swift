import SwiftUI
import Speech
import AVFoundation

// MARK: - Бюджет, который назвал человек (на объект)

enum ObjectBudget {
    static func limit(_ object: UUID?) -> Double { object.map { UserDefaults.standard.double(forKey: "objectBudgetLimit.\($0.uuidString)") } ?? 0 }
    static func setLimit(_ value: Double, for object: UUID?) {
        guard let object else { return }
        UserDefaults.standard.set(max(0, value), forKey: "objectBudgetLimit.\(object.uuidString)")
    }
}

/// «1,5 миллиона», «200 тысяч», «20 000», «20к» → число.
enum SpokenNumber {
    static func parse(_ text: String) -> Double? {
        let lower = text.lowercased().replacingOccurrences(of: "\u{00a0}", with: " ")
        guard let range = lower.range(of: #"\d[\d\s]*([.,]\d+)?"#, options: .regularExpression) else { return nil }
        let raw = lower[range].replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")
        guard var value = Double(raw) else { return nil }
        let tail = lower[range.upperBound...].prefix(14)
        if tail.contains("млн") || tail.contains("миллион") || tail.contains("million") { value *= 1_000_000 }
        else if tail.contains("тыс") || tail.hasPrefix("к") || tail.hasPrefix(" к") || tail.contains("thousand") || tail.hasPrefix("k") { value *= 1_000 }
        return value
    }
}

// MARK: - Сводка объекта: деньги, этапы, задачи — на один взгляд

struct ObjectDashboard: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var links = ObjectLinks.shared
    @State private var editingLimit = false
    @State private var limitText = ""
    @State private var limit = 0.0
    @State private var showMore = false

    private var planned: Double { store.budgetPlanned }
    private var actual: Double { store.budgetActual }
    private var overspent: [ProjectBudgetItem] { store.budgetItems.filter { $0.included && $0.planned > 0 && $0.actual > $0.planned * 1.05 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            moneyCard
            stepsCard
            tasksCard
            VoiceCommandCard()
            ObjectLinkedItems()
            ObjectToolsSection()
            ObjectShareCard()
            DisclosureGroup(isExpanded: $showMore) {
                VStack(spacing: 10) {
                    NavigationLink { ProjectPhotoDiaryView() } label: { AppTabRow(icon: "photo.stack.fill", title: "Фото‑дневник", subtitle: store.projectPhotos.isEmpty ? "Скрытые работы и этапы на фото" : "Фото: \(store.projectPhotos.count)") }
                    NavigationLink { ConstructionDiaryView() } label: { AppTabRow(icon: "text.book.closed.fill", title: "Журнал решений", subtitle: store.diary.isEmpty ? "Договорённости, даты, комментарии" : "Записей: \(store.diary.count)") }
                    NavigationLink { ChecklistView() } label: { AppTabRow(icon: "checkmark.shield.fill", title: "Контроль качества", subtitle: "Отмечено пунктов: \(store.checklistDone.count)") }
                    NavigationLink { ObjectPassportView() } label: { AppTabRow(icon: "list.clipboard.fill", title: "Паспорт объекта", subtitle: "Адрес, площадь, этап и заметки") }
                }
                .buttonStyle(PremiumCardPressStyle())
                .padding(.top, 8)
            } label: {
                Text("Ещё: фото‑дневник, журнал, контроль, паспорт").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            }
            .tint(Theme.orange)
        }
        .onAppear { limit = ObjectBudget.limit(store.activeProjectID) }
        .onChange(of: store.activeProjectID) { _, id in limit = ObjectBudget.limit(id) }
        .alert("Мой бюджет на объект", isPresented: $editingLimit) {
            TextField("Например, 1 500 000", text: $limitText).keyboardType(.numberPad)
            Button("Сохранить") {
                limit = SpokenNumber.parse(limitText) ?? 0
                ObjectBudget.setLimit(limit, for: store.activeProjectID)
            }
            Button("Отмена", role: .cancel) {}
        } message: { Text("Сколько вы готовы потратить. Сравним со сметой и тратами.") }
    }

    // MARK: Деньги

    private var moneyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ДЕНЬГИ").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
                Spacer()
                NavigationLink { ProjectBudgetTrackerView() } label: { Text("Статьи и траты").font(.caption.weight(.semibold)) }
            }
            moneyRow("Мой бюджет", limit, color: Theme.ink, action: { limitText = limit > 0 ? CalculationEngine.format(limit) : ""; editingLimit = true },
                     hint: limit > 0 ? nil : "указать")
            moneyRow("Смета (план)", planned, color: Theme.orange, hint: planned > 0 ? nil : "добавьте смету или материалы в бюджет")
            moneyRow("Потрачено (факт)", actual, color: actual > max(planned, limit) && max(planned, limit) > 0 ? Theme.danger : Theme.success, hint: actual > 0 ? nil : "вносите траты в «Статьи и траты» или голосом")
            if max(limit, planned) > 0 { bars }
            verdict
            ForEach(overspent) { item in
                let pct = Int(((item.actual / item.planned) - 1) * 100)
                Label("Перерасход «\(item.title)»: +\(pct) % (\(CalculationEngine.money(item.actual - item.planned)))", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.danger)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).panelCard(18)
    }

    private func moneyRow(_ title: String, _ value: Double, color: Color, action: (() -> Void)? = nil, hint: String? = nil) -> some View {
        Button { action?() } label: {
            HStack(alignment: .firstTextBaseline) {
                Text(title.tr).font(.subheadline).foregroundStyle(Theme.muted)
                Spacer()
                if value > 0 { Text(CalculationEngine.money(value)).font(.headline.monospacedDigit()).foregroundStyle(color) }
                else if let hint { Text(hint.tr).font(.caption).foregroundStyle(action == nil ? Theme.muted : Theme.orange).multilineTextAlignment(.trailing) }
                if action != nil { Image(systemName: "pencil").font(.caption).foregroundStyle(Theme.orange) }
            }
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }

    /// Три полосы в одном масштабе: бюджет, смета, факт.
    private var bars: some View {
        let top = max(limit, planned, actual, 1)
        return VStack(spacing: 5) {
            bar(limit / top, Theme.ink.opacity(0.25))
            bar(planned / top, Theme.orange)
            bar(actual / top, actual > max(planned, limit) && max(planned, limit) > 0 ? Theme.danger : Theme.success)
        }
    }
    private func bar(_ share: Double, _ color: Color) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.panelRaised)
                Capsule().fill(color).frame(width: max(4, g.size.width * min(1, share)))
            }
        }
        .frame(height: 7)
    }

    @ViewBuilder private var verdict: some View {
        if limit > 0 && planned > 0 {
            let diff = planned - limit
            if diff > 0 {
                Label("Смета больше бюджета на \(CalculationEngine.money(diff)) (+\(Int(diff / limit * 100)) %). Уберите часть работ или выберите «Эконом».", systemImage: "exclamationmark.octagon.fill")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Theme.danger)
            } else {
                Label("Укладываетесь в бюджет: запас \(CalculationEngine.money(-diff)).", systemImage: "checkmark.seal.fill")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Theme.success)
            }
        } else if limit == 0 && planned > 0 {
            Text("Укажите свой бюджет — покажем, укладывается ли смета.").font(.caption).foregroundStyle(Theme.muted)
        }
        if planned > 0 && actual > 0 {
            Text("Потрачено \(Int(actual / planned * 100)) % от сметы.").font(.caption).foregroundStyle(Theme.muted)
        }
    }

    // MARK: Этапы: что сделано и что дальше

    private struct Step: Identifiable {
        let id: String
        let title: String
        let detail: String
        let done: Bool
        let icon: String
    }

    private var steps: [Step] {
        let object = store.activeProjectID ?? AppStore.looseWorkID
        let scans = links.items(in: object, kind: .houseScan).count
        let measured = !store.floorPlans.isEmpty || scans > 0
        let materials = store.floorPlans.contains { UserDefaults.standard.data(forKey: "roomWorks.\($0.id.uuidString)") != nil }
        let estimates = links.items(in: object, kind: .docEstimate).count
        let pictures = links.items(in: object, kind: .picture).count + store.floorPlans.filter { !$0.proposals.isEmpty }.count
        let purchase = ObjectPurchase.lines(store: store)
        let bought = Set(UserDefaults.standard.stringArray(forKey: "purchaseBought.\(object.uuidString)") ?? []).intersection(Set(purchase.map(\.id))).count
        let doneTasks = store.projectTasks.filter { $0.status == .done }.count
        return [
            Step(id: "measure", title: "Обмер", detail: measured ? "Комнат: \(store.floorPlans.count) · домов: \(scans)" : "Скан комнаты или 3D‑обмер дома", done: measured, icon: "viewfinder"),
            Step(id: "materials", title: "Материалы", detail: materials ? "Посчитаны по скану" : "Откройте комнату → «Материалы, цены и визуализация»", done: materials, icon: "shippingbox.fill"),
            Step(id: "estimate", title: "Смета и бюджет", detail: planned > 0 ? "План \(CalculationEngine.money(planned))" + (estimates > 0 ? " · смет: \(estimates)" : "") : "Смета дома, по документам или материалы → «В бюджет»", done: planned > 0, icon: "rublesign.circle.fill"),
            Step(id: "design", title: "Дизайн и визуализация", detail: pictures > 0 ? "Готово картинок и концепций: \(pictures)" : "Стиль комнаты или «Показать с этой отделкой»", done: pictures > 0, icon: "paintpalette.fill"),
            Step(id: "purchase", title: "Закупка", detail: purchase.isEmpty ? "Появится после расчёта материалов" : "Куплено \(bought) из \(purchase.count)", done: !purchase.isEmpty && bought == purchase.count, icon: "cart.fill"),
            Step(id: "works", title: "Работы", detail: store.projectTasks.isEmpty ? "Смета → «План работ» или задачи вручную" : "Готово \(doneTasks) из \(store.projectTasks.count) задач", done: !store.projectTasks.isEmpty && doneTasks == store.projectTasks.count, icon: "hammer.fill"),
        ]
    }

    private var stepsCard: some View {
        let list = steps
        let done = list.filter(\.done).count
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("ЭТАПЫ").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
                Spacer()
                Text("\(done) из \(list.count)").font(.caption.weight(.bold)).monospacedDigit().foregroundStyle(Theme.orange)
            }
            ProgressView(value: Double(done), total: Double(list.count)).tint(Theme.orange).padding(.bottom, 6)
            ForEach(list) { step in
                stepLink(step) {
                    HStack(spacing: 12) {
                        Image(systemName: step.done ? "checkmark.circle.fill" : step.icon).font(.title3)
                            .foregroundStyle(step.done ? Theme.success : Theme.orange).frame(width: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title.tr).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                            Text(step.detail).font(.caption).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 8)
                }
                if step.id != list.last?.id { Divider().padding(.leading, 42) }
            }
        }
        .padding(16).panelCard(18)
    }

    @ViewBuilder private func stepLink<Label: View>(_ step: Step, @ViewBuilder label: () -> Label) -> some View {
        switch step.id {
        case "measure": Menu { Button("Скан комнаты", systemImage: "camera.metering.matrix") { store.showRoomScan = true }; Button("3D‑обмер дома", systemImage: "house.lodge") { store.showHouseScan = true } } label: { label() }
        case "materials", "design": Button { if let plan = store.floorPlans.first { store.planToOpen = plan.id }; store.tab = 2 } label: { label() }.buttonStyle(.plain)
        case "estimate": NavigationLink { FullEstimateHubView() } label: { label() }.buttonStyle(.plain)
        case "purchase": NavigationLink { ObjectPurchaseView() } label: { label() }.buttonStyle(.plain)
        default: NavigationLink { ProjectTasksView() } label: { label() }.buttonStyle(.plain)
        }
    }

    // MARK: Задачи

    private var tasksCard: some View {
        let open = store.projectTasks.filter { $0.status != .done }.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("БЛИЖАЙШИЕ ЗАДАЧИ").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
                Spacer()
                NavigationLink { ProjectTasksView() } label: { Text(open.isEmpty ? "Добавить" : "Все \(store.projectTasks.count)").font(.caption.weight(.semibold)) }
            }
            if open.isEmpty {
                Text("Открытых задач нет. Добавьте вручную, голосом или из сметы → «План работ».").font(.caption).foregroundStyle(Theme.muted)
            }
            ForEach(open.prefix(3)) { task in
                Button {
                    if let i = store.projectTasks.firstIndex(where: { $0.id == task.id }) { withAnimation { store.projectTasks[i].status = .done }; Haptics.success() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "circle").foregroundStyle(Theme.muted)
                        Text(task.title).font(.subheadline).foregroundStyle(Theme.ink).lineLimit(2)
                        Spacer()
                        if let due = task.dueDate {
                            Text(due.formatted(.dateTime.day().month(.abbreviated))).font(.caption.weight(.semibold))
                                .foregroundStyle(due < Date() ? Theme.danger : Theme.muted)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            if !open.isEmpty { Text("Нажмите на задачу — она отметится выполненной.").font(.caption2).foregroundStyle(Theme.muted) }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).panelCard(18)
    }
}

// MARK: - Голосом: «бюджет 1,5 миллиона», «потратил 20 тысяч на плитку», «задача купить клей»

@MainActor final class VoiceCommandRecognizer: ObservableObject {
    @Published var listening = false
    @Published var text = ""
    @Published var problem: String?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start() async {
        problem = nil
        let speech = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        guard speech == .authorized else { problem = "Разрешите распознавание речи: Настройки → \(Brand.name)."; return }
        guard await AVAudioApplication.requestRecordPermission() else { problem = "Разрешите микрофон: Настройки → \(Brand.name)."; return }
        let locale = AppLanguage.isRussian ? Locale(identifier: "ru-RU") : Locale.current
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else { problem = "Распознавание речи сейчас недоступно."; return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? session.setActive(true, options: .notifyOthersOnDeactivation)
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in request.append(buffer) }
        engine.prepare()
        do { try engine.start() } catch { problem = "Микрофон занят."; input.removeTap(onBus: 0); return }
        self.request = request
        text = ""
        listening = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result { self.text = result.bestTranscription.formattedString }
                if error != nil || result?.isFinal == true { self.stop() }
            }
        }
    }

    func stop() {
        guard listening else { return }
        listening = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Что поняли из фразы — показываем до выполнения.
enum VoiceAction: Equatable {
    case budget(Double)
    case spend(Double, item: String)
    case task(String)
    case note(String)

    var title: String {
        switch self {
        case .budget(let v): "Бюджет объекта: \(CalculationEngine.money(v))"
        case .spend(let v, let item): "Трата \(CalculationEngine.money(v)) → «\(item)»"
        case .task(let t): "Задача: \(t)"
        case .note(let t): "Запись в журнал: \(t)"
        }
    }

    @MainActor static func parse(_ text: String, store: AppStore) -> VoiceAction? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        let lower = clean.lowercased()
        if lower.contains("бюджет") || lower.contains("budget"), let value = SpokenNumber.parse(lower) { return .budget(value) }
        if ["потратил", "потратила", "оплатил", "оплатила", "заплатил", "заплатила", "купил", "купила", "spent", "paid"].contains(where: { lower.contains($0) }),
           let value = SpokenNumber.parse(lower) {
            let keywords: [(String, [String])] = [("Отделка", ["плитк", "клей", "краск", "обо", "ламинат", "штукатур", "отделк", "шпакл"]),
                                                  ("Кровля", ["кровл", "крыш", "черепиц"]), ("Фундамент", ["фундамент", "бетон", "арматур"]),
                                                  ("Инженерия", ["электрик", "кабел", "труб", "сантех", "котел", "котёл"]), ("Фасад", ["фасад", "сайдинг"]),
                                                  ("Коробка", ["кирпич", "газобетон", "блок", "брус"]), ("Доставка и техника", ["доставк", "техник", "кран", "экскаватор"])]
            let match = store.budgetItems.first { item in lower.contains(item.title.lowercased()) }?.title
                ?? keywords.first { _, words in words.contains { lower.contains($0) } }?.0
                ?? store.budgetItems.first?.title ?? "Отделка"
            return .spend(value, item: match)
        }
        for prefix in ["задача", "задачу", "надо", "нужно", "сделать", "напомни", "task"] where lower.hasPrefix(prefix) || lower.contains("добавь задачу") {
            var title = clean
            for word in ["добавь задачу", "Добавь задачу", "задача", "Задача", "задачу", "Задачу"] { title = title.replacingOccurrences(of: word, with: "") }
            title = title.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            return .task(title.isEmpty ? clean : title.prefix(1).uppercased() + title.dropFirst())
        }
        return .note(clean)
    }

    @MainActor func apply(store: AppStore) {
        switch self {
        case .budget(let v): ObjectBudget.setLimit(v, for: store.activeProjectID)
        case .spend(let v, let item):
            if let i = store.budgetItems.firstIndex(where: { $0.title == item }) { store.budgetItems[i].actual += v.rounded() }
            else { var b = ProjectBudgetItem(id: "budget-\(UUID().uuidString)", title: item); b.actual = v.rounded(); store.budgetItems.append(b) }
        case .task(let t): store.projectTasks.insert(ProjectTask(title: t), at: 0)
        case .note(let t): store.addDiary(t)
        }
    }
}

struct VoiceCommandCard: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var voice = VoiceCommandRecognizer()
    @State private var action: VoiceAction?
    @State private var done: String?
    @State private var typed = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button { Task { if voice.listening { voice.stop() } else { done = nil; action = nil; await voice.start() } } } label: {
                    Image(systemName: voice.listening ? "stop.fill" : "mic.fill").font(.title3.weight(.semibold)).foregroundStyle(Theme.onAccent)
                        .frame(width: 50, height: 50).background(voice.listening ? AnyShapeStyle(Theme.danger) : AnyShapeStyle(Theme.accentGradient), in: Circle())
                }
                .accessibilityLabel(voice.listening ? "Остановить" : "Сказать команду")
                VStack(alignment: .leading, spacing: 2) {
                    Text(voice.listening ? "Слушаю…" : "Скажите или напишите").font(.subheadline.weight(.semibold))
                    Text("«Бюджет полтора миллиона» · «Потратил 20 тысяч на плитку» · «Задача купить клей»").font(.caption2).foregroundStyle(Theme.muted)
                }
            }
            if !voice.listening {
                TextField("Или напишите команду", text: $typed).submitLabel(.done)
                    .onSubmit { action = VoiceAction.parse(typed, store: store) }
                    .padding(10).background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
            }
            if !voice.text.isEmpty { Text("«\(voice.text)»").font(.footnote).foregroundStyle(Theme.ink) }
            if let action {
                HStack {
                    Label(action.title, systemImage: "wand.and.stars").font(.footnote.weight(.semibold)).foregroundStyle(Theme.orange)
                    Spacer()
                    Button("Выполнить") { action.apply(store: store); done = action.title; self.action = nil; typed = ""; voice.text = ""; Haptics.success() }
                        .font(.footnote.weight(.bold))
                }
            }
            if let done { Label("Готово: \(done)", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Theme.success) }
            if let problem = voice.problem { Text(problem).font(.caption).foregroundStyle(Theme.danger) }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).panelCard(18)
        .onChange(of: voice.listening) { _, listening in if !listening, !voice.text.isEmpty { action = VoiceAction.parse(voice.text, store: store) } }
    }
}

// MARK: - Совместный доступ: супруг или прораб видят и правят тот же объект

@MainActor enum ObjectSync {
    static func code(_ id: UUID) -> String? { UserDefaults.standard.string(forKey: "objectShareCode.\(id.uuidString)") }
    static func version(_ id: UUID) -> Int { UserDefaults.standard.integer(forKey: "objectShareVersion.\(id.uuidString)") }
    private static func remember(_ id: UUID, code: String?, version: Int) {
        UserDefaults.standard.set(code, forKey: "objectShareCode.\(id.uuidString)")
        UserDefaults.standard.set(version, forKey: "objectShareVersion.\(id.uuidString)")
    }

    private static func request(_ path: String, method: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        guard let base = AIServerConfig.marketURL else { throw ClaudeError.api("Нет связи с сервером.") }
        var r = URLRequest(url: base.appendingPathComponent(path))
        r.httpMethod = method
        r.timeoutInterval = 60
        r.setValue(AIServerConfig.installID, forHTTPHeaderField: "X-Install-ID")
        if !AIServerConfig.appToken.isEmpty { r.setValue(AIServerConfig.appToken, forHTTPHeaderField: "X-App-Token") }
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { r.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: r)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ClaudeError.api(json["error"] as? String ?? "Сервер не ответил.") }
        return json
    }

    /// Объект без фото (они остаются в телефоне) — в JSON для сервера.
    private static func payload(_ w: ProjectWorkspace) throws -> Any {
        var copy = w
        copy.projectPhotos = []
        return try JSONSerialization.jsonObject(with: JSONEncoder().encode(copy))
    }
    private static func decode(_ any: Any?) -> ProjectWorkspace? {
        guard let any, let data = try? JSONSerialization.data(withJSONObject: any) else { return nil }
        return try? JSONDecoder().decode(ProjectWorkspace.self, from: data)
    }

    /// Слить правки: списки — по id без потерь; задачи — самый продвинутый статус; траты — большая сумма.
    static func merge(local: ProjectWorkspace, remote: ProjectWorkspace) -> ProjectWorkspace {
        var out = remote
        out.projectPhotos = local.projectPhotos
        out.checklistDone = local.checklistDone.union(remote.checklistDone)
        out.diary = (remote.diary + local.diary.filter { l in !remote.diary.contains { $0.id == l.id } }).sorted { $0.date > $1.date }
        out.floorPlans = remote.floorPlans + local.floorPlans.filter { l in !remote.floorPlans.contains { $0.id == l.id } }
        let rank: [ProjectTaskStatus: Int] = [.planned: 0, .inProgress: 1, .done: 2]
        out.tasks = remote.tasks.map { r in
            guard let l = local.tasks.first(where: { $0.id == r.id }) else { return r }
            var m = r; if (rank[l.status] ?? 0) > (rank[r.status] ?? 0) { m.status = l.status }; return m
        } + local.tasks.filter { l in !remote.tasks.contains { $0.id == l.id } }
        out.budgetItems = remote.budgetItems.map { r in
            guard let l = local.budgetItems.first(where: { $0.id == r.id }) else { return r }
            var m = r; m.actual = max(l.actual, r.actual); if m.planned == 0 { m.planned = l.planned }; return m
        } + local.budgetItems.filter { l in !remote.budgetItems.contains { $0.id == l.id } }
        out.milestones = remote.milestones.map { r in
            var m = r; if local.milestones.first(where: { $0.id == r.id })?.completed == true { m.completed = true }; return m
        }
        return out
    }

    static func share(_ id: UUID, store: AppStore) async throws -> String {
        guard let w = store.workspaceSnapshot(id) else { throw ClaudeError.api("Объект не найден.") }
        let json = try await request("v1/objects", method: "POST", body: ["workspace": try payload(w)])
        guard let code = json["code"] as? String else { throw ClaudeError.badResponse }
        remember(id, code: code, version: json["version"] as? Int ?? 1)
        return code
    }

    /// Открыть чужой объект по коду: он появится в «Мои объекты» и станет текущим.
    static func join(_ code: String, store: AppStore) async throws {
        let clean = code.uppercased().filter { $0.isLetter || $0.isNumber }
        let json = try await request("v1/objects/\(clean)", method: "GET")
        guard let remote = decode(json["workspace"]) else { throw ClaudeError.badResponse }
        let merged = store.workspaceSnapshot(remote.id).map { merge(local: $0, remote: remote) } ?? remote
        store.replaceWorkspace(merged)
        remember(remote.id, code: clean, version: json["version"] as? Int ?? 1)
        store.selectProject(remote.id)
    }

    /// Забрать правки другого человека и отправить свои.
    static func sync(_ id: UUID, store: AppStore) async throws {
        guard let code = code(id) else { return }
        for _ in 0..<3 {
            guard let local = store.workspaceSnapshot(id) else { return }
            let json = try await request("v1/objects/\(code)", method: "PUT", body: ["baseVersion": version(id), "workspace": try payload(local)])
            if json["conflict"] as? Bool == true, let remote = decode(json["workspace"]) {
                store.replaceWorkspace(merge(local: local, remote: remote))
                remember(id, code: code, version: json["version"] as? Int ?? 0)
                continue
            }
            remember(id, code: code, version: json["version"] as? Int ?? version(id))
            return
        }
    }

    static func leave(_ id: UUID) async {
        guard let code = code(id) else { return }
        _ = try? await request("v1/objects/\(code)/leave", method: "POST", body: [:])
        remember(id, code: nil, version: 0)
    }
}

struct ObjectShareCard: View {
    @EnvironmentObject private var store: AppStore
    @State private var busy = false
    @State private var message: String?
    @State private var joinCode = ""
    @State private var joining = false

    var body: some View {
        let id = store.activeProjectID ?? AppStore.looseWorkID
        let code = ObjectSync.code(id)
        VStack(alignment: .leading, spacing: 10) {
            Text("СОВМЕСТНЫЙ ДОСТУП").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
            if let code {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Код объекта").font(.caption).foregroundStyle(Theme.muted)
                        Text(code).font(.system(.title3, design: .monospaced, weight: .bold))
                    }
                    Spacer()
                    ShareLink(item: "Открой наш объект «\(store.projectDisplayName)» в приложении \(Brand.name): Объекты → «Открыть по коду» → \(code)") {
                        Image(systemName: "square.and.arrow.up").font(.title3)
                    }
                }
                HStack(spacing: 10) {
                    Button { Task { await run { try await ObjectSync.sync(id, store: store); return "Синхронизировано" } } } label: { SecondaryActionLabel(title: busy ? "Синхронизируем…" : "Синхронизировать", icon: "arrow.triangle.2.circlepath") }
                    Button(role: .destructive) { Task { await ObjectSync.leave(id); message = "Совместный доступ выключен" } } label: { SecondaryActionLabel(title: "Выключить", icon: "person.crop.circle.badge.xmark") }
                }
                .buttonStyle(PremiumPressStyle()).disabled(busy)
                Text("Супруг или прораб видят смету, бюджет, задачи и комнаты и вносят свои правки. Фото остаются у каждого в телефоне.").font(.caption2).foregroundStyle(Theme.muted)
            } else {
                Button { Task { await run { let c = try await ObjectSync.share(id, store: store); return "Код объекта: \(c)" } } } label: {
                    SecondaryActionLabel(title: busy ? "Готовим…" : "Пригласить супруга или прораба", icon: "person.2.fill")
                }
                .buttonStyle(PremiumPressStyle()).disabled(busy || !store.inObject)
            }
            Button { joining = true } label: { Text("Открыть объект по коду").font(.caption.weight(.semibold)) }
            if let message { Text(message).font(.caption).foregroundStyle(Theme.muted) }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).panelCard(18)
        .task(id: store.activeProjectID) { if ObjectSync.code(id) != nil { try? await ObjectSync.sync(id, store: store) } }
        .alert("Открыть по коду", isPresented: $joining) {
            TextField("8 букв и цифр", text: $joinCode).textInputAutocapitalization(.characters)
            Button("Открыть") { Task { await run { try await ObjectSync.join(joinCode, store: store); return "Объект открыт" } } }
            Button("Отмена", role: .cancel) {}
        } message: { Text("Код вам пришлёт владелец объекта.") }
    }

    private func run(_ work: () async throws -> String) async {
        busy = true; defer { busy = false }
        do { message = try await work(); Haptics.success() } catch { message = error.localizedDescription }
    }
}
