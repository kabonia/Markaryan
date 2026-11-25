import SwiftUI

#if DEBUG
/// Debug-only: opens one screen straight away for automated screenshots in CI.
/// Launch with `-screenshotRoute <route>` (and `-onboardingCompleted YES`).
enum ScreenshotRoute {
    static var current: String? { UserDefaults.standard.string(forKey: "screenshotRoute") }

    /// Every route, tabs included, opens one screen directly.
    static var tab: Int? { nil }

    @MainActor @ViewBuilder static func screen(_ route: String) -> some View {
        if route == "root" {
            RootView()
        } else if route == "helper" {
            HelperChatView()
        } else if route == "tour" {
            RootView().onAppear { HelperCenter.shared.startTour() }
        } else if route == "home" {
            HomeView()
        } else if route == "calcs" {
            CalculatorsView()
        } else if route == "design" {
            FloorPlansView()
        } else if route == "projects" {
            ProjectsTabView()
        } else if route == "profile" {
            ProfileTabView()
        } else if route.hasPrefix("calc:"), let kind = CalculationKind(rawValue: String(route.dropFirst(5))) {
            CalculatorView(kind: kind)
        } else if route == "estimate" {
            HouseEstimateParamsView()
        } else if route == "assistant" {
            AIAssistantView(context: .general)
        } else if route == "about" {
            AboutAppView()
        } else if route == "photocount" {
            PhotoCountView()
        } else if route == "photodesign" {
            PhotoDesignView()
        } else if route == "docs" {
            DocEstimateHubView()
        } else if route == "docsnew" {
            DocEstimateNewView()
        } else if route == "splash" {
            SplashView(revealed: true)
        } else if route == "kp" || route == "kpco" {
            ProposalPreviewRoute(company: route == "kpco")
        } else if route == "billing" {
            BillingView()
        } else if route.hasPrefix("intro:"), let intro = FeatureIntro(rawValue: String(route.dropFirst(6))) {
            FeatureIntroSheet(intro: intro)
        } else {
            Text("Неизвестный маршрут: \(route)")
        }
    }
}
#endif
