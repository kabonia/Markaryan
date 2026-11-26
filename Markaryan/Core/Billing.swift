import SwiftUI
import StoreKit

// MARK: - Credits and plans: balance from the server, purchases through the App Store (USA and the rest of the world)
// or on the website with СБП / card (Russia, where the App Store does not take payments).

struct BillingMe: Decodable {
    struct Plan: Decodable { var id: String; var until: String }
    struct Autopay: Decodable { var on: Bool; var title: String? }
    struct Item: Decodable, Identifiable {
        var id: String; var title: String; var titleEn: String?; var plan: String?; var credits: Int; var rub: Double; var usd: Double
        var apple: String?; var days: Int?
        /// Пакет функций: сколько единиц каждой функции даёт (nil — обычные кредиты или подписка).
        var grants: [String: Int]?
        var includes: String?
    }
    var enabled: Bool
    var code: String
    var credits: Int
    var plan: Plan?
    var autopay: Autopay?
    var prices: [String: Int]
    var helperFreePerDay: Int?
    var products: [Item]
    var payUrl: String?
    /// Остатки купленных пакетов: вид функции → единиц.
    var packs: [String: Int]?
}

@MainActor
final class BillingCenter: ObservableObject {
    static let shared = BillingCenter()
    @Published private(set) var me: BillingMe?
    @Published private(set) var storeProducts: [Product] = []
    @Published private(set) var russia = false
    @Published var busy = false
    @Published var message: String?
    private var updates: Task<Void, Never>?

    /// At launch: listen for renewals and purchases made elsewhere, send what the App Store has, load the balance.
    func start() async {
        if updates == nil {
            updates = Task { [weak self] in
                for await result in Transaction.updates {
                    if case .verified(let transaction) = result {
                        await self?.send([result.jwsRepresentation])
                        await transaction.finish()
                    }
                }
            }
        }
        russia = await Storefront.current?.countryCode == "RUS"
        await refresh()
        var current: [String] = []
        for await result in Transaction.currentEntitlements { current.append(result.jwsRepresentation) }
        if !current.isEmpty { await send(current) }
    }

    func refresh() async {
        guard let base = AIServerConfig.marketURL else { return }
        if let answer = try? await URLSession.shared.data(for: request(base, "v1/billing/me")), (answer.1 as? HTTPURLResponse)?.statusCode == 200 {
            me = try? JSONDecoder().decode(BillingMe.self, from: answer.0)
        }
        if !russia, storeProducts.isEmpty, let ids = me?.products.compactMap(\.apple), !ids.isEmpty {
            storeProducts = ((try? await Product.products(for: ids)) ?? []).sorted { $0.price < $1.price }
        }
    }

    func buy(_ product: Product) async {
        busy = true; message = nil
        defer { busy = false }
        do {
            var options: Set<Product.PurchaseOption> = []
            if let token = UUID(uuidString: AIServerConfig.installID) { options.insert(.appAccountToken(token)) }
            switch try await product.purchase(options: options) {
            case .success(let result):
                guard case .verified(let transaction) = result else { message = "Покупка не прошла проверку Apple."; return }
                await send([result.jwsRepresentation])
                await transaction.finish()
                message = "Готово: \(product.displayName)."
                Haptics.success()
            case .pending: message = "Покупка ждёт подтверждения."
            case .userCancelled: break
            @unknown default: break
            }
        } catch {
            message = error.localizedDescription
            HelperCenter.shared.failed(error, action: "Покупка в App Store")
        }
    }

    func restore() async {
        busy = true; defer { busy = false }
        try? await StoreKit.AppStore.sync()
        var all: [String] = []
        for await result in Transaction.currentEntitlements { all.append(result.jwsRepresentation) }
        await send(all)
        message = all.isEmpty ? "Покупок для восстановления нет." : "Покупки восстановлены."
    }

