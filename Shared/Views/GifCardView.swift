import SwiftUI

/// One reaction card: animated GIF + why it lands + share / copy / shuffle /
/// report, plus a thumbs up/down so users can rate the pick.
struct GifCardView: View {
    let card: ReactionCard
    var onShuffle: () -> Void
    var onReport: () -> Void
    var onFeedback: (FeedbackRating, [String]) -> Void

    @State private var showShare = false
    @State private var toast: String?

    @State private var rating: FeedbackRating?
    @State private var showReasons = false
    @State private var recordedDown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let gif = card.current {
                header(provider: gif.provider)

                AnimatedGIFView(url: gif.gifURL)
                    .id(gif.gifURL)
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(alignment: .bottomTrailing) { toastView }

                Text(card.why)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                actionRow(gif: gif)

                Divider()

                feedbackRow
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))
        .sheet(isPresented: $showShare) {
            if let gif = card.current { ShareSheet(items: [gif.gifURL]) }
        }
    }

    private func header(provider: String) -> some View {
        HStack {
            Text(card.label)
                .font(.headline)
            Spacer()
            if card.candidates.count > 1 {
                Text("\(card.index + 1)/\(card.candidates.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(provider)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
        }
    }

    private func actionRow(gif: GifCandidate) -> some View {
        HStack(spacing: 10) {
            Button {
                Haptics.tap()
                showShare = true
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                copy(gif.gifURL)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)

            Button {
                Haptics.tap()
                onShuffle()
            } label: {
                Image(systemName: "shuffle")
            }
            .buttonStyle(.bordered)
            .disabled(card.candidates.count < 2)

            Menu {
                Button(role: .destructive) {
                    onReport()
                } label: {
                    Label("Report this GIF", systemImage: "flag")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
        }
    }

    /// Thumbs up/down. Down opens a short MCQ; up records immediately.
    private var feedbackRow: some View {
        HStack(spacing: 18) {
            Text("Good pick?")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                vote(.up)
            } label: {
                Image(systemName: rating == .up ? "hand.thumbsup.fill" : "hand.thumbsup")
            }
            .tint(rating == .up ? .green : .secondary)

            Button {
                vote(.down)
            } label: {
                Image(systemName: rating == .down ? "hand.thumbsdown.fill" : "hand.thumbsdown")
            }
            .tint(rating == .down ? .red : .secondary)
        }
        .font(.headline)
        .buttonStyle(.plain)
        .sheet(isPresented: $showReasons, onDismiss: {
            // Opened the reasons sheet but didn't submit — undo the thumb.
            if rating == .down && !recordedDown { rating = nil }
        }) {
            FeedbackReasonSheet { reasons in
                recordedDown = true
                onFeedback(.down, reasons)
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func vote(_ newRating: FeedbackRating) {
        Haptics.tap()
        rating = newRating
        if newRating == .up {
            onFeedback(.up, [])
        } else {
            recordedDown = false
            showReasons = true
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(8)
                .transition(.opacity)
        }
    }

    private func copy(_ url: URL) {
        Haptics.tap()
        Task {
            let ok = await GifActions.copyToPasteboard(url)
            await MainActor.run {
                withAnimation { toast = ok ? "Copied!" : "Copy failed" }
            }
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            await MainActor.run { withAnimation { toast = nil } }
        }
    }
}

/// Short MCQ shown after a thumbs-down: why didn't this pick land? Multi-select.
struct FeedbackReasonSheet: View {
    var onSubmit: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []

    private let reasons = [
        "Doesn't match the conversation",
        "Wrong vibe or tone",
        "GIF unrelated to the search",
        "Generic / overused",
        "Not actually funny",
        "Broken or low quality",
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(reasons, id: \.self) { reason in
                        Button {
                            if selected.contains(reason) {
                                selected.remove(reason)
                            } else {
                                selected.insert(reason)
                            }
                        } label: {
                            HStack {
                                Text(reason).foregroundStyle(.primary)
                                Spacer()
                                if selected.contains(reason) {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                } header: {
                    Text("What was off?")
                } footer: {
                    Text("Pick all that apply. Saved with the screenshot and the GIF to help improve results.")
                }
            }
            .navigationTitle("Why not?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Submit") {
                        onSubmit(Array(selected))
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Wraps the system share sheet so the user can drop the GIF into any app.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
