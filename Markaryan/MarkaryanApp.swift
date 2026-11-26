import SwiftUI
import StoreKit

@main struct MarkaryanApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase
    init() {
        // Числа в размерах и проверках — как принято в стране пользователя («1,5» / «1.5»).
        if !AppLanguage.isRussian {
            ParcelRules.locale = .current; RoomMaterials.locale = .current
            CalculationEngine.locale = .current
            CalculationEngine.currencySymbol = Locale.current.currencySymbol ?? "$"
        }
    }
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

/// The launch screen continued: the same gold logo on the dark backdrop, the name appears and a gold ruler measures the load.
struct SplashView: View {
    let revealed: Bool
    @State private var measured = false
    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            Lux.backdrop.ignoresSafeArea().opacity(revealed ? 1 : 0)
            RadialGradient(colors: [Lux.goldMid.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: 260)
                .ignoresSafeArea().opacity(revealed ? 1 : 0)
            Image("LaunchLogo").resizable().frame(width: 240, height: 240)
                .scaleEffect(revealed ? 1.04 : 1)
            VStack(spacing: 10) {
                Text(Brand.name).font(.system(size: 34, weight: .bold, design: .serif)).foregroundStyle(Lux.goldGradient)
                Text("Сметы · замеры · дизайн").font(.footnote.weight(.semibold)).tracking(1.6).foregroundStyle(Theme.goldLight.opacity(0.8))
                SplashRuler(progress: measured ? 1 : 0).frame(width: 200, height: 18).padding(.top, 14)
            }
            .offset(y: 190)
            .opacity(revealed ? 1 : 0).offset(y: revealed ? 0 : 10)
        }
        .onAppear { withAnimation(.easeInOut(duration: 1.1).delay(0.1)) { measured = true } }
    }
}

/// A thin gold ruler that fills like a progress bar.
struct SplashRuler: View, Animatable {
    var progress: Double
    var animatableData: Double { get { progress } set { progress = newValue } }
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.10)).frame(height: 3).frame(maxHeight: .infinity, alignment: .bottom)
                Capsule().fill(Lux.goldGradient).frame(width: w * progress, height: 3).frame(maxHeight: .infinity, alignment: .bottom)
                    .shadow(color: Lux.goldBright.opacity(0.7), radius: 4)
                ForEach(0...20, id: \.self) { i in
                    let x = w * Double(i) / 20
                    Rectangle().fill(Double(i) / 20 <= progress ? Lux.goldBright : .white.opacity(0.25))
                        .frame(width: 1, height: i % 5 == 0 ? 12 : 6)
                        .position(x: x, y: geo.size.height - 3 - (i % 5 == 0 ? 6 : 3))
                }
            }
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
                SplashView(revealed: revealsLogo)
                    .transition(.opacity)
            }
        }
        .background(KeyboardDismissInstaller().frame(width: 0, height: 0))
        .task {
            KeyboardHelper.install()
            Task { await store.refreshPriceBook(silent: true) }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { revealsLogo = true }
            try? await Task.sleep(for: .milliseconds(1250))
            withAnimation(.easeInOut(duration: 0.45)) { opensApp = true }
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
            HStack { Text(title.tr).fontWeight(.semibold); Spacer(); Image(systemName: icon) }
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
        Label(title.tr, systemImage: icon).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.orange)
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
    var body: some View { VStack(alignment: .leading, spacing: 10) { Text(eyebrow.tr.uppercased()).font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(Theme.gold); Text(title.tr).font(.system(.title2, design: .serif, weight: .bold)).tracking(-0.3).foregroundStyle(Theme.ink) }.accessibilityElement(children: .combine) }
}
struct InfoNote: View {
    let text: String
    var body: some View { Label { Text(text.tr).font(.footnote).foregroundStyle(Theme.muted) } icon: { Image(systemName: "info.circle").foregroundStyle(Theme.orange) }.padding(16).frame(maxWidth: .infinity, alignment: .leading).panelCard(16) }
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
            NavigationStack { CalculatorsView() }
                .tabItem { Label("Смета", systemImage: "function") }
                .tag(1)
            NavigationStack { FloorPlansView() }
                .tabItem { Label("Дизайн", systemImage: "cube.transparent.fill") }
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
        .fullScreenCover(isPresented: $store.showHouseScan) { HouseScanView() }
        .onChange(of: store.planToOpen) { _, id in if id != nil { store.tab = 2 } }
        .onChange(of: store.apartmentToOpen) { _, id in if id != nil { store.tab = 2 } }
        .sheet(item: $store.arTransfer) { transfer in
            NavigationStack { CalculatorView(kind: transfer.kind, initialValues: [transfer.key: String(format: "%.2f", transfer.value)], measurementNote: "Размер передан из AR и является приблизительным. Перепроверьте его рулеткой перед закупкой.")
                    .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { store.arTransfer = nil } } } }
        }
    }
}
