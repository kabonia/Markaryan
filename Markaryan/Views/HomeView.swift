import SwiftUI
import PhotosUI

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var appeared = false
    @State private var visible = true
    @State private var liveOpen: LiveExample?
    @State private var showTryOn = false
    @State private var unsentScans = 0

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: return "Доброе утро"
        case 12..<18: return "Добрый день"
        case 18..<23: return "Добрый вечер"
        default: return "Доброй ночи"
        }
    }

    private let quickCalculators: [CalculationKind] = [.concreteMix, .tiles, .paint, .screed, .masonry, .rebar, .plaster, .drywall, .roof, .fence]

    var body: some View {
        content
            .task {
                unsentScans = HouseScanStore.pending().count
                await Task.detached(priority: .background) { HouseScanStore.cleanupUploaded() }.value
            }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                    .reveal(appeared, delay: 0)

                NavigationLink { PhotoDesignView() } label: { HomeHeroCard(greeting: greeting) }
                    .buttonStyle(PremiumCardPressStyle())
                    .reveal(appeared, delay: 0.05)

                // Скан дома, который не дошёл до сервера (оборвалась связь) — не теряем: напоминаем и продолжаем загрузку.
                if unsentScans > 0 {
                    Button { store.showHouseScan = true } label: {
                        Label(unsentScans == 1 ? "Скан дома не отправлен — продолжить загрузку" : "Есть неотправленные сканы дома — продолжить загрузку",
                              systemImage: "icloud.and.arrow.up")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.goldTint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(PremiumPressStyle())
                }

                VStack(alignment: .leading, spacing: 14) {
                    HomeSectionHeader(eyebrow: "Смотрите вживую", title: "Что можно сделать")
                    LiveExamplesCard(paused: !visible) { example in
                        switch example {
                        case .design: store.tab = 2
                        case .ar: store.showAR = true
                        case .calculator: store.tab = 1
                        case .house: store.showHouseScan = true
                        default: liveOpen = example
                        }
                    }
                }
                .reveal(appeared, delay: 0.08)

                if let alert = store.priceAlert { PriceAlertBanner(text: alert) { store.priceAlert = nil } }

                VStack(alignment: .leading, spacing: 14) {
                    HomeSectionHeader(eyebrow: "Популярное", title: "Инструменты")
                    Button { store.showHouseScan = true } label: { HouseScanHomeCard(paused: !visible) }
                        .buttonStyle(PremiumCardPressStyle())
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        NavigationLink { DocEstimateHubView() } label: {
                            HomeToolCard(icon: "doc.text.magnifyingglass", title: "Смета по документам", text: "АР, КР, ТЗ или перечень работ — точная смета ИИ‑сметчиками с ценами рынка.", accent: Theme.orange, badge: "НОВОЕ")
                        }
                        Button { store.tab = 2 } label: {
                            HomeToolCard(icon: "cube.transparent", title: "Дизайн комнаты", text: "Скан лидаром, обмеры, стиль и фотореалистичный рендер по точной геометрии.", accent: Theme.orange, badge: "ХИТ")
                        }
                        Button { store.showAR = true } label: {
                            HomeToolCard(icon: "viewfinder", title: "AR‑рулетка", text: "Длины, площадь и периметр камерой телефона — без рулетки.", accent: Theme.success)
                        }
                        NavigationLink { PhotoCountView() } label: {
                            HomeToolCard(icon: "camera.viewfinder", title: "Сколько в пачке", text: "ИИ считает торцы арматуры, труб, досок и бруса на фото.", accent: Theme.gold)
                        }
                        Button { HelperCenter.shared.isOpen = true } label: {
                            HomeToolCard(icon: "sparkles", title: "ИИ‑помощник", text: "Подскажет нормы и расход, разберёт смету или фото, покажет, что где.", accent: Theme.gold)
                        }
                        NavigationLink { FullEstimateHubView() } label: {
                            HomeToolCard(icon: "house.fill", title: "Смета дома", text: "Работы и материалы по рыночным ценам вашего города с вилкой цен.", accent: Theme.orange)
                        }
                    }
                    .buttonStyle(PremiumCardPressStyle())
                    NavigationLink { AIVisionStudioView(initialStyle: .object) } label: {
                        HomeWideToolCard(icon: "wand.and.stars", title: "Визуализация дома и участка", text: "Фасад, крыша, забор, ландшафт — по фото участка или по описанию идеи.")
                    }
                    .buttonStyle(PremiumCardPressStyle())
                    Button { showTryOn = true } label: {
                        HomeWideToolCard(icon: "arkit", title: "Примерка ремонта в AR", text: "Наведите iPhone на комнату — новая плитка, ламинат или краска вживую на ваших стенах и полу. Сфотографируйте плитку в магазине — сразу увидите её у себя.")
                    }
                    .buttonStyle(PremiumCardPressStyle())
                    NavigationLink { AcceptanceView() } label: {
                        HomeWideToolCard(icon: "checkmark.seal.fill", title: "Приёмка без приёмщика", text: "Лидар меряет ровность стен и пола по нормам СП, ИИ находит дефекты на фото — готовый акт для застройщика или бригады.")
                    }
                    .buttonStyle(PremiumCardPressStyle())
                    NavigationLink { PhotoRoomView() } label: {
                        HomeWideToolCard(icon: "camera.aperture", title: "Ремонт по фото комнаты", text: "Без лидара: размеры по снимку → материалы, цены со ссылками и картинка с новой отделкой.")
                    }
                    .buttonStyle(PremiumCardPressStyle())
                    NavigationLink { QuoteCheckView() } label: {
                        HomeWideToolCard(icon: "checkmark.shield.fill", title: "Проверить смету подрядчика", text: "Фото или PDF сметы → сверка с ценами города со ссылками: где завышено, сколько переплата и что забыли.")
                    }
                    .buttonStyle(PremiumCardPressStyle())
                    NavigationLink { ReceiptScanView() } label: {
                        HomeWideToolCard(icon: "receipt.fill", title: "Чек → в бюджет", text: "Сфотографируйте чек — сумма сама попадёт в траты объекта, перерасход виден сразу.")
                    }
                    .buttonStyle(PremiumCardPressStyle())
                }
                .reveal(appeared, delay: 0.1)

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .lastTextBaseline) {
                        HomeSectionHeader(eyebrow: "За 10 секунд", title: "Калькуляторы")
                        Spacer()
                        Button("Все") { store.tab = 1 }.font(.subheadline.weight(.semibold))
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(quickCalculators, id: \.self) { kind in
                                NavigationLink { CalculatorView(kind: kind) } label: { HomeCalculatorChip(kind: kind) }
                                    .buttonStyle(PremiumCardPressStyle())
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.horizontal, -20)
                }
                .reveal(appeared, delay: 0.15)

                NavigationLink { ProjectHubView() } label: {
                    HomeProjectCard(name: store.projectDisplayName, stage: store.passport.stage, progress: store.projectProgress, next: store.nextMilestone?.title, planned: store.budgetPlanned, actual: store.budgetActual)
                }
                .buttonStyle(PremiumCardPressStyle())
                .reveal(appeared, delay: 0.2)

                SiteWeatherCard()

                if !store.calculations.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .lastTextBaseline) {
                            HomeSectionHeader(eyebrow: "Недавнее", title: "Мои расчёты")
                            Spacer()
                            NavigationLink("Все") { CalculationHistoryView() }.font(.subheadline.weight(.semibold))
                        }
                        ForEach(store.calculations.prefix(2)) { item in
                            NavigationLink { SavedCalculationView(item: item) } label: {
                                AppTabRow(icon: item.kind.icon, title: item.kind.title, subtitle: "\(item.object) · \(item.date.formatted(date: .abbreviated, time: .omitted))")
                            }
                            .buttonStyle(PremiumCardPressStyle())
                        }
                    }
                }

            }
            .padding(20)
        }
        .background(HomeBackdrop())
        .toolbar(.hidden, for: .navigationBar)
        .helperScreen("Главная").featureIntro(.home)
        .refreshable { await store.refreshPriceBook(silent: true) }
        .fullScreenCover(isPresented: $showTryOn) { ARTryOnView() }
        .navigationDestination(item: $liveOpen) { example in
            switch example {
            case .documents: DocEstimateHubView()
            case .count: PhotoCountView()
            default: PhotoDesignView()
            }
        }
        .onAppear { visible = true; if !appeared { withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { appeared = true } } }
        .onDisappear { visible = false }
    }

    private var header: some View {
        HStack(spacing: 12) {
            AppMark(size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(Brand.name).font(.headline)
                Button { store.showRegionPicker = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill").font(.system(size: 9))
                        Text(store.projectCity).font(.caption.weight(.semibold))
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
                ObjectContextChip().padding(.top, 2)
            }
            Spacer()
            NavigationLink { BillingView() } label: { BalanceChip() }
                .buttonStyle(PremiumPressStyle())
        }
    }
}

