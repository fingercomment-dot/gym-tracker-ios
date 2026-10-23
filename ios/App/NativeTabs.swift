import UIKit

/// The phone's own tab bar at the bottom, over the page (iOS 26: the floating glass bar). The page says which tabs
/// there are and which one is open (`{type: "tabs", show, tab, items: [{id, title, sf}]}`); a tap on a tab goes back
/// to the page (`{type: "tab", tab}`), which switches to it. The tabs' own screens are still the page underneath, so
/// everything above the bar lets touches through to it.
final class NativeTabs: NSObject, UITabBarControllerDelegate {
    let controller = UITabBarController()
    /// Holds the tab bar controller's view: only touches on the bar itself stay here.
    let container = PassThroughView()
    /// A tab the person picked.
    var onSelect: ((String) -> Void)?

    private var ids: [String] = []

    override init() {
        super.init()
        controller.delegate = self
        container.backgroundColor = .clear
        container.passes = { [weak self] hit in
            guard let bar = self?.controller.tabBar else { return true }
            return !hit.isDescendant(of: bar)
        }
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

    /// What the page sent: the tabs, which one is open, whether the bar shows at all.
    func apply(_ body: [String: Any]) {
        let items = (body["items"] as? [[String: Any]]) ?? []
        let newIds = items.compactMap { $0["id"] as? String }
        if !items.isEmpty, newIds != ids || controller.viewControllers?.count != items.count {
            ids = newIds
            controller.viewControllers = items.map { item in
                let tab = TabPlaceholder()
                let image = (item["sf"] as? String).flatMap { UIImage(systemName: $0) }
                tab.tabBarItem = UITabBarItem(title: item["title"] as? String, image: image, selectedImage: nil)
                return tab
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

    /// How much of the bottom of the screen the bar covers, home indicator included (0 when it's hidden).
    func coveredHeight(in view: UIView) -> CGFloat {
        guard !container.isHidden, controller.tabBar.window != nil else { return 0 }
        let frame = controller.tabBar.convert(controller.tabBar.bounds, to: view)
        return max(0, view.bounds.maxY - frame.minY)
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        guard let index = tabBarController.viewControllers?.firstIndex(of: viewController), ids.indices.contains(index) else { return }
        onSelect?(ids[index])
    }
}

/// A tab's own screen while it is still the page: empty and see-through.
private final class TabPlaceholder: UIViewController {
    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
    }
}

/// A view that lets touches through to whatever is under it, except where `passes` says no.
final class PassThroughView: UIView {
    var passes: (UIView) -> Bool = { _ in true }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        return passes(hit) ? nil : hit
    }
}
