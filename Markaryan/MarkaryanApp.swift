import SwiftUI
import StoreKit

@main struct MarkaryanApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            LaunchGateView().environmentObject(store).tint(Theme.orange).foregroundStyle(Theme.ink).preferredColorScheme(.light).environment(\.colorScheme, .light)
                .alert("Сохранение", isPresented: Binding(get: { store.storageError != nil }, set: { if !$0 { store.storageError = nil } })) {
                    Button("Понятно") { store.storageError = nil }
                } message: { Text(store.storageError ?? "") }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.flush() }
            if phase == .active { Task { await store.refreshPriceBook(silent: true) }; DocEstimateCenter.shared.resumeAll() }
        }
    }
}

/// Short branded splash. The price book is refreshed in the background, so a slow network never blocks the launch.
struct LaunchGateView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false
    @State private var revealsLogo = false
    @State private var opensApp = false
    private var mainApp: some View {
        RootView()
            .transition(.opacity.combined(with: .scale(scale: 1.015)))
            .fullScreenCover(isPresented: Binding(get: { !onboardingCompleted }, set: { if !$0 { onboardingCompleted = true } })) {
                OnboardingView { onboardingCompleted = true; HelperCenter.shared.offerTour() }.environmentObject(store)
            }
    }
    var body: some View {
        ZStack {
            if opensApp {
                #if DEBUG
                if let route = ScreenshotRoute.current, ScreenshotRoute.tab == nil {
                    NavigationStack { ScreenshotRoute.screen(route) }
                } else {
                    mainApp.onAppear { if let tab = ScreenshotRoute.tab { store.tab = tab } }
                }
                #else
                mainApp
                #endif
            } else {
                ZStack {
                    Theme.heroGradient.ignoresSafeArea()
                    Circle().fill(Color.white.opacity(0.08)).frame(width: 420, height: 420).blur(radius: 60).offset(x: 120, y: -280)
                    VStack(spacing: 22) {
                        Image(systemName: "ruler.fill")
                            .font(.system(size: 52, weight: .semibold)).rotationEffect(.degrees(-45))
                            .foregroundStyle(Theme.orange)
                            .frame(width: 112, height: 112)
                            .background(.white, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                            .shadow(color: .black.opacity(0.18), radius: 20, y: 10)
                        VStack(spacing: 8) {
                            Text(Brand.name).font(.system(size: 34, weight: .bold)).foregroundStyle(.white)
                            Text(Brand.tagline).font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 32)
                    .opacity(revealsLogo ? 1 : 0).scaleEffect(revealsLogo ? 1 : 0.92)
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
                .padding(18).foregroundStyle(Theme.onAccent)
                .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.goldHairline, lineWidth: 0.8))
                .shadow(color: Theme.orange.opacity(0.28), radius: 14, y: 6)
        }
        .buttonStyle(PremiumPressStyle())
    }
}
/// Secondary full-width action with the same geometry as PrimaryButton.
struct SecondaryActionLabel: View {
    let title: String
    let icon: String
    var body: some View {
        Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.orange)
            .frame(maxWidth: .infinity).padding(15).background(Theme.accentTint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.orange.opacity(0.14), lineWidth: 0.6))
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
    var body: some View { VStack(alignment: .leading, spacing: 10) { Text(eyebrow.uppercased()).font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(Theme.gold); Text(title).font(.system(.title2, design: .serif, weight: .bold)).tracking(-0.3).foregroundStyle(Theme.ink) }.accessibilityElement(children: .combine) }
}
struct InfoNote: View {
    let text: String
    var body: some View { Label { Text(text).font(.footnote).foregroundStyle(Theme.muted) } icon: { Image(systemName: "info.circle").foregroundStyle(Theme.orange) }.padding(16).frame(maxWidth: .infinity, alignment: .leading).panelCard(16) }
}
struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var helper = HelperCenter.shared
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        TabView(selection: $store.tab) {
            NavigationStack { HomeView() }
                .tabItem { Label("Главная", systemImage: "square.grid.2x2.fill") }
                .tag(0)
            NavigationStack { EstimatesTabView() }
                .tabItem { Label("Сметы", systemImage: "doc.text.fill") }
                .tag(1)
            NavigationStack { FloorPlansView() }
                .tabItem { Label("Дизайн", systemImage: "cube.transparent.fill") }
                .tag(2)
            NavigationStack { CalculatorsView() }
                .tabItem { Label("Калькуляторы", systemImage: "function") }
                .tag(3)
            NavigationStack { ProfileTabView() }
                .tabItem { Label("Профиль", systemImage: "person.crop.circle") }
                .tag(4)
        }
        .tint(Theme.orange)
        .toolbarBackground(Theme.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.light, for: .tabBar)
        .onChange(of: store.tab) { _, _ in Haptics.tap() }
        .onChange(of: store.meaningfulActions) { _, _ in
            if store.shouldAskForReview {
                Task { try? await Task.sleep(for: .seconds(1.2)); requestReview() }
            }
        }
        .sheet(isPresented: $store.showRegionPicker) { RegionPickerView() }
        .sheet(isPresented: $helper.isOpen) { HelperChatView().presentationDetents([.medium, .large]).presentationDragIndicator(.visible) }
        .overlay(alignment: .bottomTrailing) { if helper.tourStep == nil { HelperButton().padding(.trailing, 18).padding(.bottom, 92) } }
        .overlay(alignment: .top) { HelperNoticeBanner().padding(.top, 4).animation(.spring(response: 0.4), value: helper.notice) }
        .overlay { HelperTourOverlay().animation(.easeInOut(duration: 0.2), value: helper.tourStep) }
        .fullScreenCover(isPresented: $store.showAR) { ARMeasureView() }
        .fullScreenCover(isPresented: $store.showRoomScan) { RoomScanView() }
        .onChange(of: store.planToOpen) { _, id in if id != nil { store.tab = 2 } }
        .onChange(of: store.apartmentToOpen) { _, id in if id != nil { store.tab = 2 } }
        .sheet(item: $store.arTransfer) { transfer in
            NavigationStack { CalculatorView(kind: transfer.kind, initialValues: [transfer.key: String(format: "%.2f", transfer.value)], measurementNote: "Размер передан из AR и является приблизительным. Перепроверьте его рулеткой перед закупкой.")
                    .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { store.arTransfer = nil } } } }
        }
    }
}