/// Soft glow behind the dashboard.
struct HomeBackdrop: View {
    var body: some View {
        ZStack {
            Theme.background
            // colours of the logo: emerald and gold light washing over the ivory
            LinearGradient(colors: [Theme.orange.opacity(0.16), Theme.goldTint.opacity(0.5), Theme.background.opacity(0)], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.45))
            Glow(color: Theme.orange.opacity(0.22), size: 560).offset(x: 160, y: -340)
            Glow(color: Lux.goldMid.opacity(0.20), size: 460).offset(x: -170, y: -120)
            Glow(color: Theme.orangeSoft.opacity(0.10), size: 520).offset(x: 150, y: 380)
        }
        .ignoresSafeArea()
    }
}

struct HomeSectionHeader: View {
    let eyebrow: String
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow.tr.uppercased()).font(.caption.weight(.bold)).tracking(1.6).foregroundStyle(Theme.gold)
            Text(title.tr).font(.title3.bold()).tracking(-0.4)
        }
    }
}

/// The big card on top: greeting and the most impressive feature.
struct HomeHeroCard: View {
    let greeting: String
    @State private var glow = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Theme.heroGradient
            Glow(color: .white.opacity(0.16), size: 340).opacity(glow ? 1 : 0.55).offset(x: 190, y: -150)
            Glow(color: Theme.goldLight.opacity(0.28), size: 320).opacity(glow ? 1 : 0.5).offset(x: -60, y: 120)
            HStack(spacing: -40) {
                StyleRoomIllustration(palette: ["#F4F2EE", "#D8C3A5", "#7B8C83", "#C9714A"])
                    .frame(width: 120, height: 88).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .rotationEffect(.degrees(-8)).offset(y: 14)
                StyleRoomIllustration(palette: ["#1F3B3A", "#C8A15A", "#EDE3D1", "#6B2D3A"])
                    .frame(width: 128, height: 94).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .rotationEffect(.degrees(6))
                    .shadow(color: .black.opacity(0.4), radius: 14, y: 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.top, 18).padding(.trailing, -18)
            VStack(alignment: .leading, spacing: 10) {
                Text(greeting.uppercased()).font(.caption.weight(.bold)).tracking(1.8).foregroundStyle(Theme.goldLight)
                Text("Ремонт и стройка,\nкоторые видно заранее").font(.system(.title, design: .serif, weight: .bold)).tracking(-0.4).foregroundStyle(.white)
                Text("Сфотографируйте комнату — ИИ покажет её в новом стиле.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Image(systemName: "camera.aperture")
                    Text("Попробовать дизайн по фото").font(.subheadline.weight(.semibold))
                    Image(systemName: "arrow.right").font(.caption.weight(.bold))
                }
                .foregroundStyle(Theme.orange).padding(.horizontal, 14).padding(.vertical, 11)
                .background(.white, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                .padding(.top, 4)
            }
            .padding(22)
        }
        .frame(maxWidth: .infinity, minHeight: 330, alignment: .bottomLeading)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Theme.goldHairline, lineWidth: 1))
        .shadow(color: Theme.orange.opacity(0.25), radius: 24, y: 12)
        .onAppear { withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { glow = true } }
    }
}

