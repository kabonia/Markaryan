import SwiftUI
import WebKit

/// Публичная кадастровая карта Росреестра внутри приложения — человек сам находит участок и смотрит данные,
/// как в обычном браузере. Сертификату Минцифры доверяем только для nspd.gov.ru (как и в запросах).
struct NSPDMapSheet: View {
    let url: URL
    /// Кадастровый номер, если известен: уже скопирован — вставьте в поиск карты.
    var number: String?
    let onEnterData: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var loading = true
    @State private var failure: String?
    @State private var certificateProblem = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                NSPDWebView(url: url, loading: $loading, failure: $failure, certificateProblem: $certificateProblem).ignoresSafeArea(edges: .bottom)
                VStack(spacing: 8) {
                    if loading { ProgressView().padding(10).background(.ultraThinMaterial, in: Capsule()) }
                    if let number, !number.isEmpty {
                        Label("Номер \(number) скопирован — вставьте в поиск карты", systemImage: "doc.on.clipboard")
                            .font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    } else {
                        Label("Нажмите на свой участок — откроется карточка с площадью и ВРИ", systemImage: "hand.tap")
                            .font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    if let failure {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(failure, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Theme.danger)
                            if certificateProblem {
                                Text("1. Нажмите «Установить сертификат» — откроется страница Госуслуг.\n2. Скачайте «Сертификат для iOS» и разрешите загрузку профиля.\n3. Настройки → Основные → VPN и управление устройством → профиль Минцифры → «Установить».\n4. Настройки → Основные → Об этом устройстве → Доверие сертификатам → включите Russian Trusted Root CA.")
                                    .font(.caption2).foregroundStyle(Theme.ink)
                                Button { openURL(URL(string: "https://www.gosuslugi.ru/crt")!) } label: {
                                    SecondaryActionLabel(title: "Установить сертификат", icon: "checkmark.shield")
                                }
                                .buttonStyle(PremiumPressStyle())
                            }
                            Button { dismiss(); onEnterData() } label: { SecondaryActionLabel(title: "Ввести данные вручную", icon: "square.and.pencil") }
                                .buttonStyle(PremiumPressStyle())
                        }
                        .padding(12).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.top, 8)
            }
            .navigationTitle("Кадастровая карта")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ввести данные") { dismiss(); onEnterData() }.fontWeight(.semibold)
                }
            }
        }
    }
}

struct NSPDWebView: UIViewRepresentable {
    let url: URL
    @Binding var loading: Bool
    @Binding var failure: String?
    @Binding var certificateProblem: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view.navigationDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: NSPDWebView
        /// Почему сертификат не принят (для точной причины в сообщении).
        var trustProblem: String?
        init(_ parent: NSPDWebView) { self.parent = parent }

        /// Сертификат Минцифры — только для nspd.gov.ru. Асинхронный вариант: его iOS вызывает гарантированно
        /// (старый, с completionHandler, в новых SDK помечен @MainActor и при несовпадении молча не вызывался).
        func webView(_ webView: WKWebView, respondTo challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
            let space = challenge.protectionSpace
            guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust, let trust = space.serverTrust,
                  NSPDClient.isNSPD(space.host) else {
                return (.performDefaultHandling, nil)
            }
            if let problem = NSPDClient.evaluate(trust, host: space.host) {
                trustProblem = "\(space.host): \(problem)"
                return (.performDefaultHandling, nil)
            }
            trustProblem = nil
            return (.useCredential, URLCredential(trust: trust))
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.loading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.loading = false
            parent.failure = nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { report(error) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { report(error) }

        private func report(_ error: Error) {
            parent.loading = false
            if (error as NSError).code == NSURLErrorCancelled { return }
            let code = (error as NSError).code
            parent.certificateProblem = [NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasUnknownRoot,
                                         NSURLErrorServerCertificateNotYetValid, NSURLErrorSecureConnectionFailed].contains(code)
            parent.failure = parent.certificateProblem
                ? "Карта Росреестра не открылась: iPhone не доверяет сертификату Минцифры. Установите его — это официальный сертификат для госсайтов (как для Госуслуг и Сбербанка). [код \(code)\(trustProblem.map { "; \($0)" } ?? "")]"
                : "Карта не открылась: \(error.localizedDescription). Если включён VPN — выключите: карта работает только из России."
        }
    }
}
