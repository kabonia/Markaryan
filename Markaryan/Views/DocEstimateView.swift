import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Hub: new estimate, jobs in progress, saved estimates

struct DocEstimateHubView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var center = DocEstimateCenter.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle(eyebrow: "Сметный отдел ИИ", title: "Смета по документам")
                Text("АР, КР, ТЗ, готовая смета в Excel или просто перечень работ — объёмы снимут два независимых ИИ‑агента, нормы расхода посчитает нормировщик, цены — по рынку вашего города, а аудитор проверит пропуски и ошибки.")
                    .font(.subheadline).foregroundStyle(Theme.muted)
                NavigationLink { DocEstimateNewView() } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "doc.text.magnifyingglass").font(.title2).foregroundStyle(Theme.onAccent)
                            .frame(width: 52, height: 52).background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Новая смета").font(.headline).foregroundStyle(.white)
                            Text("Загрузите PDF, Excel, фото листов или текст").font(.caption).foregroundStyle(.white.opacity(0.8))
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(18)
                    .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.goldHairline, lineWidth: 0.8))
                }
                .buttonStyle(PremiumCardPressStyle())

                if !center.running.isEmpty {
                    Text("СЧИТАЕТСЯ").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
                    ForEach(center.running) { job in DocEstimateProgressCard(job: job) }
                }
                if !center.saved.isEmpty {
                    Text("МОИ СМЕТЫ").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
                    ForEach(center.saved) { item in
                        NavigationLink { DocEstimateResultLoader(id: item.id) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "doc.richtext").foregroundStyle(Theme.orange).frame(width: 40, height: 40).background(Theme.accentTint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                                    Text("\(item.city) · \(item.date.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                Text(CalculationEngine.money(item.total)).font(.subheadline.bold()).monospacedDigit().foregroundStyle(Theme.ink)
                            }
                            .padding(14).panelCard(18)
                        }
                        .buttonStyle(PremiumCardPressStyle())
                        .contextMenu { Button(role: .destructive) { center.delete(item.id) } label: { Label("Удалить", systemImage: "trash") } }
                    }
                }
                InfoNote(text: "Точность зависит от документов: чем полнее АР и КР (планы с размерами, разрезы, спецификации, ведомости отделки и проёмов), тем точнее объёмы. Каждая цифра в смете — с формулой или ссылкой на лист.")
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Смета по документам").helperScreen("Смета по документам (АР, КР, ТЗ)", details: DocEstimateCenter.shared.running
            .map { $0.error == nil ? "«\($0.title)»: \($0.stageTitle), \(Int($0.progress * 100))%" : "«\($0.title)»: ошибка — \($0.error ?? "неизвестно")" }
            .joined(separator: "; ")).featureIntro(.docEstimate)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { center.resumeAll() }
    }
}

struct DocEstimateProgressCard: View {
    @ObservedObject private var center = DocEstimateCenter.shared
    let job: DocEstimateCenter.Running
    private let stages: [(String, String)] = [("read", "Чтение документов двумя агентами"), ("merge", "Сводная ведомость объёмов"), ("norms", "Нормы расхода и техника"), ("prices", "Рыночные цены"), ("audit", "Проверка аудитором"), ("additions", "Добавленные проверкой работы"), ("verify", "Ценовой аудитор: каждая цена")]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(job.title).font(.headline).foregroundStyle(Theme.ink)
                Spacer()
                if job.error == nil { ProgressView() }
            }
            if let error = job.error {
                Label(error, systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(Theme.danger)
                Button("Убрать") { center.delete(job.id) }.font(.subheadline.weight(.semibold))
            } else {
                let current = stages.firstIndex { $0.0 == job.stage } ?? -1
                ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                    if stage.0 != "additions" || job.stage == "additions" {
                        HStack(spacing: 10) {
                            Image(systemName: index < current ? "checkmark.circle.fill" : index == current ? "circle.dotted" : "circle")
                                .foregroundStyle(index <= current ? Theme.orange : Theme.muted.opacity(0.5))
                            Text(index == current ? job.stageTitle : stage.1).font(.subheadline).foregroundStyle(index <= current ? Theme.ink : Theme.muted)
                            Spacer()
                            if index == current, job.progress > 0, job.progress < 1 { Text("\(Int(job.progress * 100))%").font(.caption.monospacedDigit()).foregroundStyle(Theme.muted) }
                        }
                    }
                }
                Text("Обычно 5–15 минут. Можно свернуть приложение — пришлём уведомление.").font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .padding(16).panelCard(20)
    }
}