/// A tool on the dashboard: what it is and what it does, in one look.
struct HomeToolCard: View {
    let icon: String
    let title: String
    let text: String
    let accent: Color
    var badge: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: icon).font(.title3.weight(.semibold)).foregroundStyle(accent)
                    .frame(width: 46, height: 46)
                    .background(accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(accent.opacity(0.18), lineWidth: 0.6))
                Spacer(minLength: 0)
                if let badge {
                    Text(badge).font(.system(size: 9, weight: .heavy)).tracking(0.8).padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Theme.goldTint, in: Capsule()).foregroundStyle(Theme.gold)
                        .overlay(Capsule().strokeBorder(Theme.gold.opacity(0.25), lineWidth: 0.5))
                }
            }
            Text(title.tr).font(.system(.subheadline, design: .serif, weight: .bold)).foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.85)
            Text(text.tr).font(.caption).foregroundStyle(Theme.muted).lineLimit(4).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        .panelCard(22)
    }
}

struct HomeWideToolCard: View {
    let icon: String
    let title: String
    let text: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title3.weight(.semibold)).foregroundStyle(Theme.onAccent)
                .frame(width: 48, height: 48).background(Theme.orange, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title.tr).font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
                Text(text.tr).font(.caption).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
        }
        .padding(15)
        .panelCard(22)
    }
}

struct HomeCalculatorChip: View {
    let kind: CalculationKind
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: kind.icon).font(.body.weight(.semibold)).foregroundStyle(Theme.orange)
                .frame(width: 36, height: 36).background(Theme.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            Text(kind.title).font(.footnote.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(2).multilineTextAlignment(.leading)
            Text(kind.summary).font(.caption2).foregroundStyle(Theme.muted).lineLimit(2).multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 148, height: 140, alignment: .topLeading)
        .panelCard(18)
    }
}

extension View {
    /// Fades and lifts the dashboard blocks in one after another on the first appearance.
    func reveal(_ shown: Bool, delay: Double) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .animation(.spring(response: 0.55, dampingFraction: 0.86).delay(delay), value: shown)
    }
}

struct PriceAlertBanner: View {
    let text: String
    let onClose: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill").font(.title3).foregroundStyle(Theme.orange)
            VStack(alignment: .leading, spacing: 5) { Text("Цены обновились").font(.headline); Text(text.tr).font(.caption).foregroundStyle(Theme.muted) }
            Spacer()
            Button(action: onClose) { Image(systemName: "xmark").foregroundStyle(Theme.muted).padding(4) }.accessibilityLabel("Скрыть")
        }
        .padding(16).background(Theme.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct HomeProjectCard: View {
    let name: String
    let stage: String
    let progress: Double
    let next: String?
    let planned: Double
    let actual: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ТЕКУЩИЙ ОБЪЕКТ").font(.caption2.weight(.bold)).tracking(1.25).foregroundStyle(.white.opacity(0.62))
                Spacer()
                Text("\(Int(progress * 100))%").font(.headline.bold()).monospacedDigit().foregroundStyle(.white)
            }
            Text(name).font(.title3.bold()).foregroundStyle(.white)
            ProgressView(value: progress).tint(Theme.orange)
            HStack(spacing: 7) {
                Circle().fill(Theme.success).frame(width: 7, height: 7)
                Text(next.map { "Этап: \(stage) · далее: \($0)" } ?? "Все этапы закрыты").font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.88)).lineLimit(1)
            }
            if planned > 0 {
                HStack {
                    Text("Бюджет \(CalculationEngine.money(planned))").font(.caption).foregroundStyle(Theme.muted)
                    Spacer()
                    Text("потрачено \(CalculationEngine.money(actual))").font(.caption).foregroundStyle(actual > planned ? Theme.danger : Theme.muted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.orange.opacity(0.18), lineWidth: 1))
    }
}

