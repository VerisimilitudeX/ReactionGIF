import Foundation

/// Remembers GIFs the user has reported so we never show them again.
/// Backs the content-reporting requirement for App Store Guideline 1.2.
final class ReportStore {
    static let shared = ReportStore()
    private init() {}

    private let key = "reported_gif_urls"
    private let defaults = UserDefaults.standard

    var reportedURLs: Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }

    func report(_ url: String) {
        var current = reportedURLs
        current.insert(url)
        defaults.set(Array(current), forKey: key)

        // Best-effort: tell the backend too, if one is configured.
        guard !AppConfig.backendBaseURL.isEmpty,
              let base = URL(string: AppConfig.backendBaseURL) else { return }
        var request = URLRequest(url: base.appendingPathComponent("report"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["gif": url])
        URLSession.shared.dataTask(with: request).resume()
    }
}
