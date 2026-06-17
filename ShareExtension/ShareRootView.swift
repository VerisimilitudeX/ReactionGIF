import SwiftUI

/// The share-sheet UI. Reuses the same engine and result cards as the main app,
/// so reacting to a screenshot never requires opening ReactionGIF.
struct ShareRootView: View {
    let images: [UIImage]
    var onClose: () -> Void

    @StateObject private var engine = ReactionEngine()
    @AppStorage("safeMode") private var safeMode = false
    @State private var vibe: Vibe = .auto

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    screenshots

                    VibePicker(selection: $vibe)
                        .onChange(of: vibe) { _, _ in run() }

                    statusSection
                }
                .padding()
            }
            .navigationTitle("ReactionGIF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { onClose() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        run()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(engine.phase == .reading || engine.phase == .searching)
                }
            }
        }
        .task { run() }
    }

    /// One screenshot shows large; multiple show as a horizontal strip.
    @ViewBuilder
    private var screenshots: some View {
        if images.count == 1, let image = images.first {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 170)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.2)))
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 110, height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2)))
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch engine.phase {
        case .reading:
            ProgressView("Reading the conversation…").padding(.top, 24)
        case .searching:
            ProgressView("Finding the perfect GIFs…").padding(.top, 24)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.red)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .done:
            ResultsListView(
                readBack: engine.readBack,
                cards: engine.cards,
                onShuffle: { engine.shuffle($0) },
                onReport: { id in
                    Haptics.warning()
                    engine.report(id)
                },
                onFeedback: { id, rating, reasons in
                    engine.recordFeedback(cardID: id, rating: rating, reasons: reasons)
                }
            )
        case .idle:
            EmptyView()
        }
    }

    private func run() {
        Task {
            await engine.generate(from: images, vibe: vibe, safeMode: safeMode)
            switch engine.phase {
            case .done: Haptics.success()
            case .failed: Haptics.warning()
            default: break
            }
        }
    }
}