struct HomeActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Image(systemName: icon).font(.title3.weight(.semibold)).foregroundStyle(accent)
                .frame(width: 40, height: 40).background(accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Spacer(minLength: 4)
            Text(title.tr).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(2)
            Text(subtitle.tr).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .padding(16)
        .panelCard(19)
    }
}

struct HomeMetric: View {
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.title2.bold()).monospacedDigit().foregroundStyle(Theme.ink)
            Text(caption.tr).font(.caption).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .panelCard(16)
    }
}

struct ObjectPassportView: View {
    @EnvironmentObject private var store: AppStore
    private let stages = ["Планирование", "Подготовка", "Фундамент", "Коробка", "Кровля", "Отделка", "Сдан"]
    var body: some View {
        Form {
            Section("Объект") {
                TextField("Название объекта", text: $store.passport.name)
                TextField("Адрес или район", text: $store.passport.address)
                TextField("Площадь, м²", text: $store.passport.area).keyboardType(.decimalPad)
                Picker("Текущий этап", selection: $store.passport.stage) { ForEach(stages, id: \.self) { Text($0) } }
            }
            Section("Заметка") { TextEditor(text: $store.passport.notes).frame(minHeight: 110) }
            Section("Рабочие инструменты") {
                NavigationLink { ChecklistView() } label: { Label("Чек-лист контроля", systemImage: "checklist") }
                NavigationLink { ProjectBudgetTrackerView() } label: { Label("Бюджет по этапам", systemImage: "rublesign.circle") }
                NavigationLink { ConstructionDiaryView() } label: { Label("Журнал решений", systemImage: "book.closed") }
            }
            Section { Text("Паспорт, чек-листы и дневник хранятся только на этом iPhone.").font(.footnote).foregroundStyle(Theme.muted) }
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("Паспорт объекта").helperScreen("Паспорт объекта")
    }
}

struct ChecklistView: View {
    @EnvironmentObject private var store: AppStore
    private let groups: [(title: String, items: [(String, String)])] = [
        ("Перед стартом", [
            ("start-1", "Уточнить границы участка и разрешённое использование"),
            ("start-2", "Согласовать смету, договор и график оплаты"),
            ("start-3", "Проверить подъезд, место для материалов и техники"),
            ("start-4", "Сделать геологию или хотя бы шурф под фундамент"),
            ("start-5", "Решить вопрос временного электричества и воды")
        ]),
        ("Во время работ", [
            ("work-1", "Фиксировать скрытые работы на фото до закрытия"),
            ("work-2", "Сверять этап с проектом и сметой"),
            ("work-3", "Проверять паспорта на бетон и арматуру"),
            ("work-4", "Подписывать акты по каждому этапу"),
            ("work-5", "Вести бюджет: план, факт и остаток")
        ]),
        ("Перед приёмкой", [
            ("finish-1", "Проверить геометрию, уровни и вертикали"),
            ("finish-2", "Протестировать электрику, воду и канализацию"),
            ("finish-3", "Собрать исполнительную и гарантийную документацию")
        ])
    ]
    private var allIDs: [String] { groups.flatMap { $0.items.map(\.0) } }
    var done: Int { allIDs.filter { store.checklistDone.contains($0) }.count }
    var body: some View {
        List {
            Section { VStack(alignment: .leading, spacing: 8) { Text("\(done) из \(allIDs.count) пунктов").font(.title3.bold()); ProgressView(value: Double(done), total: Double(max(1, allIDs.count))).tint(Theme.orange) }.padding(.vertical, 4) }
            ForEach(groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.items, id: \.0) { item in
                        let checked = store.checklistDone.contains(item.0)
                        Button { Haptics.tap(); store.toggleChecklist(item.0) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: checked ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(checked ? Theme.orange : Theme.muted)
                                Text(item.1).foregroundStyle(checked ? Theme.muted : Theme.ink).strikethrough(checked, color: Theme.muted)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(checked ? .isSelected : [])
                    }
                }
            }
            Section { Text("Это личный список контроля. Он не заменяет проект, технадзор и условия договора.").font(.footnote).foregroundStyle(Theme.muted) }
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("Чек-листы").helperScreen("Чек-листы")
    }
}

struct ConstructionDiaryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var entry = ""
    var body: some View {
        List {
            Section("Новая запись") {
                TextEditor(text: $entry).frame(minHeight: 100)
                Button("Сохранить запись") { store.addDiary(entry); entry = ""; Haptics.success() }.disabled(entry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Section("История") {
                if store.diary.isEmpty { Text("Добавьте первую запись: встреча, решение или выполненный этап.").foregroundStyle(Theme.muted) }
                else { ForEach(store.diary) { item in VStack(alignment: .leading, spacing: 6) { Text(item.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Theme.orange); Text(item.text).textSelection(.enabled) } }.onDelete { store.diary.remove(atOffsets: $0) } }
            }
        }
        .scrollContentBackground(.hidden).background(Theme.background).navigationTitle("Журнал решений").helperScreen("Журнал решений")
        .toolbar { if !store.diary.isEmpty { ShareLink(item: diaryText) { Image(systemName: "square.and.arrow.up") } } }
    }
    private var diaryText: String {
        (["Журнал решений · \(store.projectDisplayName)", ""] + store.diary.map { "\($0.date.formatted(date: .numeric, time: .shortened)) — \($0.text)" } + ["", Brand.shareFooter]).joined(separator: "\n")
    }
}
struct AboutAppView: View {
    var body: some View {
        List {
            Section { Text(Brand.name).font(.title2.bold()); Text(Brand.tagline) }
            Section("Ваши данные") {
                Text("Расчёты, сметы, объекты, планировки, фото и журнал хранятся только на вашем iPhone. Удаление приложения удаляет их.")
                Text("Город нужен, чтобы подставлять рыночные цены вашего региона. Определяется по геопозиции только с вашего разрешения или выбирается вручную; точные координаты не сохраняются.")
                Text("Камера используется для AR‑замеров, скана помещения и съёмки. Фото уходит на сервер ИИ только после нажатия кнопки — для одного ответа или одной картинки.")
                Text("Вопросы ИИ‑помощнику и прикреплённые фото передаются через сервер приложения поставщику модели только для ответа.")
                Text("Анонимные технические события (открытие экранов, ошибки) помогают нам исправлять проблемы и не содержат личных данных.")
            }.font(.footnote)
            Section { Text("Версия \(Brand.appVersion)").foregroundStyle(Theme.muted) }
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("О приложении").helperScreen("О приложении")
    }
}

struct ProjectHubView: View {
    @EnvironmentObject private var store: AppStore
    private var complete: Int { store.milestones.filter(\.completed).count }
    private var projectReport: String {
        var lines = ["ОТЧЁТ ПО ОБЪЕКТУ · \(store.projectDisplayName.uppercased())"]
        if !store.passport.address.isEmpty { lines.append("Адрес: \(store.passport.address)") }
        if !store.passport.area.isEmpty { lines.append("Площадь: \(store.passport.area) м²") }
        lines += ["Этап: \(store.passport.stage) · готовность \(Int(store.projectProgress * 100))%", "", "ДОРОЖНАЯ КАРТА"]
        lines += store.milestones.map { "\($0.completed ? "✓" : "○") \($0.title)" }
        let budget = store.budgetItems.filter { $0.included && ($0.planned > 0 || $0.actual > 0) }
        if !budget.isEmpty {
            lines += ["", "БЮДЖЕТ (план / факт)"] + budget.map { "\($0.title): \(CalculationEngine.money($0.planned)) / \(CalculationEngine.money($0.actual))" }
            lines.append("Итого: \(CalculationEngine.money(store.budgetPlanned)) / \(CalculationEngine.money(store.budgetActual))")
        }
        if let last = store.diary.first { lines += ["", "Последнее решение (\(last.date.formatted(date: .numeric, time: .omitted))): \(last.text)"] }
        lines += ["", Brand.shareFooter]
        return lines.joined(separator: "\n")
    }
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 18) {
            SectionTitle(eyebrow: "Личный кабинет объекта", title: store.projectDisplayName)
            Text(store.passport.address.isEmpty ? "Добавьте район или адрес — он попадёт в PDF‑сметы и чертежи." : store.passport.address).font(.subheadline).foregroundStyle(Theme.muted)
            VStack(alignment: .leading, spacing: 14) {
                HStack { VStack(alignment: .leading, spacing: 4) { Text("Готовность проекта").font(.caption).foregroundStyle(Theme.muted); Text("\(complete) из \(store.milestones.count) этапов").font(.title3.bold()) }; Spacer(); Text("\(Int(store.projectProgress * 100))%").font(.title.bold()).monospacedDigit().foregroundStyle(Theme.orange).contentTransition(.numericText()) }
                ProgressView(value: store.projectProgress).tint(Theme.orange)
                Text(store.nextMilestone.map { "Следующий шаг: \($0.title)" } ?? "Все этапы закрыты — поздравляем!").font(.caption.weight(.medium)).foregroundStyle(Theme.ink)
            }.padding(20).panelCard(22)
            if let alert = store.priceAlert { PriceAlertBanner(text: alert) { store.priceAlert = nil } }
            HStack(spacing: 12) {
                ProjectMetric(value: CalculationEngine.money(store.budgetPlanned), title: "План")
                ProjectMetric(value: CalculationEngine.money(store.budgetActual), title: "Потрачено", alert: store.budgetActual > store.budgetPlanned && store.budgetPlanned > 0)
            }
            NavigationLink { ProjectPlanView() } label: { ProjectHubRow(icon: "checklist.checked", title: "План стройки", subtitle: "Этапы, контрольные точки и готовность") }.buttonStyle(PremiumCardPressStyle())
            NavigationLink { ProjectTasksView() } label: {
                ProjectHubRow(icon: "checklist", title: "Задачи команды", subtitle: store.projectTasks.isEmpty ? "Поставьте задачу и укажите ответственного" : "Открыто: \(store.projectTasks.filter { $0.status != .done }.count) · готово: \(store.projectTasks.filter { $0.status == .done }.count)")
            }.buttonStyle(PremiumCardPressStyle())
            NavigationLink { ProjectBudgetTrackerView() } label: { ProjectHubRow(icon: "chart.line.uptrend.xyaxis", title: "Бюджет объекта", subtitle: "План, факт и остаток по каждому этапу") }.buttonStyle(PremiumCardPressStyle())
            NavigationLink { ProjectPhotoDiaryView() } label: { ProjectHubRow(icon: "photo.stack", title: "Фото‑дневник", subtitle: store.projectPhotos.isEmpty ? "Фиксируйте этапы и скрытые работы" : "Фото на объекте: \(store.projectPhotos.count)") }.buttonStyle(PremiumCardPressStyle())
            NavigationLink { ObjectPassportView() } label: { ProjectHubRow(icon: "house.and.flag", title: "Данные объекта", subtitle: "Название, район, площадь и текущий этап") }.buttonStyle(PremiumCardPressStyle())
            NavigationLink { ConstructionDiaryView() } label: { ProjectHubRow(icon: "text.book.closed", title: "Журнал решений", subtitle: store.diary.isEmpty ? "Договорённости, даты, комментарии" : "Записей: \(store.diary.count)") }.buttonStyle(PremiumCardPressStyle())
            NavigationLink { ChecklistView() } label: { ProjectHubRow(icon: "checkmark.shield", title: "Чек‑листы контроля", subtitle: "Перед стартом, во время работ и при приёмке") }.buttonStyle(PremiumCardPressStyle())
            ShareLink(item: projectReport, subject: Text("Отчёт по объекту")) { SecondaryActionLabel(title: "Поделиться отчётом по объекту", icon: "square.and.arrow.up") }
            InfoNote(text: "Проект, бюджет и фото хранятся на этом iPhone. Они отправляются исполнителям только после вашего действия.")
        }.padding(20) }.background(Theme.background).navigationTitle("Мой проект").helperScreen("Мой проект").navigationBarTitleDisplayMode(.inline)
    }
}

