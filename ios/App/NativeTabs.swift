import SwiftUI
import UIKit

/// The phone's own tab bar at the bottom, over the page (iOS 26: the floating glass bar). The page says which tabs
/// there are and which one is open (`{type: "tabs", show, tab, items: [{id, title, sf}]}`); a tap on a tab goes back
/// to the page (`{type: "tab", tab}`), which switches to it.
///
/// A tab is either the page itself (its slot stays empty and see-through, touches go through to the page) or a
/// screen the app draws from the page's description (`{type: "nv", tab, screen, root}`, see NV.swift). With iOS 26
/// a minimised workout sits over the bar as the player bar (`{type: "mini"}`).
final class NativeTabs: NSObject, UITabBarControllerDelegate {
    let controller = UITabBarController()
    /// Holds the tab bar controller's view: touches on the page's own tabs go through it.
    let container = PassThroughView()
    /// A tab the person picked.
    var onSelect: ((String) -> Void)?
    /// Taps on the app's own screens and on the player bar, for the page.
    var send: (([String: Any]) -> Void)? {
        didSet { models.values.forEach { $0.send = send }; mini.send = send }
    }
    var accent: Color = .accentColor {
        didSet { models.values.forEach { $0.accent = accent }; mini.accent = accent }
    }

    private var ids: [String] = []
    private var slots: [String: TabSlot] = [:]
    private var models: [String: NVTabModel] = [:]
    let mini = MiniModel()
    private var miniView: UIView?
    /// The page (for a picture of it while it draws a tab).
    weak var pageView: UIView?
    /// A picture of the screen held over a tab switch until the new tab is on the screen: the page needs a moment to
    /// draw a tab of its own (and the app a tab it hasn't been sent yet), and meanwhile the switch should show neither
    /// an empty nor a stale screen. The page says when it has drawn the tab (`{type: "tabready"}`, page 12.11+).
    private var cover: UIView?
    private var coverTab: String?
    private var coverLimit: DispatchWorkItem?

    override init() {
        super.init()
        controller.delegate = self
        container.backgroundColor = .clear
        container.passes = { [weak self] hit, point in self?.passesThrough(hit, at: point) ?? true }
    }

    /// Touches stay with the bar, the player bar over it and the app's own screens; everything else (an empty,
    /// see-through tab and the containers around it) goes through to the page.
    private func passesThrough(_ hit: UIView, at point: CGPoint) -> Bool {
        if hit.isDescendant(of: controller.tabBar) { return false }
        if let miniView, miniView.window != nil,
           miniView.convert(miniView.bounds, to: container).insetBy(dx: -8, dy: -8).contains(point) { return false }
        for slot in slots.values where slot.hasScreen && hit.isDescendant(of: slot.view) { return false }
        return true
    }

