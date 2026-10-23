import UIKit
import WebKit

/// The app itself: your Gym Tracker page in Claude, full screen, plus what only a real app can do —
/// the workout on the Lock Screen and in the Dynamic Island, real haptics, the screen kept awake.
///
/// The page talks to the app through `window.webkit.messageHandlers.gymNative.postMessage({type, …})`
/// and gets answers through `window.__gymNative({…})`.
final class WebViewController: UIViewController {
    var onChangeLink: (() -> Void)?

    private let startURL: URL
    private var webView: WKWebView!
    private var topSafe: NSLayoutConstraint!
    private var topFull: NSLayoutConstraint!
    private var bottomSafe: NSLayoutConstraint!
    private var bottomFull: NSLayoutConstraint!
    private let spinner = UIActivityIndicatorView(style: .large)
    private var errorView: UIView?
    private weak var popup: PopupViewController?

    /// The frame Gym Tracker runs in. It says hello once it has loaded.
    private var appFrame: WKFrameInfo?
    /// Gym Tracker is the whole page (not inside Claude's page).
    private var appIsWholePage = false
    /// Only the app on screen; Claude's page around it is hidden.
    private var focused = false
    private var focusTask: Task<Void, Never>?
    private var revealTask: Task<Void, Never>?
    private var pageDark = true
    private var pageBackground = AppSettings.pageBackground ?? "#000000"
    /// The app's colours for the wheels' panel: sheet, label, label-2, tint.
    private var pageColors: [String: String] = [:]
    /// The phone's own wheels, docked at the bottom when the page asks for them.
    private var pickerPanel: PickerPanel?
    /// Press-and-hold menus the page has described, by id, and where their buttons are on screen right now.
    private var holdMenus: [String: [String: Any]] = [:]
    private var holdZones: [String: HoldZone] = [:]
    /// The button whose menu is up (or coming up): its place when the press began.
    private var activeHold: (id: String, zone: HoldZone)?
    /// A test page instead of the app (UI checks in CI: launch argument -GymDemo).
    private var demoHTML: String?

    init(url: URL) {
        startURL = url
        super.init(nibName: nil, bundle: nil)
    }

