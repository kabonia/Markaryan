import SwiftUI

#if DEBUG
/// Debug-only: opens one screen straight away for automated screenshots in CI.
/// Launch with `-screenshotRoute <route>` (and `-onboardingCompleted YES`).
enum ScreenshotRoute {
    static var current: String? { UserDefaults.standard.string(forKey: "screenshotRoute") }

    /// Tab routes switch the tab bar; other routes open a single screen.
    static var tab: Int? { ["home": 0, "calcs": 1, "design": 2, "projects": 3, "profile": 4][current ?? ""] }

    @MainActor @ViewBuilder static func screen(_ route: String) -> some View {
        if route.hasPrefix("calc:"), let kind = CalculationKind(rawValue: String(route.dropFirst(5))) {
            CalculatorView(kind: kind)
        } else if route == "estimate" {
            HouseEstimateView(kind: .house)
        } else if route == "assistant" {
            AIAssistantView(context: .general)
        } else if route == "about" {
            AboutAppView()
        } else if route == "photocount" {
            PhotoCountView()
        } else if route == "photodesign" {
            PhotoDesignView()
        } else {
            Text("Неизвестный маршрут: \(route)")
        }
    }
}
#endif
