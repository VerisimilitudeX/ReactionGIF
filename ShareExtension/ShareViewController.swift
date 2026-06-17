import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Principal class for the share extension. Pulls the shared image(s) out of the
/// extension context and hands them to a SwiftUI view that reuses the app's engine.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        loadSharedImages { [weak self] images in
            DispatchQueue.main.async {
                guard let self else { return }
                if images.isEmpty {
                    self.complete()
                } else {
                    self.present(images: images)
                }
            }
        }
    }

    private func present(images: [UIImage]) {
        let root = ShareRootView(images: images) { [weak self] in self?.complete() }
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// Loads every shared image attachment, preserving order.
    private func loadSharedImages(completion: @escaping ([UIImage]) -> Void) {
        let imageType = UTType.image.identifier
        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
            .compactMap { $0.attachments }
            .flatMap { $0 }
            .filter { $0.hasItemConformingToTypeIdentifier(imageType) } ?? []

        guard !providers.isEmpty else { return completion([]) }

        var results = [UIImage?](repeating: nil, count: providers.count)
        let group = DispatchGroup()
        for (index, provider) in providers.enumerated() {
            group.enter()
            provider.loadItem(forTypeIdentifier: imageType, options: nil) { value, _ in
                results[index] = Self.image(from: value)
                group.leave()
            }
        }
        group.notify(queue: .main) {
            completion(results.compactMap { $0 })
        }
    }

    private static func image(from value: Any?) -> UIImage? {
        if let image = value as? UIImage { return image }
        if let url = value as? URL, let data = try? Data(contentsOf: url) { return UIImage(data: data) }
        if let data = value as? Data { return UIImage(data: data) }
        return nil
    }
}
