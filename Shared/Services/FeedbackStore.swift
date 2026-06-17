import Foundation
import UIKit

/// How the user rated a single GIF pick.
enum FeedbackRating: String, Codable {
    case up
    case down
}

/// One thumbs-up/down with the full context needed to diagnose *why* a pick was
/// good or bad: the original screenshot(s), the AI's read of the convo, the
/// search query it chose, and the GIF that came back. Exported as JSON.
struct FeedbackEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    let rating: FeedbackRating
    /// MCQ reasons the user picked for a thumbs-down (empty for thumbs-up).
    let reasons: [String]

    // What the user asked for
    let vibe: String
    let safeMode: Bool

    // What the AI understood + planned
    let readBack: String
    let cardLabel: String
    let cardWhy: String
    let searchQuery: String

    // Where this pick sat in the results (0 = first/top pick)
    let position: Int
    let totalCards: Int

    // The actual GIF shown
    let gifProvider: String
    let gifURL: String
    let gifTitle: String
    let candidateIndex: Int
    let candidateCount: Int

    // Downscaled JPEGs of the original screenshot(s), base64, in order
    let imagesBase64: [String]

    enum CodingKeys: String, CodingKey {
        case id, date, rating, reasons, vibe, safeMode, readBack, cardLabel
        case cardWhy, searchQuery, position, totalCards, gifProvider, gifURL
        case gifTitle, candidateIndex, candidateCount, imagesBase64
    }

    /// Legacy single-image key, kept so older saved files still load.
    private enum LegacyKeys: String, CodingKey {
        case imageBase64
    }
}

extension FeedbackEntry {
    /// Custom decode that accepts either the new `imagesBase64` array or the old
    /// single `imageBase64` string, so previously collected feedback isn't lost.
    /// Declared in an extension to preserve the synthesized memberwise init.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        rating = try container.decode(FeedbackRating.self, forKey: .rating)
        reasons = try container.decode([String].self, forKey: .reasons)
        vibe = try container.decode(String.self, forKey: .vibe)
        safeMode = try container.decode(Bool.self, forKey: .safeMode)
        readBack = try container.decode(String.self, forKey: .readBack)
        cardLabel = try container.decode(String.self, forKey: .cardLabel)
        cardWhy = try container.decode(String.self, forKey: .cardWhy)
        searchQuery = try container.decode(String.self, forKey: .searchQuery)
        position = try container.decode(Int.self, forKey: .position)
        totalCards = try container.decode(Int.self, forKey: .totalCards)
        gifProvider = try container.decode(String.self, forKey: .gifProvider)
        gifURL = try container.decode(String.self, forKey: .gifURL)
        gifTitle = try container.decode(String.self, forKey: .gifTitle)
        candidateIndex = try container.decode(Int.self, forKey: .candidateIndex)
        candidateCount = try container.decode(Int.self, forKey: .candidateCount)

        if let images = try container.decodeIfPresent([String].self, forKey: .imagesBase64) {
            imagesBase64 = images
        } else {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            if let single = try legacy.decodeIfPresent(String.self, forKey: .imageBase64) {
                imagesBase64 = [single]
            } else {
                imagesBase64 = []
            }
        }
    }
}

/// Persists user feedback to a JSON file in Documents and can hand back an
/// export URL for the system share sheet. Lives in the shared layer so both the
/// app and the share extension can record (each in its own container).
@MainActor
final class FeedbackStore: ObservableObject {
    static let shared = FeedbackStore()

    @Published private(set) var entries: [FeedbackEntry] = []

    private let fileURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("reactiongif-feedback.json")
        load()
    }

    var count: Int { entries.count }

    func add(_ entry: FeedbackEntry) {
        entries.insert(entry, at: 0)
        persist()
    }

    func clear() {
        entries = []
        persist()
    }

    /// Writes the collected feedback to a temp file and returns its URL so the
    /// system share sheet can export it.
    func exportURL() -> URL? {
        guard !entries.isEmpty, let data = try? Self.encoder.encode(entries) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("reactiongif-feedback.json")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? Self.decoder.decode([FeedbackEntry].self, from: data) else { return }
        entries = decoded
    }

    private func persist() {
        guard let data = try? Self.encoder.encode(entries) else { return }
        try? data.write(to: fileURL)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension UIImage {
    /// A small JPEG (base64) suitable for embedding in exported feedback. Keeps
    /// the file shareable while still showing what the original screenshot was.
    func downscaledJPEGBase64(maxDimension: CGFloat = 640, quality: CGFloat = 0.5) -> String? {
        let longest = max(size.width, size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let scaled = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        return scaled.jpegData(compressionQuality: quality)?.base64EncodedString()
    }
}
