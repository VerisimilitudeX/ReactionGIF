import Foundation

/// A single GIF returned by a provider (or the backend proxy).
struct GifCandidate: Codable, Identifiable {
    var id: String { gifURL.absoluteString }
    let provider: String
    let gifURL: URL
    let previewURL: URL?
    let title: String

    enum CodingKeys: String, CodingKey {
        case provider, title
        case gifURL = "gif"
        case previewURL = "preview"
    }
}