    func setAutopay(_ on: Bool) async {
        guard let base = AIServerConfig.marketURL else { return }
        var req = request(base, "v1/billing/autopay")
        req.httpMethod = "POST"
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["on": on])
        if let answer = try? await URLSession.shared.data(for: req) { me = (try? JSONDecoder().decode(BillingMe.self, from: answer.0)) ?? me }
    }

    private func send(_ transactions: [String]) async {
        guard !transactions.isEmpty, let base = AIServerConfig.marketURL else { return }
        var req = request(base, "v1/billing/apple")
        req.httpMethod = "POST"
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["transactions": transactions])
        if let answer = try? await URLSession.shared.data(for: req),
           let json = try? JSONSerialization.jsonObject(with: answer.0) as? [String: Any], let me = json["me"],
           let meData = try? JSONSerialization.data(withJSONObject: me) {
            self.me = (try? JSONDecoder().decode(BillingMe.self, from: meData)) ?? self.me
        }
    }

    private func request(_ base: URL, _ path: String) -> URLRequest {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.timeoutInterval = 30
        request.setValue(AIServerConfig.installID, forHTTPHeaderField: "X-Install-ID")
        request.setValue(AppLanguage.code, forHTTPHeaderField: "X-App-Language")
        if !AIServerConfig.appToken.isEmpty { request.setValue(AIServerConfig.appToken, forHTTPHeaderField: "X-App-Token") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
}

// MARK: - «Тарифы и баланс»

struct BillingView: View {
    @ObservedObject private var billing = BillingCenter.shared
    @State private var copied = false

    private let priceNames: [(String, String)] = [
        ("smeta", "Смета по документам, до 2 листов"), ("smetaPage", "…каждый следующий лист"), ("json", "Дизайн‑проект комнаты"),
        ("imageEdit", "Визуализация, 1 кадр"), ("vision", "Счёт по фото"), ("chat", "Вопрос сильной модели"),
        ("priceEstimate10", "Цены по рынку, за 10 позиций"), ("material", "Распознать свой материал"), ("helper", "Помощник сверх бесплатных"),
        ("houseScan", "3D‑обмер дома: стены, окна, крыша"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                balance
                if let me = billing.me, !me.enabled {
                    InfoNote(text: "Сейчас все функции бесплатны. Когда включится оплата, баланс и тарифы будут здесь.")
                }
                packsCard
                if billing.russia { russiaCard } else { storeCard }
                if let message = billing.message { Text(message.tr).font(.footnote).foregroundStyle(Theme.muted) }
                pricesCard
                NavigationLink { SupportView(presetTopic: "paid") } label: {
                    AppTabRow(icon: "bubble.left.and.exclamationmark.bubble.right.fill", title: "Списались кредиты, а результата нет?",
                              subtitle: "Напишите в поддержку — проверим и вернём кредиты")
                }
                .buttonStyle(PremiumCardPressStyle())
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Тарифы и баланс").helperScreen("Тарифы и баланс").featureIntro(.billing)
        .navigationBarTitleDisplayMode(.inline)
        .task { await billing.refresh() }
        .refreshable { await billing.refresh() }
    }

    private var balance: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("БАЛАНС").font(.caption.weight(.semibold)).tracking(1.8).foregroundStyle(Theme.goldLight)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(billing.me?.credits ?? 0)").font(.system(size: 44, weight: .bold, design: .serif)).foregroundStyle(.white).monospacedDigit()
                Text("кредитов").font(.headline).foregroundStyle(.white.opacity(0.8))
            }
            if let plan = billing.me?.plan {
                Text("\(plan.id == "business" ? "Бизнес" : "Про") до \(String(plan.until.prefix(10)))").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.goldLight)
            } else {
                Text("Без подписки · \(billing.me?.helperFreePerDay ?? 20) вопросов помощнику в день бесплатно").font(.caption).foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(22).padding(.trailing, 74).frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) {
            CreditCoin(size: 72).rotationEffect(.degrees(-8)).padding(.trailing, 22)
        }
        .background(Lux.backdrop, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.goldHairline, lineWidth: 0.8))
    }

    /// Russia: the App Store takes no payments, so plans and credits are paid on the website by the account number.
    private var russiaCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Правило App Store 3.1.1/3.1.3(b): внутри приложения не указываем, где и как оплатить мимо App Store —
            // только номер аккаунта (кредиты, купленные в других местах, появляются здесь сами).
            Text("ВАШ АККАУНТ").font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(Theme.gold)
            Text("Номер аккаунта — для поддержки и для входа на другом устройстве. Баланс и подписка обновляются здесь автоматически.")
                .font(.subheadline).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(billing.me?.code ?? "—").font(.system(.title3, design: .monospaced, weight: .bold)).foregroundStyle(Theme.ink)
                Spacer()
                Button { UIPasteboard.general.string = billing.me?.code; copied = true; Haptics.success() } label: {
                    Label(copied ? "Скопировано" : "Копировать", systemImage: copied ? "checkmark" : "doc.on.doc").font(.subheadline.weight(.semibold))
                }
            }
            .padding(14).fieldSurface(14)
            if let pay = billing.me?.autopay {
                Toggle(isOn: Binding(get: { pay.on }, set: { on in Task { await billing.setAutopay(on) } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Автопродление подписки").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                        Text(pay.title ?? "Сохранённый способ оплаты").font(.caption).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .padding(18).panelCard(20)
    }

    /// USA and the rest: App Store purchases (Apple Pay or the card of the Apple ID).
    private var storeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ПОДПИСКИ И КРЕДИТЫ").font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(Theme.gold)
            if billing.storeProducts.isEmpty {
                Text("Загружаем предложения App Store…").font(.subheadline).foregroundStyle(Theme.muted)
            }
            ForEach(billing.storeProducts, id: \.id) { product in
                Button { Task { await billing.buy(product) } } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(product.displayName).font(.system(.subheadline, design: .serif, weight: .bold)).foregroundStyle(Theme.ink)
                            Text(product.description).font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
                        }
                        Spacer()
                        Text(product.displayPrice).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.onAccent)
                            .padding(.horizontal, 14).padding(.vertical, 9).background(Theme.accentGradient, in: Capsule())
                    }
                    .padding(14).panelCard(18)
                }
                .buttonStyle(PremiumCardPressStyle())
                .disabled(billing.busy)
            }
            Button("Восстановить покупки") { Task { await billing.restore() } }.font(.subheadline.weight(.semibold))
            Text("Подписка продлевается автоматически, пока её не отменят в настройках Apple ID не позднее чем за 24 часа до конца периода.")
                .font(.caption2).foregroundStyle(Theme.muted)
        }
        .padding(18).panelCard(20)
    }

    /// Остатки купленных пакетов: пока они есть, функции не тратят кредиты.
    @ViewBuilder private var packsCard: some View {
        if let packs = billing.me?.packs, !packs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("ВАШИ ПАКЕТЫ").font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(Theme.gold)
                ForEach(priceNames.filter { (packs[$0.0] ?? 0) > 0 }, id: \.0) { key, title in
                    HStack {
                        Text(title.tr).font(.subheadline).foregroundStyle(Theme.ink)
                        Spacer()
                        Text("осталось \(packs[key] ?? 0)").font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.orange)
                    }
                }
                Text("Пока в пакете есть единицы, функции не тратят кредиты. Если ИИ не справился — единица возвращается.").font(.caption).foregroundStyle(Theme.muted)
            }
            .padding(18).panelCard(20)
        }
    }

    private var pricesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("СКОЛЬКО СТОИТ").font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(Theme.gold)
            ForEach(priceNames, id: \.0) { key, title in
                if let credits = billing.me?.prices[key] {
                    HStack { Text(title.tr).font(.subheadline).foregroundStyle(Theme.ink); Spacer(); HStack(spacing: 5) { Text("\(credits)").font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.ink); CreditCoin(size: 15, shine: false) } }
                }
            }
            Text("Калькуляторы, AR‑рулетка, типовые сметы и проекты — бесплатно. Если ИИ не справился, кредиты возвращаются.").font(.caption).foregroundStyle(Theme.muted)
        }
        .padding(18).panelCard(20)
    }
}

/// Balance in the top right corner: credits and a gold «+» to top up; opens «Тарифы и баланс».
struct BalanceChip: View {
    @ObservedObject private var billing = BillingCenter.shared

    var body: some View {
        HStack(spacing: 8) {
            CreditCoin(size: 22)
            Text(billing.me.map { "\($0.credits)" } ?? "—").font(.system(.subheadline, design: .rounded, weight: .bold)).monospacedDigit().foregroundStyle(Theme.ink)
                .contentTransition(.numericText()).animation(.snappy, value: billing.me?.credits)
            Image(systemName: "plus").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.goldLight)
                .frame(width: 26, height: 26).background(Theme.heroGradient, in: Circle())
                .overlay(Circle().strokeBorder(Lux.goldGradient, lineWidth: 0.8))
        }
        .padding(.leading, 5).padding(.trailing, 4).padding(.vertical, 4)
        .background(Theme.panel, in: Capsule())
        .overlay(Capsule().strokeBorder(Lux.goldGradient, lineWidth: 0.8))
        .shadow(color: Theme.ink.opacity(0.08), radius: 8, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Баланс: \(billing.me?.credits ?? 0) кредитов. Пополнить")
        .task { if billing.me == nil { await billing.refresh() } }
    }
}
