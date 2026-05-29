import Foundation

/// The structured plan returned by the AI after looking at the chat screenshot.
struct ReactionSuggestion: Codable {
    struct Option: Codable, Identifiable {
        var id = UUID()
        let label: String
        let searchQuery: String
        let why: String

        // `id` is intentionally omitted so it is not expected in the JSON.
        enum CodingKeys: String, CodingKey {
            case label
            case searchQuery = "search_query"
            case why
        }
    }

    let readBack: String
    let options: [Option]

    enum CodingKeys: String, CodingKey {
        case readBack = "read_back"
        case options
    }
}