// MARK: - New estimate

struct DocEstimateNewView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    @State private var docs: [DocAttachment] = []
    @State private var vat = false
    @State private var delivery = 4.0
    /// Доставка процентом от материалов вместо расчёта рейсов (когда доставка уже заложена в ценах или считается иначе).
    @State private var deliveryPercent = false
    @State private var contingency = 5.0
    @State private var importing = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var busy = false
    @State private var error: String?

    private var pages: Int { docs.reduce(0) { $0 + $1.pages.count } }
    private var canStart: Bool { !busy && (!docs.isEmpty || text.trimmingCharacters(in: .whitespacesAndNewlines).count > 10) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                field("Название объекта") { TextField("Например: Жилой дом 10×12, Сочи", text: $title).foregroundStyle(Theme.ink) }
                HStack {
                    Label("Цены: \(store.projectCity)", systemImage: "location.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    NavigationLink("Изменить") { RegionPickerView() }.font(.subheadline.weight(.semibold))
                }
                .padding(14).panelCard(16)

                Text("ДОКУМЕНТЫ").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
                ForEach($docs) { $doc in
                    HStack(spacing: 12) {
                        Group {
                            if let preview = doc.preview { Image(uiImage: preview).resizable().scaledToFill() }
                            else { Image(systemName: "doc.text").foregroundStyle(Theme.orange) }
                        }
                        .frame(width: 44, height: 44).background(Theme.accentTint).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(doc.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                            Text(doc.summary).font(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 6)
                        Menu {
                            Picker("Тип", selection: $doc.kind) { ForEach(DocKind.allCases) { Text($0.title).tag($0) } }
                        } label: {
                            Text(doc.kind.short).font(.caption.weight(.bold)).padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Theme.accentTint, in: Capsule()).foregroundStyle(Theme.orange)
                        }
                        Button { docs.removeAll { $0.id == doc.id } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }
                    }
                    .padding(12).panelCard(16)
                }
                HStack(spacing: 10) {
                    Button { importing = true } label: { SecondaryActionLabel(title: "PDF / Excel", icon: "doc.badge.plus") }
                    PhotosPicker(selection: $photos, maxSelectionCount: 20, matching: .images) { SecondaryActionLabel(title: "Фото листов", icon: "photo.on.rectangle") }
                }
                .buttonStyle(PremiumPressStyle())
                if pages > 0 { Text("Листов: \(pages) из \(DocAttachment.maxPages). Укажите тип каждого документа — АР, КР, ТЗ или смета: агенты читают их по‑разному.").font(.caption).foregroundStyle(Theme.muted) }

                Text("ПЕРЕЧЕНЬ РАБОТ ИЛИ ТЗ").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
                TextEditor(text: $text)
                    .frame(minHeight: 140).scrollContentBackground(.hidden).foregroundStyle(Theme.ink)
                    .padding(10).panelCard(16)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("Например: дом 10×12 из газобетона D500 300 мм, лента 400×1200 B25, перекрытие монолит 200 мм, кровля металлочерепица… Или просто список наименований с объёмами.")
                                .font(.subheadline).foregroundStyle(Theme.muted.opacity(0.7)).padding(16).allowsHitTesting(false)
                        }
                    }

                Text("НАЧИСЛЕНИЯ").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
                VStack(spacing: 12) {
                    Toggle("НДС 22 %", isOn: $vat).foregroundStyle(Theme.ink)
                    Toggle("Доставка процентом вместо рейсов", isOn: $deliveryPercent.animation()).foregroundStyle(Theme.ink)
                    if deliveryPercent {
                        Stepper("Доставка материалов: \(Int(delivery)) %", value: $delivery, in: 0...15).foregroundStyle(Theme.ink)
                    } else {
                        Text("Техника — по реальной аренде (смены, минимальный заказ, подача), доставка — рейсами по закупке. Строки доставки из ваших документов не задваиваются.")
                            .font(.caption).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Stepper("Непредвиденные: \(Int(contingency)) %", value: $contingency, in: 0...20).foregroundStyle(Theme.ink)
                }
                .font(.subheadline).padding(14).panelCard(16)

                if let error { Label(error, systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(Theme.danger) }
                if busy {
                    HStack(spacing: 10) { ProgressView(); Text("Готовим и отправляем документы…").font(.subheadline).foregroundStyle(Theme.muted) }
                        .frame(maxWidth: .infinity).padding(16)
                } else {
                    PrimaryButton(title: "Рассчитать смету", icon: "sparkles") { Task { await start() } }
                        .disabled(!canStart).opacity(canStart ? 1 : 0.5)
                }
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Новая смета").helperScreen("Новая смета по документам", details: "Документов: \(docs.count), листов: \(pages)")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image, .plainText, .commaSeparatedText, .rtf, .spreadsheet, UTType("org.openxmlformats.spreadsheetml.sheet") ?? .spreadsheet, UTType("com.microsoft.excel.xls") ?? .spreadsheet], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { Task { await add(urls) } }
        }
        .onChange(of: photos) { _, items in Task { await addPhotos(items) } }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.subheadline).foregroundStyle(Theme.muted)
            content().padding(14).panelCard(16)
        }
    }

    private func add(_ urls: [URL]) async {
        busy = true; defer { busy = false }
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let type = UTType(filenameExtension: url.pathExtension.lowercased())
            let name = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension.lowercased()
            if ext == "xlsx" || ext == "xlsm" {
                if let data = try? Data(contentsOf: url), data.count < 25_000_000 {
                    docs.append(DocAttachment(name: name, kind: DocKind.guess(name) == .other ? .smeta : DocKind.guess(name), xlsx: data))
                } else { error = "Не удалось открыть «\(name)» (файл больше 25 МБ?)." }
            } else if ext == "xls" {
                error = "«\(name)» — старый формат .xls. Сохраните его в Excel как .xlsx и загрузите снова."
            } else if type?.conforms(to: .pdf) == true {
                if let doc = DocAttachment.fromPDF(url, pageBudget: DocAttachment.maxPages - pages) { docs.append(doc) }
                else { error = "Не удалось открыть «\(name)» или лимит \(DocAttachment.maxPages) листов исчерпан." }
            } else if type?.conforms(to: .image) == true, let data = try? Data(contentsOf: url), let image = UIImage(data: data), pages < DocAttachment.maxPages {
                if let doc = DocAttachment.fromImage(image, name: name, kind: DocKind.guess(name)) { docs.append(doc) }
            } else if let data = try? Data(contentsOf: url) {
                let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1251) ?? ""
                if !content.isEmpty { docs.append(DocAttachment(name: name, kind: DocKind.guess(name), text: String(content.prefix(120_000)))) }
            }
        }
    }

    private func addPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        busy = true; defer { busy = false; photos = [] }
        for (index, item) in items.enumerated() where pages < DocAttachment.maxPages {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data),
               let doc = DocAttachment.fromImage(image, name: "Фото листа \(docs.count + 1)", kind: index == 0 ? .ar : (docs.last?.kind ?? .ar)) {
                docs.append(doc)
            }
        }
    }

    private func start() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            _ = try await DocEstimateCenter.shared.start(title: title.trimmingCharacters(in: .whitespaces), city: store.projectCity, text: text, docs: docs,
                                                          options: .init(vat: vat, vatPct: 22, deliveryPct: deliveryPercent ? delivery : 0, contingencyPct: contingency, deliveryMode: deliveryPercent ? "percent" : "lines"))
            Haptics.success()
            dismiss()
        } catch {
            self.error = error.localizedDescription
            HelperCenter.shared.failed(error, action: "Отправить документы на смету")
        }
    }
}

