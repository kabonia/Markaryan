import SwiftUI
import UIKit

/// Choice of the city for prices and contractors: by location or by hand.
struct RegionPickerView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var filtered: [UserRegion] {
        guard !trimmedQuery.isEmpty else { return UserRegion.cities }
        let q = trimmedQuery.lowercased()
        return UserRegion.cities.filter { $0.city.lowercased().contains(q) || $0.region.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Task { if await store.detectRegion() { dismiss() } }
                    } label: {
                        HStack {
                            Label("Определить по местоположению", systemImage: "location.fill")
                            Spacer()
                            if store.regionDetecting { ProgressView() }
                        }
                    }
                    .disabled(store.regionDetecting)
                    if store.locationDenied {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Доступ к геопозиции выключен. Выберите город из списка или разрешите доступ в Настройках.")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button("Открыть Настройки") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            }.font(.footnote.weight(.semibold))
                        }
                    }
                } footer: {
                    Text("Используется только город, чтобы подставить цены магазинов и мастеров вашего региона. Точные координаты не сохраняются.")
                }

                Section("Города") {
                    if !trimmedQuery.isEmpty, !filtered.contains(where: { $0.city.lowercased() == trimmedQuery.lowercased() }) {
                        Button {
                            choose(UserRegion(city: trimmedQuery, region: "", latitude: nil, longitude: nil, source: .manual))
                        } label: { Label("Использовать «\(trimmedQuery)»", systemImage: "plus.circle") }
                    }
                    ForEach(filtered) { region in
                        Button { choose(region) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(region.city).foregroundStyle(.primary)
                                    if region.region != region.city { Text(region.region).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                if store.userRegion?.city == region.city { Image(systemName: "checkmark").foregroundStyle(Theme.orange) }
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Город")
            .navigationTitle("Город для цен")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Закрыть") { dismiss() } } }
        }
        .tint(Theme.orange)
    }

    private func choose(_ region: UserRegion) {
        Haptics.tap()
        store.setRegion(region)
        dismiss()
    }
}

/// Shows the city the estimate is priced for; tap to change it.
struct RegionChip: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Button { store.showRegionPicker = true } label: {
            HStack(spacing: 8) {
                Image(systemName: store.userRegion?.source == .location ? "location.fill" : "mappin.and.ellipse")
                    .foregroundStyle(Theme.orange)
                Text(store.userRegion.map { "Цены для: \($0.city)" } ?? "Выберите город для цен")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Spacer(minLength: 0)
                if store.regionDetecting { ProgressView().controlSize(.small).tint(Theme.orange) }
                else { Text("Изменить").font(.caption.weight(.semibold)).foregroundStyle(Theme.orange) }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .panelCard(14)
        }
        .buttonStyle(PremiumPressStyle())
        .accessibilityHint("Открывает выбор города")
    }
}

/// Where the prices of the current estimate come from, in one line.
struct PriceSourceNote: View {
    @EnvironmentObject private var store: AppStore

    private var text: String {
        let book = store.priceBook
        let date = book.updatedAt.formatted(date: .abbreviated, time: .omitted)
        switch book.coverage ?? "" {
        case "city", "region", "nearby", "national":
            let place: String
            switch book.coverage ?? "" {
            case "region": place = "по региону \(book.city ?? "")"
            case "nearby": place = "по ближайшему городу \(book.city ?? "")" + (book.distanceKm.map { " (\(Int($0)) км)" } ?? "")
            case "national": place = "средние по России"
            default: place = "для города \(book.city ?? "")"
            }
            return "Рыночные цены \(place) от \(date): \(book.marketLineCount) из \(book.lines.count) позиций. Медиана предложений магазинов, маркетплейсов и мастеров, завышенные, заниженные и фейковые объявления отсечены. Позиции без рыночных данных отмечены «ориентир»."
        case "import":
            return "Цены из загруженного файла прайса от \(date)."
        default:
            return "Рыночные цены для вашего города ещё не собраны. Смета посчитана по базовым ориентирам, это предварительная оценка."
        }
    }

    var body: some View { InfoNote(text: text) }
}

/// Partner contractors for the user's city, shown after an estimate.
struct PartnerOfferSection: View {
    @EnvironmentObject private var store: AppStore
    /// Work category: estimate kind (house, gazebo, metal) or calculator category (foundation, walls, roof, finishing, outdoor).
    let category: String
    /// Text the user sends to a partner in WhatsApp.
    let summary: String
    @State private var partners: [Partner] = []

    var body: some View {
        Group {
            if store.userRegion == nil {
                Button { store.showRegionPicker = true } label: {
                    SecondaryActionLabel(title: "Выберите город, чтобы увидеть подрядчиков", icon: "mappin.and.ellipse")
                }.buttonStyle(PremiumPressStyle())
            } else if !partners.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("ПОДРЯДЧИКИ · \((store.userRegion?.city ?? "").uppercased())")
                        .font(.caption.weight(.bold)).tracking(1.3).foregroundStyle(Theme.orange)
                    Text("Сравните рыночную оценку с ценой подрядчика: отправьте ему расчёт.")
                        .font(.caption).foregroundStyle(Theme.muted)
                    ForEach(partners) { partner in PartnerCard(partner: partner, summary: summary) }
                }
            }
        }
        .task(id: "\(store.userRegion?.id ?? "")|\(category)") {
            partners = await store.partners(category: category)
            for partner in partners { store.partnerEvent(partner.id, "view") }
        }
    }
}

struct PartnerCard: View {
    @EnvironmentObject private var store: AppStore
    let partner: Partner
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(partner.name).font(.headline)
                    if let description = partner.description, !description.isEmpty {
                        Text(description).font(.caption).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if let rating = partner.rating, rating > 0 {
                    Label(String(format: "%.1f", rating), systemImage: "star.fill")
                        .font(.caption.weight(.bold)).foregroundStyle(Theme.orangeSoft)
                }
            }
            HStack(spacing: 8) {
                if let url = partner.whatsAppURL(text: summary) { action("WhatsApp", "message.fill", url, "click_whatsapp") }
                if let url = partner.phoneURL { action("Позвонить", "phone.fill", url, "click_phone") }
                if let url = partner.siteURL { action("Сайт", "safari", url, "click_site") }
            }
        }
        .padding(16)
        .panelCard(18)
    }

    private func action(_ title: String, _ icon: String, _ url: URL, _ event: String) -> some View {
        Link(destination: url) { SecondaryActionLabel(title: title, icon: icon) }
            .buttonStyle(PremiumPressStyle())
            .simultaneousGesture(TapGesture().onEnded { store.partnerEvent(partner.id, event) })
    }
}