    /// The app's native parts on a small test page, for the UI checks in CI.
    convenience init(demoHTML: String) {
        self.init(url: URL(string: "https://gym-demo.local/")!)
        self.demoHTML = demoHTML
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppSettings.startBackground
        pageDark = (view.backgroundColor?.luminance ?? 0) < 0.5

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        // look like Safari: some sign-in pages refuse browsers built into apps
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        config.applicationNameForUserAgent = "Version/\(major).0 Mobile/15E148 Safari/604.1"

        let scripts = WKUserContentController()
        scripts.add(ScriptHandlerProxy(self), name: "gymNative")
        scripts.addUserScript(WKUserScript(source: PageScripts.focus, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        config.userContentController = scripts

        let web = WKWebView(frame: .zero, configuration: config)
        web.translatesAutoresizingMaskIntoConstraints = false
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = false
        web.allowsLinkPreview = false
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.isInspectable = true
        web.alpha = 0
        view.addSubview(web)
        webView = web
        // press and hold on the page's buttons with a menu: the phone's own context menu (see HoldZone)
        web.addInteraction(UIContextMenuInteraction(delegate: self))

        topSafe = web.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        topFull = web.topAnchor.constraint(equalTo: view.topAnchor)
        bottomSafe = web.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        bottomFull = web.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        NSLayoutConstraint.activate([
            web.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topSafe,
            bottomSafe,
        ])

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = .gray
        spinner.hidesWhenStopped = true
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        spinner.startAnimating()

        if let demoHTML {
            web.loadHTMLString(demoHTML, baseURL: startURL)
        } else {
            web.load(URLRequest(url: startURL))
        }
    }

    // MARK: - Showing the page

    /// While Gym Tracker loads inside Claude's page, the screen stays on the app's background with a spinner,
    /// so Claude's page doesn't flash before only the app is shown.
    private func hidePage(for seconds: Double) {
        webView.alpha = 0
        spinner.startAnimating()
        revealTask?.cancel()
        revealTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.revealPage()
        }
    }

    private func revealPage() {
        revealTask?.cancel()
        revealTask = nil
        spinner.stopAnimating()
        guard webView.alpha < 1 else { return }
        UIView.animate(withDuration: 0.2) { self.webView.alpha = 1 }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        guard focused || appIsWholePage else { return .default }
        return pageDark ? .lightContent : .darkContent
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        if focused { sendToApp(["type": "insets", "insets": insetsPayload()]) }
    }

    // MARK: - Full screen

    private func setFullScreen(_ full: Bool) {
        NSLayoutConstraint.deactivate(full ? [topSafe, bottomSafe] : [topFull, bottomFull])
        NSLayoutConstraint.activate(full ? [topFull, bottomFull] : [topSafe, bottomSafe])
        view.layoutIfNeeded()
    }

    private func focusIfWanted() {
        focusTask?.cancel()
        focusTask = nil
        guard AppSettings.focusMode, !focused, !appIsWholePage, appFrame != nil else { return }
        setFocus(true)
    }

    /// Lays the app over the whole screen (or puts Claude's page back) and tells the app how much room
    /// the status bar and the home indicator take.
    private func setFocus(_ on: Bool) {
        if on { setFullScreen(true) }
        let js = "window.__gymFocus ? window.__gymFocus(\(on ? "true" : "false"), \(Self.jsString(pageBackground))) : false"
        webView.evaluateJavaScript(js, in: nil, in: .page) { [weak self] result in
            guard let self else { return }
            var found = false
            if case .success(let value) = result, let number = value as? NSNumber {
                found = number.boolValue
            }
            let nowOn = on && found
            self.focused = nowOn
            if !nowOn { self.setFullScreen(false) }
            self.webView.scrollView.bounces = !nowOn
            self.sendToApp(["type": "focus", "focus": nowOn, "insets": nowOn ? self.insetsPayload() : NSNull()])
            self.setNeedsStatusBarAppearanceUpdate()
            self.revealPage()
        }
    }

    private func insetsPayload() -> [String: Double] {
        let insets = view.safeAreaInsets
        return ["top": Double(insets.top), "bottom": Double(insets.bottom), "left": Double(insets.left), "right": Double(insets.right)]
    }

    // MARK: - Talking to the page

    private func sendToApp(_ payload: [String: Any]) {
        guard let frame = appFrame,
              JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.__gymNative ? window.__gymNative(\(json)) : false", in: frame, in: .page, completionHandler: nil)
    }

    private static func jsString(_ text: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: text, options: .fragmentsAllowed),
              let json = String(data: data, encoding: .utf8) else { return "\"\"" }
        return json
    }

    private func applyLook(_ body: [String: Any]) {
        for key in ["sheet", "label", "label2", "tint"] {
            if let value = body[key] as? String { pageColors[key] = value }
        }
        guard let hex = body["bg"] as? String, let color = UIColor(hexString: hex) else { return }
        pageBackground = hex
        AppSettings.pageBackground = hex
        view.backgroundColor = color
        errorView?.backgroundColor = color
        pageDark = (body["dark"] as? Bool) ?? (color.luminance < 0.5)
        setNeedsStatusBarAppearanceUpdate()
        styleWheels()
        if focused {
            webView.evaluateJavaScript("window.__gymFocusBg ? window.__gymFocusBg(\(Self.jsString(hex))) : false", in: nil, in: .page, completionHandler: nil)
        }
    }

    // MARK: - The phone's own wheels

    private func wheels() -> PickerPanel {
        if let panel = pickerPanel { return panel }
        let panel = PickerPanel()
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.isHidden = true
        view.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        panel.onEvent = { [weak self] message in self?.sendToApp(message) }
        pickerPanel = panel
        styleWheels()
        return panel
    }

    private func styleWheels() {
        guard let panel = pickerPanel else { return }
        let color = { (key: String) in self.pageColors[key].flatMap { UIColor(hexString: $0) } }
        panel.style(sheet: color("sheet"), label: color("label"), secondary: color("label2"), tint: color("tint"), dark: pageDark)
    }

