import SwiftUI

// MARK: - «Металлоконструкции»: canopy, frame building or fence → steel by the profile, works, machines, delivery

struct MetalParams: Codable, Equatable {
    var type = "canopy"
    var length = 6.0
    var width = 4.0
    var height = 2.7
    var roof = "single"
    var cover = "polycarb"
    var walls = "profwall"
    var floor = true
    var gates = 1
    var wickets = 1
    var doors = 1
    var filling = "profwall"
    var paint = true
    var vat = false
    var contingency = 5.0

    func payload(city: String, region: UserRegion?) -> [String: Any] {
        var body: [String: Any] = [
            "type": type, "length": length, "width": width, "height": height, "roof": roof, "cover": cover, "walls": walls,
            "floor": floor, "gates": gates, "wickets": wickets, "doors": doors, "filling": filling, "paint": paint, "city": city,
            "options": ["vat": vat, "contingencyPct": contingency],
        ]
        if let lat = region?.latitude, let lon = region?.longitude { body["lat"] = lat; body["lon"] = lon }
        return body
    }
}

enum MetalOptions {
    static let type = [("canopy", "Навес"), ("hangar", "Ангар / склад"), ("fence", "Забор")]
    static let roof = [("single", "Односкатная"), ("gable", "Двускатная"), ("arch", "Арочная")]
    static let cover = [("polycarb", "Поликарбонат"), ("profroof", "Профнастил"), ("metaltile", "Металлочерепица")]
    static let walls = [("profwall", "Профлист (холодный)"), ("sandwich", "Сэндвич‑панели (тёплый)"), ("open", "Без стен")]
    static let filling = [("profwall", "Профнастил"), ("picket", "Евроштакетник"), ("mesh3d", "3D‑сетка")]
    static let note = ["canopy": "Навес для машины, террасы или площадки: стойки на бетонных опорах, стропила или фермы, обрешётка, кровля, водосток.",
                       "hangar": "Каркасное здание — склад, ангар, гараж, мастерская: рамы с шагом 6 м на фундаментах, прогоны, стены и кровля, ворота, пол.",
                       "fence": "Забор на столбах 60×60 с шагом 2,5 м, лаги, заполнение, ворота и калитки."]
}