// MARK: - Result

struct DocEstimateResultLoader: View {
    let id: String
    var body: some View {
        if let result = DocEstimateCenter.shared.result(id) { DocEstimateResultView(result: result) }
        else { ContentUnavailableView("Смета не найдена", systemImage: "doc.questionmark") }
    }
}

struct DocEstimateResultView: View {
    let result: DocEstimateResult
    @State private var tab = 0
    @State private var shareFile: SharedFile?
    @State private var proposalOpen = false
    @State private var expanded: Set<String> = []

    private var t: DocTotals { result.totals.typical }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                if let audit = result.audit, !audit.verdict.isEmpty || !audit.issues.isEmpty { auditCard(audit) }
                Picker("", selection: $tab) {
                    Text("Смета").tag(0); Text("Закупка").tag(1); Text("Основания").tag(2)
                }
                .pickerStyle(.segmented)
                switch tab {
                case 0: sectionsList
                case 1: purchaseList
                default: basisList
                }
                HStack(spacing: 10) {
                    Button { proposalOpen = true } label: { SecondaryActionLabel(title: "КП в PDF", icon: "doc.richtext") }
                    Button { if let url = DocEstimateExport.csv(result) { shareFile = SharedFile(url: url) } } label: { SecondaryActionLabel(title: "Excel", icon: "tablecells") }
                }
                .buttonStyle(PremiumPressStyle())
                PartnerOfferSection(category: "house", summary: "Здравствуйте! Смета «\(result.title)» по рыночным ценам: \(CalculationEngine.money(t.total)). Подскажите вашу цену?")
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle(result.title).helperScreen("Смета по документам: \(result.title)", details: "Итого \(CalculationEngine.money(t.total)); разделы: " + result.sections.map { "\($0.title) \(CalculationEngine.money($0.total))" }.joined(separator: "; "))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shareFile) { file in ActivityShareSheet(items: [file.url]) }
        .sheet(isPresented: $proposalOpen) { ProposalExportSheet(result: result) }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ИТОГО ПО СМЕТЕ · \(result.city.uppercased())").font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(.white.opacity(0.8))
            Text(CalculationEngine.money(t.total)).font(.system(size: 36, weight: .bold, design: .serif)).monospacedDigit().foregroundStyle(.white).minimumScaleFactor(0.6).lineLimit(1)
            Text("Рынок: \(CalculationEngine.money(result.totals.low.total)) – \(CalculationEngine.money(result.totals.high.total))").font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.85))
            if let area = result.object?.area, area > 0 { Text("≈ \(CalculationEngine.money(t.total / area)) за м² · \(CalculationEngine.format(area)) м²").font(.caption).foregroundStyle(.white.opacity(0.8)) }
            Divider().overlay(.white.opacity(0.25)).padding(.vertical, 4)
            VStack(spacing: 5) {
                line("Работы", t.works); line("Материалы", t.materials); line("Техника", t.machines)
                line("Доставка", t.delivery); line("Непредвиденные", t.contingency)
                if t.vat > 0 { line("НДС 22 %", t.vat) }
            }
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.goldHairline, lineWidth: 0.8))
    }

    private func line(_ title: String, _ value: Double) -> some View {
        HStack { Text(title); Spacer(); Text(CalculationEngine.money(value)).monospacedDigit() }.font(.caption).foregroundStyle(.white.opacity(0.9))
    }

    private func auditCard(_ audit: DocEstimateResult.Audit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Проверка аудитором", systemImage: "checkmark.shield.fill").font(.subheadline.weight(.bold)).foregroundStyle(Theme.orange)
            if !audit.verdict.isEmpty { Text(audit.verdict).font(.subheadline).foregroundStyle(Theme.ink) }
            ForEach(audit.issues, id: \.self) { issue in
                Label(issue.text, systemImage: issue.severity == "critical" ? "exclamationmark.octagon.fill" : issue.severity == "warning" ? "exclamationmark.triangle.fill" : "info.circle")
                    .font(.caption).foregroundStyle(issue.severity == "critical" ? Theme.danger : Theme.ink)
            }
            if audit.added > 0 { Text("Добавлено проверкой работ: \(audit.added) — отмечены в смете.").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted) }
            if let checked = audit.pricesChecked, checked > 0 { Text("Ценовой аудитор проверил \(checked) цен, исправлено: \(audit.pricesFixed ?? 0).").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted) }
            if let unpriced = result.unpriced, unpriced > 0 { Text("Без рыночной цены: \(unpriced) позиций — уточните у поставщиков.").font(.caption.weight(.semibold)).foregroundStyle(Theme.danger) }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).panelCard(20)
    }

    private var sectionsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(result.sections) { section in
                VStack(alignment: .leading, spacing: 10) {
                    Button { withAnimation(.snappy) { if expanded.contains(section.id) { expanded.remove(section.id) } else { expanded.insert(section.id) } } } label: {
                        HStack {
                            Text(section.title).font(.headline).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
                            Spacer()
                            Text(CalculationEngine.money(section.total)).font(.subheadline.bold()).monospacedDigit().foregroundStyle(Theme.ink)
                            Image(systemName: expanded.contains(section.id) ? "chevron.up" : "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
                        }
                    }
                    .buttonStyle(.plain)
                    Text("Работы \(CalculationEngine.money(section.works.typical)) · материалы \(CalculationEngine.money(section.materials.typical))\(section.machines.typical > 0 ? " · техника \(CalculationEngine.money(section.machines.typical))" : "")")
                        .font(.caption).foregroundStyle(Theme.muted)
                    if expanded.contains(section.id) {
                        ForEach(section.items) { work in DocWorkRow(work: work) }
                    }
                }
                .padding(16).panelCard(20)
            }
        }
    }

    private var purchaseList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Все материалы объекта, сложенные по работам, с нормами и отходами; техника и рейсы доставки.").font(.caption).foregroundStyle(Theme.muted)
            ForEach(result.materials + result.machines) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        Text(item.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                        Spacer(minLength: 8)
                        Text(CalculationEngine.money(item.quantity * (item.price?.typical ?? 0))).font(.subheadline.bold()).monospacedDigit().foregroundStyle(Theme.ink)
                    }
                    Text("\(CalculationEngine.format(item.quantity)) \(item.unit) × \(item.price?.hasPrice == true ? CalculationEngine.money(item.price?.typical ?? 0) : "нет цены")\(item.price?.estimated == true ? " · экспертная цена" : "")").font(.caption).foregroundStyle(Theme.muted)
                    DocSourcesRow(price: item.price)
                }
                .padding(14).panelCard(18)
            }
        }
    }

    private var basisList: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let object = result.object, let summary = object.summary, !summary.isEmpty { InfoNote(text: summary) }
            if let sources = result.sources, !sources.isEmpty {
                card("Документы", sources.map { "\($0.name) — \($0.kind.uppercased()), \($0.pages) л." })
            }
            if let d = result.discrepancies, !d.isEmpty { card("Расхождения двух чтений и решения", d) }
            if let a = result.assumptions, !a.isEmpty { card("Допущения", a) }
            card("Как считалось", [
                "Объёмы сняты с документов двумя независимыми агентами на разных моделях ИИ и сведены главным сметчиком.",
                "Материалы — по нормам расхода (ГЭСН и практика) с отходами; одинаковые материалы сложены в закупку.",
                "Цены — рыночные предложения магазинов, маркетплейсов и подрядчиков в г. \(result.city); работа считается отдельно от материалов.",
                result.options?.deliveryAsPercent == false
                    ? "Техника — по реальной аренде: смены и минимальный заказ, подача и перебазировка; мелкий инструмент — в работе бригады. Доставка — рейсами по закупке. Цены техники и рейсов — медиана нескольких предложений (Авито, частники, компании)."
                    : "Доставка \(CalculationEngine.format(result.options?.deliveryPct ?? 4)) % от материалов.",
                "Непредвиденные \(CalculationEngine.format(result.options?.contingencyPct ?? 5)) %\(result.options?.vat == true ? ", НДС 22 %" : "").",
            ])
        }
    }

    private func card(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
            ForEach(lines, id: \.self) { Text("• " + $0).font(.caption).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).panelCard(18)
    }
}