    /// `{type: "picker", id, title, sub, done, cols}` brings the wheels up (or changes what they show);
    /// `{type: "picker", close: true}` puts them away.
    private func handlePicker(_ body: [String: Any]) {
        if (body["close"] as? Bool) == true {
            pickerPanel?.hide(notify: false)
            return
        }
        guard let id = body["id"] as? String, let raw = body["cols"] as? [[String: Any]] else { return }
        let columns = raw.compactMap(PickerPanel.Column.init(json:))
        guard !columns.isEmpty else { return }
        let panel = wheels()
        view.bringSubviewToFront(panel)
        if let errorView { view.bringSubviewToFront(errorView) }
        panel.show(id: id, title: body["title"] as? String ?? "", sub: body["sub"] as? String ?? "",
                   done: body["done"] as? String ?? "Готово", columns: columns)
    }

    // MARK: - Press-and-hold menus

    static let holdScheme = "gymtracker"

    /// The menu the page described for this button, as the phone's own menu; a pick goes back to the page.
    fileprivate func holdMenu(id: String) -> UIMenu? {
        guard let def = holdMenus[id] else { return nil }
        let items = def["items"] as? [[String: Any]] ?? []
        let actions: [UIMenuElement] = items.compactMap { (item: [String: Any]) -> UIMenuElement? in
            guard let key = item["id"] as? String else { return nil }
            let sub = item["sub"] as? String
            let image = (item["sf"] as? String).flatMap { $0.isEmpty ? nil : UIImage(systemName: $0) }
            let action = UIAction(title: item["title"] as? String ?? "", subtitle: sub?.isEmpty == false ? sub : nil, image: image) { [weak self] _ in
                self?.sendToApp(["type": "hold", "id": id, "pick": key])
            }
            if (item["on"] as? Bool) == true { action.state = .on }
            return action
        }
        guard !actions.isEmpty else { return nil }
        return UIMenu(title: def["title"] as? String ?? "", children: actions)
    }

    /// Where the page's buttons with a menu are, in the page's own coordinates (only the app on screen — then the
    /// page's coordinates are the screen's). `null` means the button is gone or covered.
    private func updateHoldZones(_ zones: [String: Any]) {
        for (id, value) in zones {
            guard let z = value as? [String: Any],
                  let x = (z["x"] as? NSNumber)?.doubleValue, let y = (z["y"] as? NSNumber)?.doubleValue,
                  let w = (z["w"] as? NSNumber)?.doubleValue, let h = (z["h"] as? NSNumber)?.doubleValue,
                  w > 0, h > 0 else {
                holdZones.removeValue(forKey: id)
                continue
            }
            let radius = (z["r"] as? NSNumber)?.doubleValue ?? 12
            holdZones[id] = HoldZone(rect: CGRect(x: x, y: y, width: w, height: h), radius: CGFloat(radius))
        }
    }

    fileprivate func holdZone(at point: CGPoint) -> (id: String, zone: HoldZone)? {
        guard focused || appIsWholePage, presentedViewController == nil else { return nil }
        for (id, zone) in holdZones where zone.rect.contains(point) && holdMenus[id] != nil {
            return (id, zone)
        }
        return nil
    }

    /// The button itself, lifted out of the page: a picture of it in its own shape (the pill of the button), so it
    /// rises and the screen blurs around it exactly like any button with a menu in iOS.
    fileprivate func holdPreview() -> UITargetedPreview? {
        guard let hold = activeHold else { return nil }
        let zone = hold.zone
        let rect = zone.rect
        let picture = webView.resizableSnapshotView(from: rect, afterScreenUpdates: false, withCapInsets: .zero) ?? UIView()
        picture.frame = CGRect(origin: .zero, size: rect.size)
        let parameters = UIPreviewParameters()
        parameters.visiblePath = UIBezierPath(roundedRect: picture.bounds, cornerRadius: min(zone.radius, rect.height / 2))
        parameters.backgroundColor = .clear
        let target = UIPreviewTarget(container: webView, center: CGPoint(x: rect.midX, y: rect.midY))
        return UITargetedPreview(view: picture, parameters: parameters, target: target)
    }

    // MARK: - The app's own menu (Settings in the app, or shake the phone)