struct ProjectMetric: View {
    let value: String
    let title: String
    var alert = false
    var body: some View { VStack(alignment: .leading, spacing: 6) { Text(title.tr.uppercased()).font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(Theme.muted); Text(value).font(.headline.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(alert ? Theme.danger : .white) }.frame(maxWidth: .infinity, alignment: .leading).padding(16).panelCard(18) }
}
struct ProjectHubRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var body: some View { HStack(spacing: 14) { Image(systemName: icon).font(.title3).foregroundStyle(Theme.orange).frame(width: 32); VStack(alignment: .leading, spacing: 4) { Text(title.tr).font(.headline).foregroundStyle(Theme.ink); Text(subtitle.tr).font(.caption).foregroundStyle(Theme.muted) }; Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted) }.padding(18).panelCard(18) }
}

struct ProjectPlanView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        List {
            Section { Text("Отмечайте закрытые этапы. Карточка «Мой проект» покажет общий прогресс и поможет не потерять следующий шаг.").font(.footnote).foregroundStyle(Theme.muted) }
            Section("Дорожная карта") { ForEach($store.milestones) { $milestone in
                Button { Haptics.tap(); withAnimation(.snappy) { milestone.completed.toggle() } } label: { HStack(spacing: 14) { Image(systemName: milestone.completed ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(milestone.completed ? Theme.orange : Theme.muted); VStack(alignment: .leading, spacing: 4) { Text(milestone.title).foregroundStyle(Theme.ink); Text(milestone.subtitle).font(.caption).foregroundStyle(Theme.muted) }; Spacer() } }.buttonStyle(.plain)
            } }
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("План стройки").helperScreen("План стройки")
    }
}

