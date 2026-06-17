import SwiftUI

/// Renders the read-back line plus the reaction cards. Shared by the app and
/// the share extension. Shows one fixed batch — no infinite scroll.
struct ResultsListView: View {
    let readBack: String
    let cards: [ReactionCard]
    var onShuffle: (UUID) -> Void
    var onReport: (UUID) -> Void
    var onFeedback: (UUID, FeedbackRating, [String]) -> Void

    var body: some View {
        VStack(spacing: 14) {
            if !readBack.isEmpty {
                Text("“\(readBack)”")
                    .font(.callout.italic())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(cards) { card in
                GifCardView(
                    card: card,
                    onShuffle: { onShuffle(card.id) },
                    onReport: { onReport(card.id) },
                    onFeedback: { rating, reasons in onFeedback(card.id, rating, reasons) }
                )
            }
        }
    }
}