    func showAppMenu() {
        guard viewIfLoaded?.window != nil, presentedViewController == nil else { return }
        let sheet = UIAlertController(title: "Gym Tracker", message: "Версия для iPhone \(AppSettings.appVersion)", preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Обновить страницу", style: .default) { [weak self] _ in
            self?.reloadPage()
        })
        if appFrame != nil && !appIsWholePage {
            let title = focused ? "Показать страницу Claude вокруг" : "Только приложение, без Claude вокруг"
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.toggleFocus()
            })
        }
        if !LiveActivityManager.shared.isEnabled {
            sheet.addAction(UIAlertAction(title: "Включить Live Activity в настройках", style: .default) { _ in
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            })
        }
        sheet.addAction(UIAlertAction(title: "Сменить ссылку на приложение", style: .default) { [weak self] _ in
            self?.onChangeLink?()
        })
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY - 40, width: 1, height: 1)
        }
        present(sheet, animated: true)
    }

    private func toggleFocus() {
        let want = !focused
        AppSettings.focusMode = want
        setFocus(want)
    }

    private func reloadPage() {
        hideError()
        spinner.startAnimating()
        if webView.url == nil {
            webView.load(URLRequest(url: startURL))
        } else {
            webView.reload()
        }
    }

    // MARK: - When the page won't open

    private func showError(_ text: String) {
        hideError()
        pickerPanel?.hide(notify: true)
        let overlay = UIView()
        overlay.backgroundColor = view.backgroundColor
        overlay.overrideUserInterfaceStyle = pageDark ? .dark : .light
        overlay.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIImageView(image: UIImage(systemName: "wifi.exclamationmark"))
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 44, weight: .regular)
        icon.tintColor = .secondaryLabel

        let title = UILabel()
        title.text = "Не получилось открыть"
        title.font = UIFontMetrics(forTextStyle: .title2).scaledFont(for: .systemFont(ofSize: 22, weight: .bold))
        title.adjustsFontForContentSizeCategory = true
        title.textAlignment = .center
        title.numberOfLines = 0

        let message = UILabel()
        message.text = text + "\n\nНужен интернет, чтобы открыть приложение. Потом можно тренироваться и без сети, если не закрывать его."
        message.font = .preferredFont(forTextStyle: .subheadline)
        message.adjustsFontForContentSizeCategory = true
        message.textColor = .secondaryLabel
        message.textAlignment = .center
        message.numberOfLines = 0

        var retryConfig = UIButton.Configuration.filled()
        retryConfig.title = "Повторить"
        retryConfig.cornerStyle = .large
        retryConfig.buttonSize = .large
        let retry = UIButton(configuration: retryConfig, primaryAction: UIAction { [weak self] _ in self?.reloadPage() })

        var changeConfig = UIButton.Configuration.plain()
        changeConfig.title = "Сменить ссылку"
        let change = UIButton(configuration: changeConfig, primaryAction: UIAction { [weak self] _ in self?.onChangeLink?() })

        let stack = UIStackView(arrangedSubviews: [icon, title, message, retry, change])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.setCustomSpacing(24, after: message)
        stack.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(stack)
        view.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -32),
        ])
        errorView = overlay
    }

    private func hideError() {
        errorView?.removeFromSuperview()
        errorView = nil
    }

    private func loadFailed(_ webView: WKWebView, _ error: Error) {
        guard webView === self.webView else { return }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        if ns.domain == "WebKitErrorDomain" && (ns.code == 102 || ns.code == 204) { return }
        revealPage()
        // the app is already on screen: a failed side request is no reason to cover it
        guard appFrame == nil else { return }
        showError(ns.localizedDescription)
    }

    private func topPresenter() -> UIViewController {
        var top: UIViewController = self
        while let next = top.presentedViewController, !next.isBeingDismissed { top = next }
        return top
    }

    /// Shows a dialog for the page. If it can't be shown, `otherwise` answers the page right away
    /// (WebKit insists on an answer).
    private func present(dialog: UIViewController, otherwise: () -> Void) {
        let top = topPresenter()
        guard viewIfLoaded?.window != nil, !top.isBeingPresented, !top.isBeingDismissed else {
            otherwise()
            return
        }
        top.present(dialog, animated: true)
    }
}

// MARK: - Messages from the page

