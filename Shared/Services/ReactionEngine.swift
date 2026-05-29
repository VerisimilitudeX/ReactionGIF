import Foundation
import UIKit

/// Drives the whole flow: screenshot -> AI plan -> GIF search -> shuffleable
/// cards. Supports infinite loading: an initial batch shows fast, then more
/// batches stream in as the user scrolls — guarded so we never fire overlapping
/// requests or run past a hard cap.
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
    @Published var isLoadingMore: Bool = false
    @Published var canLoadMore: Bool = false

    /// Hard ceiling so accidental infinite scrolls can't drain API credit.
    private let maxCards = 40
    private let initialBatchSize = 6
    private let nextBatchSize = 5

    /// Remembered so loadMore can re-issue the call with the same inputs.
    private var lastImage: UIImage?
    private var lastVibe: Vibe = .auto
    private var lastSafeMode: Bool = false

    private let openAI = OpenAIService()
    private let gifs = GifProviders()

    func generate(from image: UIImage, vibe: Vibe, safeMode: Bool) async {
        lastImage = image
        lastVibe = vibe
        lastSafeMode = safeMode

        phase = .reading
        readBack = ""
        cards = []
        canLoadMore = false

        do {
            let suggestion = try await openAI.suggestReactions(
                for: image, vibe: vibe, safeMode: safeMode,
                count: initialBatchSize, excludeLabels: []
            )
            readBack = suggestion.readBack
            phase = .searching

            let newCards = await buildCards(from: suggestion.options, usedTopURLs: [])
            guard !newCards.isEmpty else {
                phase = .failed("No GIFs found. Check your keys/backend or try a clearer screenshot.")
                return
            }

            cards = newCards
            phase = .done
            canLoadMore = cards.count < maxCards
            RecentsStore.shared.add(readBack: readBack, cards: newCards)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Ask the AI for the next batch of distinct bits. Safe to call repeatedly:
    /// no-ops while one is in flight, while we're still on the initial load, or
    /// once we've hit `maxCards`.
    func loadMore() async {
        guard let image = lastImage,
              phase == .done,
              !isLoadingMore,
              canLoadMore,
              cards.count < maxCards else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        let exclude = cards.map { $0.label }
        let remaining = max(0, maxCards - cards.count)
        let batch = min(nextBatchSize, remaining)
        guard batch > 0 else {
            canLoadMore = false
            return
        }

        do {
            let suggestion = try await openAI.suggestReactions(
                for: image, vibe: lastVibe, safeMode: lastSafeMode,
                count: batch, excludeLabels: exclude
            )
            let alreadyUsedURLs = Set(cards.compactMap { $0.current?.gifURL.absoluteString })
            let newCards = await buildCards(
                from: suggestion.options,
                usedTopURLs: alreadyUsedURLs,
                excludeLabels: Set(exclude)
            )
            if newCards.isEmpty {
                // Model couldn't find anything new — stop asking.
                canLoadMore = false
                return
            }
            cards.append(contentsOf: newCards)
            canLoadMore = cards.count < maxCards
        } catch {
            // Don't fail the whole screen for a paging error — just stop paging.
            canLoadMore = false
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

    // MARK: - Private

    private func buildCards(
        from options: [ReactionSuggestion.Option],
        usedTopURLs initialUsed: Set<String>,
        excludeLabels: Set<String> = []
    ) async -> [ReactionCard] {
        let reported = ReportStore.shared.reportedURLs
        var newCards: [ReactionCard] = []
        var usedTopURLs = initialUsed

        for option in options {
            if excludeLabels.contains(option.label) { continue }
            var pool = await gifs.search(option.searchQuery, safeMode: lastSafeMode)
            pool.removeAll { reported.contains($0.gifURL.absoluteString) }

            if let freshIndex = pool.firstIndex(where: { !usedTopURLs.contains($0.gifURL.absoluteString) }) {
                pool.swapAt(0, freshIndex)
            }
            guard let top = pool.first else { continue }
            usedTopURLs.insert(top.gifURL.absoluteString)

            newCards.append(ReactionCard(label: option.label, why: option.why, candidates: pool))
        }
        return newCards
    }
}
