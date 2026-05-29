import UIKit

enum GifActions {
    /// Downloads the GIF and copies it to the clipboard so it can be pasted
    /// straight into iMessage, WhatsApp, etc.
    static func copyToPasteboard(_ url: URL) async -> Bool {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return false }
        await MainActor.run {
            UIPasteboard.general.setData(data, forPasteboardType: "com.compuserve.gif")
        }
        return true
    }
}

enum Haptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
