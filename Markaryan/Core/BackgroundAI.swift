import Foundation
import UIKit
import UserNotifications

/// Long AI jobs (renders, design concepts) run in a background URLSession: iOS keeps the transfer going
/// while the app is minimised or even unloaded, wakes the app when the server answers and the app posts
/// a notification «готово» or «не получилось». Short helper answers do not need this.
final class BackgroundAI: NSObject, URLSessionDataDelegate {
    static let shared = BackgroundAI()
    static let identifier = "smetapro.background-ai"

    /// Set by the app delegate when iOS relaunches the app for finished transfers.
    var systemCompletion: (() -> Void)?

    private struct Job {
        var title: String
        var data = Data()
        var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
    }
    private var jobs: [Int: Job] = [:]
    private let lock = NSLock()

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.timeoutIntervalForRequest = 330
        configuration.timeoutIntervalForResource = 900
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    /// Wakes the session up after a relaunch, so finished transfers are delivered.
    func reconnect() { _ = session }

    /// Sends the request through the background session; `title` names the job in the notification.
    func send(_ request: URLRequest, title: String) async throws -> (Data, HTTPURLResponse) {
        Self.askForNotificationsOnce()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ai-\(UUID().uuidString).json")
        try (request.httpBody ?? Data()).write(to: file)
        var upload = request
        upload.httpBody = nil
        return try await withCheckedThrowingContinuation { continuation in
            let task = session.uploadTask(with: upload, fromFile: file)
            lock.lock(); jobs[task.taskIdentifier] = Job(title: title, continuation: continuation); lock.unlock()
            task.resume()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock(); jobs[dataTask.taskIdentifier]?.data.append(data); lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let job = jobs.removeValue(forKey: task.taskIdentifier); lock.unlock()
        let http = task.response as? HTTPURLResponse
        let ok = error == nil && http.map { (200...299).contains($0.statusCode) } == true
        let title = job?.title ?? "Задача ИИ"
        // Long polls of a running job («смета по документам»): only the real end is worth a notification.
        let body = job.map { String(decoding: $0.data.prefix(400), as: UTF8.self) } ?? ""
        let isPoll = task.originalRequest?.url?.path.hasSuffix("/wait") == true
        let stillRunning = body.contains("\"status\":\"running\"")
        let failedJob = body.contains("\"status\":\"failed\"")
        if isPoll && (stillRunning || !ok) { return finish(job, task: task, error: error, http: http) }
        let success = ok && !failedJob
        Task { @MainActor in
            // Only when the person is not looking at the app: in the foreground the screen shows the result itself.
            if UIApplication.shared.applicationState != .active {
                Self.notify(title: success ? "\(title): готово" : "\(title): не получилось",
                            body: success ? "Откройте приложение, чтобы посмотреть результат." : "Откройте приложение — помощник подскажет, что делать.")
            }
        }
        finish(job, task: task, error: error, http: http)
    }

    private func finish(_ job: Job?, task: URLSessionTask, error: Error?, http: HTTPURLResponse?) {
        guard let continuation = job?.continuation else { return }
        if let error { continuation.resume(throwing: error) }
        else if let http { continuation.resume(returning: (job?.data ?? Data(), http)) }
        else { continuation.resume(throwing: URLError(.badServerResponse)) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { self.systemCompletion?(); self.systemCompletion = nil }
    }

    // MARK: Notifications

    private static var asked = false
    static func askForNotificationsOnce() {
        guard !asked else { return }
        asked = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

/// Hooks the background session into the app life cycle and shows notifications over the open app.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        BackgroundAI.shared.reconnect()
        UIWindow.appearance().overrideUserInterfaceStyle = .light
        AppAppearance.apply()
        // The design is light: keep every window, sheet and alert light even when the iPhone is in dark mode.
        NotificationCenter.default.addObserver(forName: UIWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            (note.object as? UIWindow)?.overrideUserInterfaceStyle = .light
        }
        return true
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == BackgroundAI.identifier else { completionHandler(); return }
        BackgroundAI.shared.systemCompletion = completionHandler
        BackgroundAI.shared.reconnect()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

/// One look for the system parts: navigation bars with serif titles on the ivory page, lists on the same page,
/// emerald segmented controls — so system screens do not look different from the app's own.
enum AppAppearance {
    static func apply() {
        let ink = UIColor(Theme.ink), page = UIColor(Theme.background), accent = UIColor(Theme.orange)
        func serif(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            return base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) } ?? base
        }
        let bar = UINavigationBarAppearance()
        bar.configureWithDefaultBackground()
        bar.backgroundColor = page.withAlphaComponent(0.94)
        bar.shadowColor = UIColor(red: 0.24, green: 0.20, blue: 0.12, alpha: 0.10)
        bar.titleTextAttributes = [.font: serif(17, .semibold), .foregroundColor: ink]
        bar.largeTitleTextAttributes = [.font: serif(32, .bold), .foregroundColor: ink]
        let edge = bar.copy()
        edge.configureWithTransparentBackground()
        edge.titleTextAttributes = bar.titleTextAttributes
        edge.largeTitleTextAttributes = bar.largeTitleTextAttributes
        UINavigationBar.appearance().standardAppearance = bar
        UINavigationBar.appearance().compactAppearance = bar
        UINavigationBar.appearance().scrollEdgeAppearance = edge
        UINavigationBar.appearance().tintColor = accent

        UICollectionView.appearance().backgroundColor = page
        UITableView.appearance().backgroundColor = page

        let segments = UISegmentedControl.appearance()
        segments.selectedSegmentTintColor = accent
        segments.backgroundColor = UIColor(Theme.panelRaised)
        segments.setTitleTextAttributes([.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 13, weight: .semibold)], for: .selected)
        segments.setTitleTextAttributes([.foregroundColor: ink, .font: UIFont.systemFont(ofSize: 13, weight: .medium)], for: .normal)
        UISwitch.appearance().onTintColor = accent
        UIPageControl.appearance().currentPageIndicatorTintColor = accent
        UIPageControl.appearance().pageIndicatorTintColor = UIColor(Theme.panelRaised)
    }
}
