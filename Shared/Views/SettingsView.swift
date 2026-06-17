import SwiftUI

/// A file to share, wrapped so `.sheet(item:)` can drive presentation reliably
/// (the value is guaranteed non-nil when the sheet builds).
private struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// App settings: content safety toggle plus the feedback collected from
/// thumbs up/down, which can be exported as a single JSON file to diagnose
/// why results land or miss.
struct SettingsView: View {
    @AppStorage("safeMode") private var safeMode = false
    @ObservedObject private var feedback = FeedbackStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var exportFile: ExportFile?

    var body: some View {
        NavigationStack {
            Form {
                Section("Content") {
                    Toggle("Safe mode (G-rated)", isOn: $safeMode)
                }

                Section {
                    LabeledContent("Collected", value: "\(feedback.count)")

                    Button {
                        if let url = feedback.exportURL() {
                            exportFile = ExportFile(url: url)
                        }
                    } label: {
                        Label("Export feedback", systemImage: "square.and.arrow.up")
                    }
                    .disabled(feedback.count == 0)

                    Button(role: .destructive) {
                        feedback.clear()
                    } label: {
                        Label("Clear feedback", systemImage: "trash")
                    }
                    .disabled(feedback.count == 0)
                } header: {
                    Text("Feedback")
                } footer: {
                    Text("Every thumbs up/down is saved with the screenshot, the AI's pick, the search query, and your reason. Export the file and share it to help track down why results miss.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $exportFile) { file in
                ShareSheet(items: [file.url])
            }
        }
    }
}
