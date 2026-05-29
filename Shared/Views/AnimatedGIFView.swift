import SwiftUI
import UIKit
import ImageIO

/// Downloads a GIF and plays it back with correct frame timing.
struct AnimatedGIFView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        load(into: imageView)
        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {}

    private func load(into imageView: UIImageView) {
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
            let image = UIImage.animatedGIF(from: data) ?? UIImage(data: data)
            await MainActor.run { imageView.image = image }
        }
    }
}

extension UIImage {
    /// Builds an animated `UIImage` from raw GIF data using ImageIO.
    static func animatedGIF(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let frameCount = CGImageSourceGetCount(source)

        guard frameCount > 1 else {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            return UIImage(cgImage: cgImage)
        }

        var frames: [UIImage] = []
        var totalDuration: Double = 0

        for index in 0..<frameCount {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(UIImage(cgImage: cgImage))
            totalDuration += frameDuration(at: index, source: source)
        }

        return UIImage.animatedImage(with: frames, duration: totalDuration)
    }

    private static func frameDuration(at index: Int, source: CGImageSource) -> Double {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any],
              let gifProperties = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any] else {
            return 0.1
        }
        let unclamped = gifProperties[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double
        let clamped = gifProperties[kCGImagePropertyGIFDelayTime as String] as? Double
        let duration = unclamped ?? clamped ?? 0.1
        // Browsers clamp very small delays; mirror that so playback isn't too fast.
        return duration < 0.02 ? 0.1 : duration
    }
}
