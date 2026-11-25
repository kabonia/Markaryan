import SwiftUI

// MARK: - «Смета дома»: a few choices → a full estimate from the geometry and the city's weekly real prices

struct HouseParams: Codable, Equatable {
    var length = 12.0
    var width = 10.0
    var floors = 1
    var floorHeight = 2.8
    var foundation = "strip"
    var walls = "gasblock"
    var slabs = "monolith"
    var roof = "gable"
    var roofCover = "metaltile"
    var pitch = 30.0
    var facade = "plaster"
    var finish = "rough"
    var electric = true
    var water = true
    var sewer = "septic"
    var heating = "gas"
    var well = false
    /// 0 — counted from the area.
    var bathrooms = 0
    var vat = false
    var contingency = 5.0

    var area: Double { length * width * Double(floors) }
    var heavyWalls: Bool { ["gasblock", "brick", "ceramic"].contains(walls) }

    /// What goes to the server (and, in words, to the AI estimator for a check by documents).
    func payload(city: String, region: UserRegion?) -> [String: Any] {
        var body: [String: Any] = [
            "length": length, "width": width, "floors": floors, "floorHeight": floorHeight,
            "foundation": foundation, "walls": walls, "slabs": slabs, "roof": roof, "roofCover": roofCover, "pitch": pitch,
            "facade": facade, "finish": finish, "city": city,
            "engineering": ["electric": electric, "water": water, "sewer": sewer, "heating": heating, "well": well],
            "options": ["vat": vat, "contingencyPct": contingency],
        ]
        if bathrooms > 0 { body["bathrooms"] = bathrooms }
        if let lat = region?.latitude, let lon = region?.longitude { body["lat"] = lat; body["lon"] = lon }
        return body
    }

    var description: String {
        func t(_ list: [(String, String)], _ v: String) -> String { list.first { $0.0 == v }?.1 ?? v }
        var parts = [
            "Жилой дом \(CalculationEngine.format(length))×\(CalculationEngine.format(width)) м, \(floors) эт., высота этажа \(CalculationEngine.format(floorHeight)) м, площадь \(CalculationEngine.format(area)) м².",
            "Фундамент: \(t(HouseOptions.foundation, foundation)). Стены: \(t(HouseOptions.walls, walls)).",
            roof == "flat" ? "Кровля плоская." : "Кровля \(t(HouseOptions.roof, roof).lowercased()), \(t(HouseOptions.roofCover, roofCover).lowercased()), уклон \(Int(pitch))°.",
            "Фасад: \(t(HouseOptions.facade, facade).lowercased()). Отделка: \(t(HouseOptions.finish, finish).lowercased()).",
        ]
        if floors > 1 { parts.append("Межэтажные перекрытия: \(t(HouseOptions.slabs, slabs).lowercased()).") }
        var eng: [String] = []
        if electric { eng.append("электрика") }
        if water { eng.append("водопровод") }
        if sewer != "none" { eng.append(sewer == "septic" ? "септик" : "канализация в центральную сеть") }
        if heating != "none" { eng.append(heating == "gas" ? "отопление газовым котлом" : "отопление электрокотлом") }
        if well { eng.append("скважина") }
        if !eng.isEmpty { parts.append("Инженерия: \(eng.joined(separator: ", ")).") }
        return parts.joined(separator: " ")
    }
}

enum HouseOptions {
    static let foundation = [("strip", "Лента"), ("slab", "Плита"), ("piles", "Сваи")]
    static let walls = [("gasblock", "Газобетон"), ("brick", "Кирпич"), ("ceramic", "Керамоблок"), ("frame", "Каркас"), ("timber", "Брус")]
    static let slabs = [("monolith", "Монолит"), ("wood", "Дерево")]
    static let roof = [("gable", "Двускатная"), ("hip", "Вальмовая"), ("flat", "Плоская")]
    static let roofCover = [("metaltile", "Металлочерепица"), ("softroof", "Гибкая черепица"), ("profroof", "Профнастил"), ("seamroof", "Фальц")]
    static let facade = [("plaster", "Штукатурка"), ("facing", "Кирпич"), ("siding", "Сайдинг"), ("none", "Без отделки")]
    static let finish = [("shell", "Коробка"), ("rough", "Черновая"), ("turnkey", "Под ключ")]
    static let sewer = [("septic", "Септик"), ("central", "Центральная"), ("none", "Нет")]
    static let heating = [("gas", "Газ"), ("electric", "Электро"), ("none", "Нет")]
    static let finishNote = ["shell": "Фундамент, стены, перекрытия, кровля, окна и входная дверь.",
                             "rough": "Плюс штукатурка стен и стяжка — под чистовую отделку (white box).",
                             "turnkey": "Плюс плитка, ламинат, покраска, потолки и межкомнатные двери."]
}

