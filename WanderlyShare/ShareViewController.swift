import SwiftUI

#if os(iOS)
import UIKit

final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let composer = ShareComposeView(
            model: model,
            onDone: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) },
            onCancel: { [weak self] in self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled)) })
        let host = UIHostingController(rootView: composer)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        Task { await model.load(from: extensionContext) }
    }
}
#else
import AppKit

final class ShareViewController: NSViewController {
    private let model = ShareModel()

    override func loadView() {
        let composer = ShareComposeView(
            model: model,
            onDone: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) },
            onCancel: { [weak self] in self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled)) })
        let host = NSHostingView(rootView: composer)
        host.frame = NSRect(x: 0, y: 0, width: 440, height: 380)
        view = host
        preferredContentSize = host.frame.size
        Task { await model.load(from: extensionContext) }
    }
}
#endif
