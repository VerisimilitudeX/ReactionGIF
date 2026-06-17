import Foundation
import UIKit

/// Drives the whole flow: screenshot(s) -> AI plan -> GIF search -> shuffleable
/// cards. Returns a single batch of reactions (no infinite scroll); the model
/// decides how many to return within the allowed range.
@MainActor
final class ReactionEngine: ObservableObject {
    enum Phase: Equatable {
        case idle
        case reading
        case searching
        case done
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var readBack: String = ""
    @Published var cards: [ReactionCard] = []

    /// The model picks how many reactions to return within this range — only as
    /// many as genuinely land. TODO: once enough feedback is collected, use the
    /// thumbs up/down scoring to tune this range (and per-vibe sweet spots).
    private let minResults = 5
    private let maxResults = 10

    /// Remembered so feedback can capture the exact inputs behind a pick.
    private var lastImages: [UIImage] = []
    private var lastVibe: Vibe = .auto
    private var lastSafeMode: Bool = false

    private let openAI = OpenAIService()
    private let gifs = GifProviders()

    func generate(from images: [UIImage], vibe: Vibe, safeMode: Bool) async {
        guard !images.isEmpty else { return }
        lastImages = images
        lastVibe = vibe
        lastSafeMode = safeMode

        phase = .reading
        readBack = ""
        cards = []

        do {
            let suggestion = try await openAI.suggestReactions(
                for: images, vibe: vibe, safeMode: safeMode,
                minCount: minResults, maxCount: maxResults
            )
            readBack = suggestion.readBack
            phase = .searching

            let (newCards, rateLimited) = await buildCards(from: suggestion.options, usedTopURLs: [])
            guard !newCards.isEmpty else {
                if rateLimited {
                    phase = .failed("The GIF service is rate-limited right now. Wait a minute and try again (or add a Tenor key as a backup).")
                } else {
                    phase = .failed("No GIFs found. Try a clearer screenshot, or check your keys/backend.")
                }
                return
            }

            cards = newCards
            phase = .done
            RecentsStore.shared.add(readBack: readBack, cards: newCards)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Cycle a card to its next alternative GIF (no network call).
    func shuffle(_ cardID: UUID) {
        guard let position = cards.firstIndex(where: { $0.id == cardID }) else { return }
        guard cards[position].candidates.count > 1 else { return }
        cards[position].index = (cards[position].index + 1) % cards[position].candidates.count
    }

    /// Report the currently shown GIF: remember it, drop it, and advance.
    func report(_ cardID: UUID) {
        guard let position = cards.firstIndex(where: { $0.id == cardID }) else { return }
        var card = cards[position]
        if let current = card.current {
            ReportStore.shared.report(current.gifURL.absoluteString)
            card.candidates.remove(at: card.index)
        }
        if card.index >= card.candidates.count { card.index = 0 }

        if card.candidates.isEmpty {
            cards.remove(at: position)
        } else {
            cards[position] = card
        }
    }

    /// Save a thumbs up/down for a card along with the full context behind the
    /// pick (screenshots, AI read, search query, GIF, position). Patterns across
    /// these entries are what reveal why results land or miss — exported in
    /// Settings.
    func recordFeedback(cardID: UUID, rating: FeedbackRating, reasons: [String]) {
        guard let position = cards.firstIndex(where: { $0.id == cardID }) else { return }
        let card = cards[position]
        guard let gif = card.current else { return }

        let entry = FeedbackEntry(
            id: UUID(),
            date: Date(),
            rating: rating,
            reasons: reasons,
            vibe: lastVibe.rawValue,
            safeMode: lastSafeMode,
            readBack: readBack,
            cardLabel: card.label,
            cardWhy: card.why,
            searchQuery: card.searchQuery,
            position: position,
            totalCards: cards.count,
            gifProvider: gif.provider,
            gifURL: gif.gifURL.absoluteString,
            gifTitle: gif.title,
            candidateIndex: card.index,
            candidateCount: card.candidates.count,
            imagesBase64: lastImages.compactMap { $0.downscaledJPEGBase64() }
        )
        FeedbackStore.shared.add(entry)
    }

    // MARK: - Private

    /// Builds cards for each option. Returns the cards plus whether any provider
    /// reported a rate limit (so the caller can show an accurate message).
    private func buildCards(
        from options: [ReactionSuggestion.Option],
        usedTopURLs initialUsed: Set<String>,
        excludeLabels: Set<String> = []
    ) async -> (cards: [ReactionCard], rateLimited: Bool) {
        let reported = ReportStore.shared.reportedURLs
        var newCards: [ReactionCard] = []
        var usedTopURLs = initialUsed
        var rateLimited = false

        for option in options {
            if excludeLabels.contains(option.label) { continue }
            let result = await gifs.search(option.searchQuery, safeMode: lastSafeMode)
            if result.rateLimited { rateLimited = true }

            var pool = result.candidates
            pool.removeAll { reported.contains($0.gifURL.absoluteString) }

            if let freshIndex = pool.firstIndex(where: { !usedTopURLs.contains($0.gifURL.absoluteString) }) {
                pool.swapAt(0, freshIndex)
            }
            guard let top = pool.first else { continue }
            usedTopURLs.insert(top.gifURL.absoluteString)

            newCards.append(ReactionCard(label: option.label, why: option.why, searchQuery: option.searchQuery, candidates: pool))
        }
        return (newCards, rateLimited)
    }
}
