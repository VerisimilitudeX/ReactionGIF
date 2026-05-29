import Foundation

struct RecentItem: Codable, Identifiable {
    let id: UUID
    let readBack: String
    let gifURLs: [URL]
    let date: Date
}

/// Keeps the last handful of reactions so users can re-grab a go-to GIF fast.
@MainActor
final class RecentsStore: ObservableObject {
    static let shared = RecentsStore()

    @Published private(set) var items: [RecentItem] = []

    private let key = "recent_reactions"
    private let limit = 12
    private let defaults = UserDefaults.standard

    private init() {
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([RecentItem].self, from: data) {
            items = decoded
        }
    }

    func add(readBack: String, cards: [ReactionCard]) {
        let urls = cards.compactMap { $0.current?.gifURL }
        guard !urls.isEmpty else { return }
        let item = RecentItem(id: UUID(), readBack: readBack, gifURLs: urls, date: Date())
        items.insert(item, at: 0)
        if items.count > limit { items = Array(items.prefix(limit)) }
        persist()
    }

    func clear() {
        items = []
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: key)
        }
    }
}
