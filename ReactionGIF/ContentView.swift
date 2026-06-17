import SwiftUI
import PhotosUI

/// The main-app home screen. Add one or more chat screenshots as context — pick
/// from Photos, take a photo, or paste from the clipboard — then it runs the same
/// engine and result cards as the share extension.
struct ContentView: View {
    @StateObject private var engine = ReactionEngine()
    @AppStorage("safeMode") private var safeMode = false
    @State private var vibe: Vibe = .auto

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var images: [UIImage] = []

    @State private var showCamera = false
    @State private var showPasteError = false
    @State private var showSettings = false

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    private var isBusy: Bool {
        engine.phase == .reading || engine.phase == .searching
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !images.isEmpty {
                        thumbnailStrip

                        VibePicker(selection: $vibe)
                            .onChange(of: vibe) { _, _ in rerunOnVibeChange() }
                    }

                    captureOptions

                    if images.isEmpty {
                        ContentUnavailableView(
                            "Drop in your screenshots",
                            systemImage: "wand.and.stars",
                            description: Text("Add one or more chat screenshots and ReactionGIF finds the perfect reaction.")
                        )
                        .padding(.top, 40)
                    } else {
                        Button {
                            Haptics.tap()
                            run()
                        } label: {
                            Label(engine.phase == .idle ? "Get reactions" : "Regenerate",
                                  systemImage: "sparkles")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Capsule().fill(Color.accentColor))
                                .foregroundStyle(Color.white)
                        }
                        .disabled(isBusy)

                        statusSection
                    }
                }
                .padding()
            }
            .navigationTitle("ReactionGIF")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await addPicked(items) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            ImagePicker(sourceType: .camera) { captured in
                images.append(captured)
            }
            .ignoresSafeArea()
        }
        .alert("Nothing to paste", isPresented: $showPasteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Copy a screenshot first, then tap Paste.")
        }
    }

    // MARK: - Screenshots

    /// Horizontal strip of added screenshots, each removable.
    private var thumbnailStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 110, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2)))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                remove(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.5))
                            }
                            .padding(4)
                        }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - Capture options

    /// Three ways to add context: Photos (multi-select), Camera, and Paste.
    private var captureOptions: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
                captureLabel("Photos", systemImage: "photo.on.rectangle")
            }

            if cameraAvailable {
                Button {
                    Haptics.tap()
                    showCamera = true
                } label: {
                    captureLabel("Camera", systemImage: "camera")
                }
            }

            Button {
                Haptics.tap()
                pasteFromClipboard()
            } label: {
                captureLabel("Paste", systemImage: "doc.on.clipboard")
            }
        }
    }

    private func captureLabel(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title3)
            Text(title)
                .font(.subheadline.weight(.medium))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
        .foregroundStyle(Color.accentColor)
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

    // MARK: - Input

    private func pasteFromClipboard() {
        if let pasted = UIPasteboard.general.images, !pasted.isEmpty {
            images.append(contentsOf: pasted)
        } else if let one = UIPasteboard.general.image {
            images.append(one)
        } else {
            showPasteError = true
        }
    }

    private func addPicked(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                images.append(uiImage)
            }
        }
        pickerItems = []
    }

    private func remove(at index: Int) {
        guard images.indices.contains(index) else { return }
        Haptics.tap()
        images.remove(at: index)
    }

    /// Re-run only if results are already showing, so changing the vibe refreshes
    /// them without firing before the user has tapped "Get reactions".
    private func rerunOnVibeChange() {
        guard !images.isEmpty, engine.phase != .idle else { return }
        run()
    }

    private func run() {
        guard !images.isEmpty else { return }
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
