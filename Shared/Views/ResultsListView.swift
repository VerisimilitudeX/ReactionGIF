import SwiftUI

/// Renders the read-back line plus the reaction cards. Shared by the app and
/// the share extension. When the user scrolls near the bottom, asks the engine
/// for more — guarded inside the engine so this is safe to fire repeatedly.
struct ResultsListView: View {
    let readBack: String
    let cards: [ReactionCard]
    var onShuffle: (UUID) -> Void
    var onReport: (UUID) -> Void
    var isLoadingMore: Bool = false
    var canLoadMore: Bool = false
    var onLoadMore: (() -> Void)? = nil

    /// When the card at (count - prefetchOffset) appears, kick off the next
    /// batch so it's ready by the time the user reaches the bottom.
    private let prefetchOffset = 3

    var body: some View {
        VStack(spacing: 14) {
            if !readBack.isEmpty {
                Text("“\(readBack)”")
                    .font(.callout.italic())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                GifCardView(
                    card: card,
                    onShuffle: { onShuffle(card.id) },
                    onReport: { onReport(card.id) }
                )
                .onAppear {
                    guard let onLoadMore,
                          canLoadMore,
                          !isLoadingMore,
                          index >= cards.count - prefetchOffset else { return }
                    onLoadMore()
                }
            }

            if isLoadingMore {
                ProgressView("Finding more…")
                    .padding(.vertical, 8)
            }
        }
    }
}
