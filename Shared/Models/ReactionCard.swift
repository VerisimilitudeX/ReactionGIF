import Foundation

/// One reaction shown to the user. Holds the whole pool of GIFs for its bit so
/// the user can shuffle through alternatives with no extra network calls.
struct ReactionCard: Identifiable {
    let id = UUID()
    let label: String
    let why: String
    var candidates: [GifCandidate]
    var index: Int = 0

    var current: GifCandidate? {
        candidates.indices.contains(index) ? candidates[index] : nil
    }
}