struct MetalEstimateParamsView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("metalParams.v1") private var saved = ""
    @State private var p = MetalParams()
    @State private var lengthText = "6"
    @State private var widthText = "4"
    @State private var heightText = "2,7"
    @State private var busy = false
    @State private var error: String?
    @State private var result: DocEstimateResult?
    @FocusState private var focused: String?

    private var fence: Bool { p.type == "fence" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(eyebrow: "Металлоконструкции", title: "Посчитаем по весу металла")
                RegionChip()
                Text("Металл считается по длине каждого профиля и весу метра, работа — по тоннам, окраска — по площади поверхности. Цены — реальные предложения вашего города, раз в неделю.")
                    .font(.subheadline).foregroundStyle(Theme.muted)

                ParamCard("Что строим") {
                    OptionChips(MetalOptions.type, selection: $p.type)
                    Text(MetalOptions.note[p.type] ?? "").font(.caption).foregroundStyle(Theme.muted)
                }
                ParamCard("Размеры") {
                    HStack(spacing: 12) {
                        NumberInputField(title: fence ? "Длина забора, м" : "Длина, м", text: $lengthText, id: "length", focused: $focused)
                        if !fence { NumberInputField(title: "Ширина, м", text: $widthText, id: "width", focused: $focused) }
                        NumberInputField(title: fence ? "Высота, м" : "Высота, м", text: $heightText, id: "height", focused: $focused)
                    }
                    Text(fence ? "Площадь заполнения \(CalculationEngine.format(p.length * p.height)) м²" : "Площадь \(CalculationEngine.format(p.length * p.width)) м²")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                switch p.type {
                case "canopy":
                    ParamCard("Кровля") {
                        OptionChips(MetalOptions.roof, selection: $p.roof)
                        OptionChips(MetalOptions.cover, selection: $p.cover)
                    }
                case "hangar":
                    ParamCard("Стены и кровля") { OptionChips(MetalOptions.walls, selection: $p.walls) }
                    ParamCard("Ворота, двери, пол") {
                        Stepper("Секционные ворота 4×4 м: \(p.gates)", value: $p.gates, in: 0...6)
                        Stepper("Входные двери: \(p.doors)", value: $p.doors, in: 0...6)
                        Toggle("Бетонный пол", isOn: $p.floor)
                    }
                default:
                    ParamCard("Заполнение") { OptionChips(MetalOptions.filling, selection: $p.filling) }
                    ParamCard("Ворота и калитки") {
                        Stepper("Распашные ворота 4 м: \(p.gates)", value: $p.gates, in: 0...6)
                        Stepper("Калитки: \(p.wickets)", value: $p.wickets, in: 0...6)
                    }
                }
                ParamCard("Защита и начисления") {
                    Toggle("Грунтовка и окраска металла", isOn: $p.paint)
                    Toggle("НДС 22 %", isOn: $p.vat)
                    Stepper("Непредвиденные: \(Int(p.contingency)) %", value: $p.contingency, in: 0...20)
                }

                if let error { Label(error, systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(Theme.danger) }
                if busy {
                    HStack(spacing: 10) { ProgressView(); Text("Считаем металл и цены…").font(.subheadline).foregroundStyle(Theme.muted) }.frame(maxWidth: .infinity).padding(16)
                } else {
                    PrimaryButton(title: "Рассчитать смету", icon: "sparkles") { Task { await calculate() } }
                        .disabled(!canCalculate).opacity(canCalculate ? 1 : 0.5)
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .navigationTitle("Металлоконструкции").navigationBarTitleDisplayMode(.inline)
        .helperScreen("Смета металлоконструкций", details: "\(MetalOptions.type.first { $0.0 == p.type }?.1 ?? ""): \(CalculationEngine.format(p.length))×\(CalculationEngine.format(p.width))×\(CalculationEngine.format(p.height)) м")
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Готово") { focused = nil } } }
        .navigationDestination(item: $result) { r in DocEstimateResultView(result: r) }
        .onAppear(perform: load)
        .onChange(of: p) { _, new in if let data = try? JSONEncoder().encode(new) { saved = String(decoding: data, as: UTF8.self) } }
        .onChange(of: lengthText) { _, v in if let x = CalculationEngine.parse(v), x > 0 { p.length = min(x, 200) } }
        .onChange(of: widthText) { _, v in if let x = CalculationEngine.parse(v), x > 0 { p.width = min(x, 48) } }
        .onChange(of: heightText) { _, v in if let x = CalculationEngine.parse(v), x > 0 { p.height = min(x, 12) } }
        .task { await store.ensureRegion() }
    }

    private var canCalculate: Bool {
        let l = CalculationEngine.parse(lengthText) ?? 0, w = CalculationEngine.parse(widthText) ?? 0, h = CalculationEngine.parse(heightText) ?? 0
        return h >= 1 && (fence ? l >= 4 : l >= 2 && w >= 2)
    }

    private func load() {
        if let data = saved.data(using: .utf8), let old = try? JSONDecoder().decode(MetalParams.self, from: data) { p = old }
        lengthText = CalculationEngine.format(p.length); widthText = CalculationEngine.format(p.width); heightText = CalculationEngine.format(p.height)
    }

    private func calculate() async {
        focused = nil; busy = true; error = nil
        defer { busy = false }
        do {
            result = try await HouseEstimateAPI.post("v1/metal/estimate", body: p.payload(city: store.projectCity, region: store.userRegion))
            Haptics.success()
            store.track("metal_estimate_\(p.type)")
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "Не удалось посчитать. Проверьте интернет и попробуйте ещё раз."
        }
    }
}
