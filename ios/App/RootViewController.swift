import UIKit

/// Holds either the first-launch screen (where does your app live?) or the app itself.
final class RootViewController: UIViewController {
    private var current: UIViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppSettings.startBackground
        if ProcessInfo.processInfo.arguments.contains("-GymDemo") {
            // UI checks in CI: the native parts on a test page
            swap(to: WebViewController(demoHTML: DemoPage.html))
        } else if let url = AppSettings.artifactURL {
            showWeb(url)
        } else {
            showSetup(cancellable: false)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(onShake), name: .gymShake, object: nil)
    }

    override var childForStatusBarStyle: UIViewController? { current }

    private func showSetup(cancellable: Bool) {
        let setup = SetupViewController()
        setup.initialText = AppSettings.artifactURL?.absoluteString
        setup.onOpen = { [weak self] url in
            AppSettings.artifactURL = url
            self?.showWeb(url)
        }
        if cancellable, let url = AppSettings.artifactURL {
            setup.onCancel = { [weak self] in self?.showWeb(url) }
        }
        swap(to: setup)
    }

    private func showWeb(_ url: URL) {
        let web = WebViewController(url: url)
        web.onChangeLink = { [weak self] in self?.showSetup(cancellable: true) }
        swap(to: web)
    }

    private func swap(to next: UIViewController) {
        if let old = current {
            old.willMove(toParent: nil)
            old.view.removeFromSuperview()
            old.removeFromParent()
        }
        UIApplication.shared.isIdleTimerDisabled = false
        addChild(next)
        next.view.frame = view.bounds
        next.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(next.view)
        next.didMove(toParent: self)
        current = next
        setNeedsStatusBarAppearanceUpdate()
    }

    @objc private func onShake() {
        (current as? WebViewController)?.showAppMenu()
    }
}
