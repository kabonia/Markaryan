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

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                NSPDWebView(url: url, loading: $loading, failure: $failure).ignoresSafeArea(edges: .bottom)
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
                        Label(failure, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Theme.danger)
                            .padding(10).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
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
        init(_ parent: NSPDWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                     completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            let space = challenge.protectionSpace
            guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust, let trust = space.serverTrust,
                  NSPDClient.isNSPD(space.host) else {
                completionHandler(.performDefaultHandling, nil)
                return
            }
            if NSPDClient.evaluate(trust, host: space.host) == nil {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
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
            parent.failure = "Карта не открылась: \(error.localizedDescription). Если включён VPN — выключите: карта работает только из России."
        }
    }
}