enum HouseEstimateAPI {
    static func estimate(_ params: HouseParams, city: String, region: UserRegion?) async throws -> DocEstimateResult {
        try await post("v1/house/estimate", body: params.payload(city: city, region: region))
    }

    /// The parameter estimates (house, metal structures): computed on the server from the geometry and the weekly prices.
    static func post(_ path: String, body: [String: Any]) async throws -> DocEstimateResult {
        guard let base = AIServerConfig.marketURL else { throw DocEstimateError.noServer }
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(AIServerConfig.installID, forHTTPHeaderField: "X-Install-ID")
        if !AIServerConfig.appToken.isEmpty { request.setValue(AIServerConfig.appToken, forHTTPHeaderField: "X-App-Token") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw DocEstimateError.server(message ?? "Сервер ответил с ошибкой \(code).")
        }
        return try JSONDecoder().decode(DocEstimateResult.self, from: data)
    }
}

struct HouseEstimateParamsView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("houseParams.v1") private var saved = ""
    @State private var p = HouseParams()
    @State private var lengthText = "12"
    @State private var widthText = "10"
    @State private var busy = false
    @State private var error: String?
    @State private var result: DocEstimateResult?
    @State private var aiSent = false
    @FocusState private var focused: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(eyebrow: "Смета дома", title: "Опишите дом — посчитаем всё")
                RegionChip()
                Text("Объёмы считаются по размерам дома: периметр, стены за вычетом окон, кровля по скатам, фундамент. Цены — реальные предложения вашего города, обновляются раз в неделю.")
                    .font(.subheadline).foregroundStyle(Theme.muted)

                ParamCard("Размеры") {
                    HStack(spacing: 12) {
                        numberField("Длина, м", text: $lengthText, id: "length")
                        numberField("Ширина, м", text: $widthText, id: "width")
                    }
                    Stepper("Этажей: \(p.floors)", value: $p.floors, in: 1...3)
                    OptionChips([("2.5", "2,5 м"), ("2.7", "2,7 м"), ("2.8", "2,8 м"), ("3.0", "3,0 м"), ("3.2", "3,2 м")],
                          selection: Binding(get: { String(format: "%.1f", p.floorHeight) }, set: { p.floorHeight = Double($0) ?? 2.8 }), title: "Высота этажа")
                    Text("Площадь дома \(CalculationEngine.format(p.area)) м² · пятно застройки \(CalculationEngine.format(p.length * p.width)) м²")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                ParamCard("Фундамент") {
                    OptionChips(HouseOptions.foundation, selection: $p.foundation)
                    if p.foundation == "piles" && p.heavyWalls {
                        Label("Сваи не держат тяжёлые стены — выберите ленту или плиту, или каркас/брус.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Theme.danger)
                    }
                }
                ParamCard("Стены") { OptionChips(HouseOptions.walls, selection: $p.walls) }
                if p.floors > 1 { ParamCard("Межэтажные перекрытия") { OptionChips(HouseOptions.slabs, selection: $p.slabs) } }
                ParamCard("Кровля") {
                    OptionChips(HouseOptions.roof, selection: $p.roof)
                    if p.roof != "flat" {
                        OptionChips(HouseOptions.roofCover, selection: $p.roofCover)
                        Stepper("Уклон: \(Int(p.pitch))°", value: $p.pitch, in: 15...45, step: 5)
                    }
                }
                ParamCard("Фасад") { OptionChips(HouseOptions.facade, selection: $p.facade) }
                ParamCard("Отделка") {
                    OptionChips(HouseOptions.finish, selection: $p.finish)
                    Text(HouseOptions.finishNote[p.finish] ?? "").font(.caption).foregroundStyle(Theme.muted)
                }
                ParamCard("Инженерия") {
                    Toggle("Электрика", isOn: $p.electric)
                    Toggle("Водопровод", isOn: $p.water)
                    OptionChips(HouseOptions.sewer, selection: $p.sewer, title: "Канализация")
                    OptionChips(HouseOptions.heating, selection: $p.heating, title: "Отопление")
                    Toggle("Скважина на воду", isOn: $p.well)
                    Stepper(p.bathrooms == 0 ? "Санузлов: по площади" : "Санузлов: \(p.bathrooms)", value: $p.bathrooms, in: 0...6)
                }
                ParamCard("Начисления") {
                    Toggle("НДС 22 %", isOn: $p.vat)
                    Stepper("Непредвиденные: \(Int(p.contingency)) %", value: $p.contingency, in: 0...20)
                }

                if let error { Label(error, systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(Theme.danger) }
                if busy {
                    HStack(spacing: 10) { ProgressView(); Text("Считаем объёмы и цены…").font(.subheadline).foregroundStyle(Theme.muted) }.frame(maxWidth: .infinity).padding(16)
                } else {
                    PrimaryButton(title: "Рассчитать смету", icon: "sparkles") { Task { await calculate() } }
                        .disabled(!canCalculate).opacity(canCalculate ? 1 : 0.5)
                    Button { Task { await sendToAI() } } label: {
                        SecondaryActionLabel(title: aiSent ? "Отправлено ИИ‑сметчику" : "Точный расчёт ИИ‑сметчиком", icon: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(PremiumPressStyle()).disabled(!canCalculate || aiSent)
                    Text("ИИ‑сметчик пересчитает дом по описанию с поиском цен под ваш объект — за кредиты, 10–30 минут. Результат появится в «Смета по документам».")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .navigationTitle("Смета дома").navigationBarTitleDisplayMode(.inline)
        .helperScreen("Смета дома", details: p.description)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Готово") { focused = nil } } }
        .navigationDestination(item: $result) { r in DocEstimateResultView(result: r) }
        .onAppear(perform: load)
        .onChange(of: p) { _, new in if let data = try? JSONEncoder().encode(new) { saved = String(decoding: data, as: UTF8.self) } }
        .onChange(of: lengthText) { _, v in if let x = CalculationEngine.parse(v), x > 0 { p.length = min(x, 40) } }
        .onChange(of: widthText) { _, v in if let x = CalculationEngine.parse(v), x > 0 { p.width = min(x, 30) } }
        .task { await store.ensureRegion() }
    }

    private var canCalculate: Bool {
        (CalculationEngine.parse(lengthText) ?? 0) >= 4 && (CalculationEngine.parse(widthText) ?? 0) >= 4 && !(p.foundation == "piles" && p.heavyWalls)
    }

    private func load() {
        if let data = saved.data(using: .utf8), let old = try? JSONDecoder().decode(HouseParams.self, from: data) { p = old }
        lengthText = CalculationEngine.format(p.length); widthText = CalculationEngine.format(p.width)
    }

    private func calculate() async {
        focused = nil; busy = true; error = nil
        defer { busy = false }
        do {
            result = try await HouseEstimateAPI.estimate(p, city: store.projectCity, region: store.userRegion)
            Haptics.success()
            store.track("house_estimate")
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "Не удалось посчитать. Проверьте интернет и попробуйте ещё раз."
        }
    }

    private func sendToAI() async {
        focused = nil; error = nil
        do {
            _ = try await DocEstimateCenter.shared.start(title: "Дом \(CalculationEngine.format(p.length))×\(CalculationEngine.format(p.width))", city: store.projectCity,
                                                         text: p.description, docs: [],
                                                         options: .init(vat: p.vat, vatPct: 22, deliveryPct: 0, contingencyPct: p.contingency, deliveryMode: "lines"))
            aiSent = true
            Haptics.success()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "Не удалось отправить. Попробуйте ещё раз."
        }
    }

    private func numberField(_ title: String, text: Binding<String>, id: String) -> some View {
        NumberInputField(title: title, text: text, id: id, focused: $focused)
    }
}

/// Chips that wrap onto the next line instead of running off the screen.
struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

// MARK: - Shared pieces of the parameter screens

struct ParamCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased()).font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.gold)
            content
        }
        .font(.subheadline).foregroundStyle(Theme.ink)
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).panelCard(18)
    }
}

struct OptionChips: View {
    let options: [(String, String)]
    @Binding var selection: String
    var title: String?
    init(_ options: [(String, String)], selection: Binding<String>, title: String? = nil) { self.options = options; _selection = selection; self.title = title }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title { Text(title).font(.caption).foregroundStyle(Theme.muted) }
            ChipFlow(spacing: 8) {
                ForEach(options, id: \.0) { option in
                    let on = selection == option.0
                    Button { withAnimation(.snappy) { selection = option.0 }; Haptics.tap() } label: {
                        Text(option.1).font(.subheadline.weight(on ? .semibold : .regular))
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .foregroundStyle(on ? Theme.onAccent : Theme.ink)
                            .background(on ? AnyShapeStyle(Theme.orange) : AnyShapeStyle(Theme.panelRaised.opacity(0.6)), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct NumberInputField: View {
    let title: String
    @Binding var text: String
    let id: String
    var focused: FocusState<String?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(Theme.muted)
            TextField("0", text: $text).keyboardType(.decimalPad).focused(focused, equals: id)
                .font(.title3.weight(.semibold)).padding(12).background(Theme.panelRaised.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