    /// Puts the bar into the screen (above `below`'s content), once.
    func install(in parent: UIViewController, above view: UIView) {
        guard container.superview == nil else { return }
        container.translatesAutoresizingMaskIntoConstraints = false
        parent.view.insertSubview(container, aboveSubview: view)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: parent.view.topAnchor),
            container.bottomAnchor.constraint(equalTo: parent.view.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: parent.view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: parent.view.trailingAnchor),
        ])
        parent.addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        controller.view.backgroundColor = .clear
        container.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: container.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            controller.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        controller.didMove(toParent: parent)
        container.isHidden = true
    }

    private func model(_ tab: String) -> NVTabModel {
        if let m = models[tab] { return m }
        let m = NVTabModel(tab: tab)
        m.send = send
        m.accent = accent
        models[tab] = m
        return m
    }

    /// What the page sent: the tabs, which one is open, whether the bar shows at all.
    func apply(_ body: [String: Any]) {
        let items = (body["items"] as? [[String: Any]]) ?? []
        let newIds = items.compactMap { $0["id"] as? String }
        if !items.isEmpty, newIds != ids || controller.viewControllers?.count != items.count {
            ids = newIds
            controller.viewControllers = items.map { item in
                let id = item["id"] as? String ?? ""
                let slot = slots[id] ?? TabSlot(model: model(id))
                slots[id] = slot
                let image = (item["sf"] as? String).flatMap { UIImage(systemName: $0) }
                slot.tabBarItem = UITabBarItem(title: item["title"] as? String, image: image, selectedImage: nil)
                return slot
            }
        } else if !items.isEmpty {
            for (vc, item) in zip(controller.viewControllers ?? [], items) {
                vc.tabBarItem.title = item["title"] as? String
            }
        }
        if let tab = body["tab"] as? String, let index = ids.firstIndex(of: tab), controller.selectedIndex != index {
            controller.selectedIndex = index
        }
        container.isHidden = !((body["show"] as? Bool) ?? false) || ids.isEmpty
    }

    /// The page's description of a tab's screen (nil: the page draws that tab itself again).
    func setScreen(tab: String, screen: [String: Any]?, root: [String: Any]?) {
        let m = model(tab)
        m.update(screen: screen, root: root)
        slots[tab]?.showScreen(m.isShown)
        if screen != nil, tab == coverTab { dropCoverSoon() }
    }

    /// The page has drawn the tab the person switched to.
    func tabReady(_ tab: String?) {
        guard let tab, tab == coverTab else { return }
        dropCoverSoon()
    }

    private func holdPicture(until tab: String) {
        dropCover(animated: false)
        let current = controller.selectedViewController as? TabSlot
        guard let source = (current?.hasScreen ?? false) ? current?.view : pageView,
              source.window != nil,
              let picture = source.snapshotView(afterScreenUpdates: false) else { return }
        picture.frame = source.convert(source.bounds, to: controller.view)
        picture.isUserInteractionEnabled = false
        picture.accessibilityIdentifier = "tab.cover"
        // under the bar (it shows the new tab right away), over the tabs' screens; if the bar shares its layer
        // with the screens, over everything for that moment
        var anchor: UIView? = controller.tabBar
        while let a = anchor, a.superview !== controller.view { anchor = a.superview }
        if let anchor, let content = controller.selectedViewController?.view, !content.isDescendant(of: anchor) {
            controller.view.insertSubview(picture, belowSubview: anchor)
        } else {
            controller.view.addSubview(picture)
        }
        cover = picture
        coverTab = tab
        // an older page never says so: the picture goes by itself
        let limit = DispatchWorkItem { [weak self] in self?.dropCover(animated: true) }
        coverLimit = limit
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: limit)
    }

    /// A frame or two later: an app screen just made has been drawn by then.
    private func dropCoverSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in self?.dropCover(animated: true) }
    }

    private func dropCover(animated: Bool) {
        coverLimit?.cancel()
        coverLimit = nil
        guard let picture = cover else { return }
        cover = nil
        coverTab = nil
        if animated {
            UIView.animate(withDuration: 0.12, delay: 0, options: [.curveEaseOut]) {
                picture.alpha = 0
            } completion: { _ in
                picture.removeFromSuperview()
            }
        } else {
            picture.removeFromSuperview()
        }
    }

    /// A new page or Claude's page around the app: the app's own screens go away.
    func reset() {
        dropCover(animated: false)
        for (tab, m) in models {
            m.update(screen: nil, root: nil)
            slots[tab]?.showScreen(false)
        }
        showMini(["show": false])
    }

    /// How much of the bottom of the screen the bar covers (with the player bar and the home indicator; 0 when hidden).
    func coveredHeight(in view: UIView) -> CGFloat {
        guard !container.isHidden, controller.tabBar.window != nil else { return 0 }
        var top = controller.tabBar.convert(controller.tabBar.bounds, to: view).minY
        if let miniView, miniView.window != nil, !miniView.isHidden, miniView.bounds.height > 0 {
            top = min(top, miniView.convert(miniView.bounds, to: view).minY - 8)
        }
        return max(0, view.bounds.maxY - top)
    }

    // MARK: - The minimised workout over the bar (iOS 26)

    static var hasPlayerBar: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    func showMini(_ body: [String: Any]) {
        guard #available(iOS 26.0, *) else { return }
        let show = (body["show"] as? Bool) ?? false
        if show {
            mini.update(body)
            if controller.bottomAccessory == nil {
                let content = UIHostingConfiguration { MiniBarView(model: self.mini) }
                    .margins(.all, 0)
                    .makeContentView()
                content.backgroundColor = .clear
                content.accessibilityIdentifier = "mini.bar"
                miniView = content
                controller.setBottomAccessory(UITabAccessory(contentView: content), animated: true)
            }
        } else if controller.bottomAccessory != nil {
            controller.setBottomAccessory(nil, animated: true)
            miniView = nil
        }
    }

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        if let index = tabBarController.viewControllers?.firstIndex(of: viewController), ids.indices.contains(index),
           index != tabBarController.selectedIndex, let slot = viewController as? TabSlot, !slot.hasScreen {
            holdPicture(until: ids[index])
        }
        return true
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        guard let index = tabBarController.viewControllers?.firstIndex(of: viewController), ids.indices.contains(index) else { return }
        onSelect?(ids[index])
    }
}

/// A tab's own screen: empty and see-through while the page draws it, or the app's screen drawn from the page.
final class TabSlot: UIViewController {
    let model: NVTabModel
    private var host: UIHostingController<NVTabRoot>?
    var hasScreen: Bool { host != nil }

    init(model: NVTabModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
    }

    func showScreen(_ on: Bool) {
        if on, host == nil {
            loadViewIfNeeded()
            let h = UIHostingController(rootView: NVTabRoot(model: model))
            h.view.backgroundColor = .systemGroupedBackground
            addChild(h)
            h.view.frame = view.bounds
            h.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(h.view)
            h.didMove(toParent: self)
            host = h
        } else if !on, let h = host {
            h.willMove(toParent: nil)
            h.view.removeFromSuperview()
            h.removeFromParent()
            host = nil
        }
    }
}

/// A view that lets touches through to whatever is under it, except where `passes` says no.
final class PassThroughView: UIView {
    var passes: (UIView, CGPoint) -> Bool = { _, _ in true }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        return passes(hit, point) ? nil : hit
    }
}