struct ProjectBudgetTrackerView: View {
    @EnvironmentObject private var store: AppStore
    @State private var newTitle = ""
    private var remaining: Double { store.budgetPlanned - store.budgetActual }
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text("План"); Spacer(); Text(CalculationEngine.money(store.budgetPlanned)).monospacedDigit() }
                    HStack { Text("Потрачено"); Spacer(); Text(CalculationEngine.money(store.budgetActual)).monospacedDigit().foregroundStyle(Theme.orange) }
                    if store.budgetPlanned > 0 { ProgressView(value: min(store.budgetActual, store.budgetPlanned), total: store.budgetPlanned).tint(remaining < 0 ? Theme.danger : Theme.orange) }
                    HStack {
                        Text(remaining < 0 ? "Перерасход" : "Остаток").fontWeight(.semibold)
                        Spacer()
                        Text(CalculationEngine.money(abs(remaining))).fontWeight(.bold).monospacedDigit().foregroundStyle(remaining < 0 ? Theme.danger : Theme.ink)
                    }
                }.font(.subheadline)
            }
            Section("Этапы") {
                ForEach(store.budgetItems.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(store.budgetItems[index].title, isOn: $store.budgetItems[index].included)
                        if store.budgetItems[index].included {
                            HStack { budgetField("План, ₽", index: index, keyPath: \.planned); budgetField("Факт, ₽", index: index, keyPath: \.actual) }
                            if store.budgetItems[index].actual > store.budgetItems[index].planned && store.budgetItems[index].planned > 0 {
                                Text("Перерасход \(CalculationEngine.money(store.budgetItems[index].actual - store.budgetItems[index].planned))").font(.caption).foregroundStyle(Theme.danger)
                            }
                        }
                    }
                }
                .onDelete { store.budgetItems.remove(atOffsets: $0) }
                HStack {
                    TextField("Новая статья, например «Забор»", text: $newTitle)
                    Button { addItem() } label: { Image(systemName: "plus.circle.fill").accessibilityLabel("Добавить").font(.title3) }.disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Section { Text("Совет: в полной смете нажмите «В бюджет проекта» — плановые суммы заполнятся автоматически. Фактические суммы не передаются на сервер.").font(.footnote).foregroundStyle(Theme.muted) }
        }
        .scrollContentBackground(.hidden).background(Theme.background).navigationTitle("Бюджет").helperScreen("Бюджет")
        .scrollDismissesKeyboard(.interactively)
    }
    private func addItem() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        store.budgetItems.append(ProjectBudgetItem(id: "budget-\(UUID().uuidString)", title: title))
        newTitle = ""
        Haptics.success()
    }
    /// Whole rubles only: avoids the broken decimal-comma editing of the previous version.
    private func budgetField(_ title: String, index: Int, keyPath: WritableKeyPath<ProjectBudgetItem, Double>) -> some View {
        TextField(title, text: Binding(
            get: {
                guard store.budgetItems.indices.contains(index) else { return "" }
                let value = store.budgetItems[index][keyPath: keyPath]
                return value == 0 ? "" : CalculationEngine.format(value.rounded())
            },
            set: { text in
                guard store.budgetItems.indices.contains(index) else { return }
                store.budgetItems[index][keyPath: keyPath] = Double(text.filter(\.isNumber)) ?? 0
            }))
            .keyboardType(.numberPad)
            .padding(10).background(Theme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct ProjectPhotoDiaryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var item: PhotosPickerItem?
    @State private var caption = ""
    @State private var error: String?
    @State private var showCamera = false
    @State private var cameraImage: UIImage?
    @State private var pendingDelete: ProjectPhoto?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(eyebrow: "Объект в динамике", title: "Фото‑дневник")
                Text("Добавляйте фото выполненных этапов, скрытых работ и согласованных решений. Они останутся на вашем iPhone.").font(.subheadline).foregroundStyle(Theme.muted)
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Подпись к фото, например: армирование плиты", text: $caption).padding(14).panelCard(14)
                    HStack(spacing: 10) {
                        PhotosPicker(selection: $item, matching: .images) { Label("Из галереи", systemImage: "photo.badge.plus").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(15).foregroundStyle(Theme.onAccent).background(Theme.orange, in: RoundedRectangle(cornerRadius: 15, style: .continuous)) }.buttonStyle(.plain)
                        Button { showCamera = true } label: { Label("Снять", systemImage: "camera.fill").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(15).foregroundStyle(Theme.ink).panelCard(15, fill: Theme.panelRaised) }
                            .buttonStyle(.plain)
                            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                    }
                }
                if let error { Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(Theme.danger) }
                if store.projectPhotos.isEmpty { ContentUnavailableView("Пока нет фото", systemImage: "photo.on.rectangle", description: Text("Сохраните первый этап, чтобы вести историю объекта.")) }
                else {
                    LazyVStack(spacing: 16) {
                        ForEach(store.projectPhotos) { photo in
                            VStack(alignment: .leading, spacing: 10) {
                                LocalThumbnail(url: store.projectPhotoURL(photo), maxPixel: 1000)
                                    .frame(height: 220).frame(maxWidth: .infinity).clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) { Text(photo.caption.isEmpty ? "Этап строительства" : photo.caption).font(.headline); Text(photo.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Theme.muted) }
                                    Spacer()
                                    if let url = store.projectPhotoURL(photo) { ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }.padding(.trailing, 6) }
                                    Button(role: .destructive) { pendingDelete = photo } label: { Image(systemName: "trash") }.accessibilityLabel("Удалить фото")
                                }
                            }.padding(12).panelCard(20)
                        }
                    }
                }
            }.padding(20)
        }.background(Theme.background).navigationTitle("Фото‑дневник").helperScreen("Фото‑дневник").navigationBarTitleDisplayMode(.inline)
            .onChange(of: item) { _, selected in Task { await importPhoto(selected) } }
            .sheet(isPresented: $showCamera) { CameraCaptureView(image: $cameraImage).ignoresSafeArea() }
            .onChange(of: cameraImage) { _, image in
                guard let image else { return }
                save(image); cameraImage = nil
            }
            .confirmationDialog("Удалить фото из дневника?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
                Button("Удалить", role: .destructive) {
                    if let photo = pendingDelete, let index = store.projectPhotos.firstIndex(where: { $0.id == photo.id }) { store.deleteProjectPhotos(at: IndexSet(integer: index)) }
                    pendingDelete = nil
                }
            }
    }
    private func save(_ image: UIImage) {
        do { try store.addProjectPhoto(image, caption: caption); caption = ""; error = nil; Haptics.success() }
        catch { self.error = error.localizedDescription; HelperCenter.shared.failed(error) }
    }
    private func importPhoto(_ selected: PhotosPickerItem?) async {
        guard let selected else { return }
        do {
            guard let data = try await selected.loadTransferable(type: Data.self), let image = UIImage(data: data) else { throw ProjectPhotoError.encoding }
            save(image); item = nil
        } catch { self.error = error.localizedDescription; HelperCenter.shared.failed(error) }
    }
}