struct DocWorkRow: View {
    let work: DocWork
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(.snappy) { open.toggle() } } label: {
                HStack(alignment: .top, spacing: 8) {
                    Text(work.id).font(.caption2.weight(.bold)).foregroundStyle(Theme.orange).frame(width: 34, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(work.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
                        Text("\(CalculationEngine.format(work.quantity)) \(work.unit) × \(work.price?.hasPrice == true ? CalculationEngine.money(work.price?.typical ?? 0) : "нет цены") работа")
                            .font(.caption).foregroundStyle(Theme.muted)
                        HStack(spacing: 6) {
                            if work.added == true { tag("добавлено проверкой", Theme.danger) }
                            if work.confidence == "low" { tag("объём — оценка", Theme.muted) }
                            if work.price?.estimated == true { tag("экспертная цена", Theme.orange) }
                            if work.price?.rechecked == true { tag("цена перепроверена", Theme.success) }
                        }
                    }
                    Spacer(minLength: 6)
                    Text(CalculationEngine.money(work.sum ?? 0)).font(.subheadline.bold()).monospacedDigit().foregroundStyle(Theme.ink)
                }
            }
            .buttonStyle(.plain)
            if open {
                if let basis = work.basis, !basis.isEmpty { Label(basis, systemImage: "ruler").font(.caption).foregroundStyle(Theme.ink) }
                if let note = work.price?.note, !note.isEmpty { Label(note, systemImage: "checkmark.shield").font(.caption).foregroundStyle(Theme.muted) }
                DocSourcesRow(price: work.price)
                ForEach(work.materials + work.machines) { m in
                    HStack(alignment: .top) {
                        Text("• \(m.name)").font(.caption).foregroundStyle(Theme.ink)
                        Spacer(minLength: 6)
                        Text("\(CalculationEngine.format(m.quantity)) \(m.unit) · \(CalculationEngine.money(m.sum ?? 0))").font(.caption.monospacedDigit()).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.stroke).frame(height: 0.5) }
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption2.weight(.semibold)).padding(.horizontal, 7).padding(.vertical, 3).background(color.opacity(0.12), in: Capsule()).foregroundStyle(color)
    }
}

struct DocSourcesRow: View {
    let price: DocPrice?
    var body: some View {
        if let sources = price?.sources, !sources.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if let example = price?.example, !example.isEmpty { Text(example).font(.caption2).foregroundStyle(Theme.muted).lineLimit(1) }
                    ForEach(sources, id: \.url) { source in
                        if let url = URL(string: source.url) {
                            Link(destination: url) {
                                Label(source.title.isEmpty ? (url.host ?? "источник") : source.title, systemImage: "link").font(.caption2.weight(.semibold)).lineLimit(1)
                                    .padding(.horizontal, 9).padding(.vertical, 5).background(Theme.accentTint, in: Capsule()).foregroundStyle(Theme.orange)
                            }
                        }
                    }
                }
            }
        }
    }
}