extension WebViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "hello":
            appFrame = message.frameInfo
            appIsWholePage = message.frameInfo.isMainFrame
            hideError()
            if appIsWholePage {
                setFullScreen(true)
                setNeedsStatusBarAppearanceUpdate()
                revealPage()
            } else if !AppSettings.focusMode {
                revealPage()
            } else if !focused {
                // let the page connect to Claude first (it says "ready"), but don't wait for ever
                focusTask?.cancel()
                focusTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    guard !Task.isCancelled else { return }
                    self?.focusIfWanted()
                }
            }
            sendToApp([
                "type": "hello",
                "native": AppSettings.appVersion,
                "live": LiveActivityManager.shared.isEnabled,
                "focus": focused,
                "insets": focused ? insetsPayload() : NSNull(),
                "picker": true,
                "holdZones": true,
            ])
        case "ready":
            if appFrame == nil { appFrame = message.frameInfo }
            focusIfWanted()
        case "haptic":
            Haptics.play(body["style"] as? String ?? "selection")
        case "live":
            LiveActivityManager.shared.apply(body["state"] as? [String: Any])
        case "look":
            applyLook(body)
        case "awake":
            UIApplication.shared.isIdleTimerDisabled = (body["on"] as? Bool) ?? false
        case "menu":
            showAppMenu()
        case "picker":
            handlePicker(body)
        case "holdMenu":
            if let id = body["id"] as? String { holdMenus[id] = body }
        case "holdZones":
            updateHoldZones(body["zones"] as? [String: Any] ?? [:])
        default:
            break
        }
    }
}

/// WKUserContentController holds its handlers for ever; this keeps only a weak link back to the screen.
final class ScriptHandlerProxy: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

// MARK: - Navigation

extension WebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
            decisionHandler(.allow)
            return
        }
        if scheme == Self.holdScheme {
            // a tap on a button with a menu: the page runs it itself
            decisionHandler(.cancel)
            return
        }
        if !["http", "https", "about", "blob", "data", "javascript"].contains(scheme) {
            // mailto:, tel:, other apps
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        if navigationAction.navigationType == .linkActivated, scheme == "http" || scheme == "https", !Hosts.keepsInside(url) {
            // a link to somewhere else: Safari (or the app that owns the link)
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        hideError()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        // a new page: the app will say hello again from wherever it runs now
        focusTask?.cancel()
        focusTask = nil
        if focused || appIsWholePage {
            focused = false
            webView.scrollView.bounces = true
            setFullScreen(false)
        }
        appFrame = nil
        appIsWholePage = false
        pickerPanel?.hide(notify: false)
        holdMenus = [:]
        holdZones = [:]
        setNeedsStatusBarAppearanceUpdate()
        if AppSettings.focusMode, webView.url?.path.contains("/artifact") == true {
            hidePage(for: 8)
        } else {
            revealPage()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        if webView.alpha >= 1 { spinner.stopAnimating() }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadFailed(webView, error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadFailed(webView, error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}

// MARK: - Windows and dialogs the page opens

extension WebViewController: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https", !Hosts.isSignIn(url) {
            // a link that wants its own window: Safari, or the Claude app for claude.ai links
            UIApplication.shared.open(url)
            return nil
        }
        // sign-in windows (and blank ones a page fills in itself) stay in the app, on top
        let popupWeb = WKWebView(frame: .zero, configuration: configuration)
        popupWeb.navigationDelegate = self
        popupWeb.uiDelegate = self
        let sheet = PopupViewController(webView: popupWeb)
        topPresenter().present(sheet, animated: true)
        popup = sheet
        return popupWeb
    }

    func webViewDidClose(_ webView: WKWebView) {
        if let popup, popup.webView === webView {
            popup.dismiss(animated: true)
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(dialog: alert) { completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(dialog: alert) { completionHandler(false) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in
            completionHandler(alert?.textFields?.first?.text)
        })
        present(dialog: alert) { completionHandler(nil) }
    }
}

// MARK: - Press and hold: the phone's own context menu

/// Where one of the page's buttons with a menu is, and how round its corners are.
struct HoldZone {
    let rect: CGRect
    let radius: CGFloat
}

extension WebViewController: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let hit = holdZone(at: location), let menu = holdMenu(id: hit.id) else {
            activeHold = nil
            return nil
        }
        activeHold = hit
        return UIContextMenuConfiguration(identifier: hit.id as NSString, previewProvider: nil) { _ in menu }
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configuration: UIContextMenuConfiguration, highlightPreviewForItemWithIdentifier identifier: any NSCopying) -> UITargetedPreview? {
        holdPreview()
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configuration: UIContextMenuConfiguration, dismissalPreviewForItemWithIdentifier identifier: any NSCopying) -> UITargetedPreview? {
        holdPreview()
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        holdPreview()
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        holdPreview()
    }
}
