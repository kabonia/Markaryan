import SwiftUI
import StoreKit

@main struct MarkaryanApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            LaunchGateView().environmentObject(store).tint(Theme.orange).preferredColorScheme(.dark)
                .alert("Сохранение", isPresented: Binding(get: { store.storageError != nil }, set: { if !$0 { store.storageError = nil } })) {
                    Button("Понятно") { store.storageError = nil }
                } message: { Text(store.storageError ?? "") }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.flush() }
            if phase == .active { Task { await store.refreshPriceBook(silent: true) } }
        }
    }
}

/// Short branded splash. The price book is refreshed in the background, so a slow network never blocks the launch.
struct LaunchGateView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false
    @State private var revealsLogo = false
    @State private var opensApp = false
    var body: some View {
        ZStack {
            if opensApp {
                RootView()
                    .transition(.opacity.combined(with: .scale(scale: 1.015)))
                    .fullScreenCover(isPresented: Binding(get: { !onboardingCompleted }, set: { if !$0 { onboardingCompleted = true } })) {
                        OnboardingView { onboardingCompleted = true }.environmentObject(store)
                    }
            } else {
                ZStack {
                    LinearGradient(colors: [Theme.background, Color(red: 0.11, green: 0.15, blue: 0.13)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
                    Circle().fill(Theme.orange.opacity(0.12)).frame(width: 360, height: 360).blur(radius: 36).offset(x: 110, y: -260)
                    VStack(spacing: 20) {
                        Image("BrandMark").resizable().scaledToFit().frame(width: 108, height: 108).padding(26)
                            .background(Theme.panel.opacity(0.92), in: RoundedRectangle(cornerRadius: 34, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).stroke(Theme.orange.opacity(0.45), lineWidth: 1))
                        VStack(spacing: 7) {
                            Text("АРТСТРОЙ").font(.title2.bold()).tracking(3)
                            Text("ИП МАРКАРЯН А.В.").font(.caption.weight(.semibold)).tracking(1.1).foregroundStyle(Theme.muted)
                            Text("СТРОИМ В СОЧИ С \(String(Brand.foundedYear)) ГОДА").font(.caption.weight(.medium)).tracking(1.5).foregroundStyle(Theme.muted)
                        }
                    }.opacity(revealsLogo ? 1 : 0).scaleEffect(revealsLogo ? 1 : 0.92)
                }.transition(.opacity)
            }
        }.task {
            Task { await store.refreshPriceBook(silent: true) }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { revealsLogo = true }
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.easeInOut(duration: 0.38)) { opensApp = true }
            store.track("app_open")
        }
    }
}

struct PrimaryButton: View {
    let title: String
    var icon = "plus"
    let action: () -> Void
    var body: some View {
        Button { Haptics.tap(); action() } label: {
            HStack { Text(title).fontWeight(.semibold); Spacer(); Image(systemName: icon) }
                .padding(18).foregroundStyle(.black)
                .background(LinearGradient(colors: [Theme.orange, Color(red: 0.99, green: 0.53, blue: 0.30)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Theme.orange.opacity(0.25), radius: 14, y: 6)
        }
        .buttonStyle(PremiumPressStyle())
    }
}
/// Secondary full-width action with the same geometry as PrimaryButton.
struct SecondaryActionLabel: View {
    let title: String
    let icon: String
    var body: some View {
        Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding(15).panelCard(15, fill: Theme.panelRaised)
    }
}
struct PremiumPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.scaleEffect(configuration.isPressed ? 0.975 : 1).opacity(configuration.isPressed ? 0.88 : 1).animation(.easeOut(duration: 0.16), value: configuration.isPressed) }
}
struct PremiumCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}
struct SectionTitle: View {
    let eyebrow: String
    let title: String
    var body: some View { VStack(alignment: .leading, spacing: 10) { Text(eyebrow.uppercased()).font(.caption.weight(.semibold)).tracking(2).foregroundStyle(Theme.orange); Text(title).font(.title2.bold()).tracking(-0.7) }.accessibilityElement(children: .combine) }
}
struct InfoNote: View {
    let text: String
    var body: some View { Label { Text(text).font(.footnote).foregroundStyle(Theme.muted) } icon: { Image(systemName: "info.circle").foregroundStyle(Theme.orange) }.padding(16).frame(maxWidth: .infinity, alignment: .leading).panelCard(16) }
}
struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        TabView(selection: $store.tab) {
            NavigationStack { HomeView() }
                .tabItem { Label("Главная", systemImage: "square.grid.2x2.fill") }
                .tag(0)
            NavigationStack { CalculatorsView() }
                .tabItem { Label("Смета", systemImage: "function") }
                .tag(1)
            NavigationStack { AICenterTabView() }
                .tabItem { Label("ИИ", systemImage: "sparkles") }
                .tag(2)
            NavigationStack { ProjectsTabView() }
                .tabItem { Label("Проект", systemImage: "folder.fill") }
                .tag(3)
            NavigationStack { ProfileTabView() }
                .tabItem { Label("Профиль", systemImage: "person.crop.circle") }
                .tag(4)
        }
        .tint(Theme.orange)
        .toolbarBackground(Theme.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .onChange(of: store.tab) { _, _ in Haptics.tap() }
        .onChange(of: store.meaningfulActions) { _, _ in
            if store.shouldAskForReview {
                Task { try? await Task.sleep(for: .seconds(1.2)); requestReview() }
            }
        }
        .sheet(isPresented: $store.showRequest) { NavigationStack { RequestView() } }
        .sheet(isPresented: $store.showRegionPicker) { RegionPickerView() }
        .fullScreenCover(isPresented: $store.showAR) { ARMeasureView() }
        .fullScreenCover(isPresented: $store.showRoomScan) { RoomScanView() }
        .onChange(of: store.planToOpen) { _, id in if id != nil { store.tab = 3 } }
        .sheet(item: $store.arTransfer) { transfer in
            NavigationStack { CalculatorView(kind: transfer.kind, initialValues: [transfer.key: String(format: "%.2f", transfer.value)], measurementNote: "Размер передан из AR и является приблизительным. Перепроверьте его рулеткой перед закупкой.")
                    .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { store.arTransfer = nil } } } }
        }
    }
}