// MARK: - Live examples: animated scenes that play by themselves, like a short video of every function

enum LiveExample: String, CaseIterable, Identifiable, Hashable {
    case house, documents, design, ar, count, calculator
    var id: String { rawValue }
    var scene: FeatureSceneKind {
        switch self {
        case .documents: .documents
        case .design: .design
        case .ar: .ar
        case .count: .count
        case .calculator: .calculator
        case .house: .house
        }
    }
    var title: String {
        switch self {
        case .documents: "Смета по документам"
        case .design: "Дизайн комнаты"
        case .ar: "AR‑рулетка"
        case .count: "Сколько в пачке"
        case .calculator: "Калькуляторы"
        case .house: "3D‑обмер дома"
        }
    }
    var text: String {
        switch self {
        case .documents: "Загрузите АР, КР или Excel — ИИ прочитает листы и посчитает смету с ценами."
        case .design: "Было и стало: та же комната в новом стиле, с вашими материалами."
        case .ar: "Обведите комнату камерой — получите длины и площадь."
        case .count: "Сфотографируйте торцы — ИИ посчитает арматуру и трубы."
        case .calculator: "Бетон, плитка, кладка — объём и стоимость за секунды."
        case .house: "Обойдите дом с iPhone — размеры стен и крыши за пару минут."
        }
    }
}

