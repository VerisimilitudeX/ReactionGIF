import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Principal class for the share extension. Pulls the shared image out of the
/// extension context and hands it to a SwiftUI view that reuses the app's engine.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        loadSharedImage { [weak self] image in
            DispatchQueue.main.async {
                guard let self else { return }
                if let image {
                    self.present(image: image)
                } else {
                    self.complete()
                }
            }
        }
    }

    private func present(image: UIImage) {
        let root = ShareRootView(image: image) { [weak self] in self?.complete() }
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

    private func loadSharedImage(completion: @escaping (UIImage?) -> Void) {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let providers = item.attachments else {
            return completion(nil)
        }
        let imageType = UTType.image.identifier
        for provider in providers where provider.hasItemConformingToTypeIdentifier(imageType) {
            provider.loadItem(forTypeIdentifier: imageType, options: nil) { value, _ in
                completion(Self.image(from: value))
            }
            return
        }
        completion(nil)
    }

    private static func image(from value: Any?) -> UIImage? {
        if let image = value as? UIImage { return image }
        if let url = value as? URL, let data = try? Data(contentsOf: url) { return UIImage(data: data) }
        if let data = value as? Data { return UIImage(data: data) }
        return nil
    }
}
