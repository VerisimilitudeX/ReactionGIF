import SwiftUI
import PhotosUI

/// The main-app home screen. Lets the user pick a screenshot from their photo
/// library, then runs the same engine and result cards as the share extension.
struct ContentView: View {
    @StateObject private var engine = ReactionEngine()
    @AppStorage("safeMode") private var safeMode = false
    @State private var vibe: Vibe = .auto

    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.2)))

                        VibePicker(selection: $vibe)
                            .onChange(of: vibe) { _, _ in run() }
                    }

                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(image == nil ? "Pick a screenshot" : "Pick another",
                              systemImage: "photo.on.rectangle")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(Color.accentColor))
                            .foregroundStyle(Color.white)
                    }

                    if image != nil {
                        statusSection
                    } else {
                        ContentUnavailableView(
                            "Drop in a screenshot",
                            systemImage: "wand.and.stars",
                            description: Text("Pick a chat screenshot and ReactionGIF finds the perfect reaction.")
                        )
                        .padding(.top, 40)
                    }
                }
                .padding()
            }
            .navigationTitle("ReactionGIF")
        }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task { await loadImage(from: newItem) }
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
                isLoadingMore: engine.isLoadingMore,
                canLoadMore: engine.canLoadMore,
                onLoadMore: { Task { await engine.loadMore() } }
            )
        case .idle:
            EmptyView()
        }
    }

    private func loadImage(from item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data) else { return }
        image = uiImage
        run()
    }

    private func run() {
        guard let image else { return }
        Task {
            await engine.generate(from: image, vibe: vibe, safeMode: safeMode)
            switch engine.phase {
            case .done: Haptics.success()
            case .failed: Haptics.warning()
            default: break
            }
        }
    }
}