struct LiveExamplesCard: View {
    var paused = false
    let open: (LiveExample) -> Void
    @State private var index = 0
    @State private var userTouched = Date.distantPast
    private let items = LiveExample.allCases

    var body: some View {
        let item = items[index]
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                FeatureScene(kind: item.scene, paused: paused, fps: 20)
                    .id(item)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 1.03)), removal: .opacity))
                HStack(spacing: 6) {
                    Circle().fill(Color.red).frame(width: 6, height: 6)
                    Text("LIVE").font(.system(size: 10, weight: .heavy)).tracking(1.2)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.black.opacity(0.35), in: Capsule())
                .padding(14)
            }
            .frame(height: 236)
            .clipped()

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.system(.headline, design: .serif, weight: .bold)).foregroundStyle(Theme.ink)
                        Text(item.text).font(.caption).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    .id(item).transition(.opacity)
                    Spacer(minLength: 8)
                    Button { Haptics.tap(); open(item) } label: {
                        HStack(spacing: 5) { Text("Попробовать"); Image(systemName: "arrow.right") }
                            .font(.caption.weight(.bold)).foregroundStyle(Theme.onAccent)
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(Theme.accentGradient, in: Capsule())
                    }
                    .buttonStyle(PremiumPressStyle())
                }
                HStack(spacing: 6) {
                    ForEach(items.indices, id: \.self) { i in
                        Capsule().fill(i == index ? AnyShapeStyle(Lux.goldGradient) : AnyShapeStyle(Theme.muted.opacity(0.25)))
                            .frame(width: i == index ? 22 : 6, height: 6)
                            .onTapGesture { select(i) }
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.goldHairline, lineWidth: 0.8))
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.panel)
                .shadow(color: Theme.ink.opacity(0.12), radius: 16, y: 8)
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 20).onEnded { value in
            if value.translation.width < -40 { select((index + 1) % items.count) }
            if value.translation.width > 40 { select((index - 1 + items.count) % items.count) }
        })
        .task(id: paused) {
            guard !paused else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5.5))
                if Task.isCancelled { return }
                if Date().timeIntervalSince(userTouched) < 8 { continue }
                withAnimation(.easeInOut(duration: 0.6)) { index = (index + 1) % items.count }
            }
        }
    }

    private func select(_ i: Int) {
        userTouched = Date()
        Haptics.tap()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { index = i }
    }
}

/// Главная: крупная карточка «3D‑обмер дома» с живой анимацией и описанием под ней.
struct HouseScanHomeCard: View {
    var paused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                FeatureScene(kind: .house, paused: paused, fps: 15).frame(height: 190)
                Text("НОВОЕ").font(.caption2.weight(.heavy)).tracking(1.2).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 9).padding(.vertical, 4).background(Lux.goldGradient, in: Capsule())
                    .padding(14)
            }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous))
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("3D‑обмер дома").font(.system(.title3, design: .serif, weight: .bold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "arrow.right").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.orange)
                }
                Text("Обойдите дом с iPhone — получите 3D‑модель с точными размерами стен и крыши, площади кровли и фасадов для сметы и проверку по границам участка из Росреестра.")
                    .font(.footnote).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    Label("5–10 мин обход", systemImage: "figure.walk")
                    Label("до сантиметров", systemImage: "scope")
                    Label("кадастр", systemImage: "map")
                }
                .font(.caption2.weight(.semibold)).foregroundStyle(Theme.gold)
            }
            .padding(16)
        }
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.goldHairline, lineWidth: 1))
        .shadow(color: Theme.ink.opacity(0.08), radius: 14, y: 6)
    }
}
