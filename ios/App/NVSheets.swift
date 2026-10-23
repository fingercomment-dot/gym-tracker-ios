import SwiftUI
import UIKit

/// The page's sheets as the iPhone's own (`{type: "nvs", sheets: [...]}`, bottom first): a page sheet with the title
/// and its buttons in the bar, the same grouped list inside; a question with choices (Удалить? / Отмена) as the
/// iPhone's action sheet. The page stays in charge: a sheet goes away when the page closes it, and a swipe down
/// closes it on the page too.
final class NVSheets: NSObject, UIAdaptivePresentationControllerDelegate {
    weak var host: UIViewController?
    var send: (([String: Any]) -> Void)?
    var accent: Color = .accentColor {
        didSet { stack.forEach { $0.model?.accent = accent } }
    }

    private struct Entry {
        let id: String
        let vc: UIViewController
        let model: NVTabModel?
        let close: String?
    }

    private var stack: [Entry] = []
    /// The latest list, while a sheet is still coming or going: shown once the phone is ready.
    private var waiting: [[String: Any]]?
    private var retry: DispatchWorkItem?

    func apply(_ list: [[String: Any]]) {
        let ids = list.compactMap { $0["id"] as? String }
        // the lowest sheet that is gone goes away, with everything over it
        if let cut = stack.firstIndex(where: { !ids.contains($0.id) }) {
            let gone = Array(stack[cut...])
            stack.removeSubrange(cut...)
            if let first = gone.first(where: { $0.vc.presentingViewController != nil && !$0.vc.isBeingDismissed }) {
                first.vc.presentingViewController?.dismiss(animated: true)
            }
        }
        for sheet in list {
            guard let id = sheet["id"] as? String else { continue }
            if let entry = stack.first(where: { $0.id == id }) {
                entry.model?.update(screen: sheet, root: nil)
                continue
            }
            guard let presenter = topPresenter() else {
                later(list)
                return
            }
            let entry = make(sheet, id: id)
            entry.vc.presentationController?.delegate = self
            presenter.present(entry.vc, animated: true)
            stack.append(entry)
        }
    }

    /// The app's page changed or Claude's page came back around the app: all sheets go.
    func reset() {
        waiting = nil
        retry?.cancel()
        if let first = stack.first, first.vc.presentingViewController != nil {
            first.vc.presentingViewController?.dismiss(animated: false)
        }
        stack = []
    }

    private func later(_ list: [[String: Any]]) {
        waiting = list
        retry?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let list = self.waiting else { return }
            self.waiting = nil
            self.apply(list)
        }
        retry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    /// Where a new sheet can come up from right now (nil while something is still sliding).
    private func topPresenter() -> UIViewController? {
        guard var top = host, top.viewIfLoaded?.window != nil else { return nil }
        while let next = top.presentedViewController {
            if next.isBeingDismissed || next.isBeingPresented { return nil }
            top = next
        }
        if top.isBeingDismissed || top.isBeingPresented { return nil }
        return top
    }

    private func make(_ sheet: [String: Any], id: String) -> Entry {
        if (sheet["kind"] as? String) == "actions" {
            let node = NVNode(sheet)
            let alert = UIAlertController(title: node.str("title"), message: node.str("msg"), preferredStyle: .actionSheet)
            for action in node.list("actions") {
                let fn = action.str("fn")
                alert.addAction(UIAlertAction(title: action.str("t"), style: action.flag("danger") ? .destructive : .default) { [weak self] _ in
                    self?.act(fn)
                })
            }
            let cancel = node.node("cancel")
            alert.addAction(UIAlertAction(title: cancel?.str("t") ?? "Отмена", style: .cancel) { [weak self] _ in
                self?.act(cancel?.str("fn"))
            })
            if let pop = alert.popoverPresentationController, let view = host?.view {
                pop.sourceView = view
                pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY - 60, width: 1, height: 1)
            }
            return Entry(id: id, vc: alert, model: nil, close: cancel?.str("fn"))
        }
        let model = NVTabModel(tab: "sheets")
        model.send = send
        model.accent = accent
        model.update(screen: sheet, root: nil)
        let vc = UIHostingController(rootView: NVSheetView(model: model))
        vc.modalPresentationStyle = .pageSheet
        if let sp = vc.sheetPresentationController {
            sp.detents = [.large()]
            sp.prefersGrabberVisible = true
        }
        return Entry(id: id, vc: vc, model: model, close: sheet["close"] as? String)
    }

    private func act(_ fn: String?) {
        guard let fn else { return }
        send?(["type": "nva", "tab": "sheets", "fn": fn])
    }

    /// Swiped down: the page closes that sheet (and any over it) too.
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard let i = stack.firstIndex(where: { $0.vc === presentationController.presentedViewController }) else { return }
        let gone = Array(stack[i...])
        stack.removeSubrange(i...)
        for entry in gone.reversed() { act(entry.close) }
    }
}

/// A sheet of the page: the title and its two buttons in the bar, the grouped list, the main button at the bottom.
struct NVSheetView: View {
    @ObservedObject var model: NVTabModel

    var body: some View {
        NavigationStack {
            if let sheet = model.root {
                List {
                    ForEach(sheet.list("secs")) { sec in
                        NVSectionView(sec: sec, model: model)
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle(sheet.str("title") ?? "")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if let left = sheet.node("left") {
                        ToolbarItem(placement: .cancellationAction) { NVSheetBarButton(item: left, model: model) }
                    }
                    if let right = sheet.node("right") {
                        ToolbarItem(placement: .confirmationAction) { NVSheetBarButton(item: right, model: model) }
                    }
                }
                .modifier(NVSheetFoot(buttons: sheet.list("foot"), model: model))
                .accessibilityIdentifier("nv.sheet." + (sheet.str("id") ?? ""))
            }
        }
        .tint(model.accent)
    }
}

private struct NVSheetBarButton: View {
    let item: NVNode
    @ObservedObject var model: NVTabModel

    var body: some View {
        Button {
            model.act(item.str("fn"))
        } label: {
            if let title = item.str("t") {
                Text(title).fontWeight(item.flag("bold") ? .semibold : .regular)
            } else {
                Image(systemName: item.str("sf") ?? "circle")
            }
        }
        .disabled(item.flag("off"))
        .tint(NVTone.color(item.str("tone"), accent: model.accent, otherwise: model.accent))
        .accessibilityLabel(item.str("label") ?? item.str("t") ?? "")
        .accessibilityIdentifier("nv.bar." + (item.str("label") ?? item.str("t") ?? ""))
    }
}

/// The sheet's main button pinned at the bottom (iOS 26: in the bar that blurs the list under it).
private struct NVSheetFoot: ViewModifier {
    let buttons: [NVNode]
    @ObservedObject var model: NVTabModel

    func body(content: Content) -> some View {
        if buttons.isEmpty {
            content
        } else if #available(iOS 26.0, *) {
            content.safeAreaBar(edge: .bottom) { bar }
        } else {
            content.safeAreaInset(edge: .bottom) { bar.background(.bar) }
        }
    }

    private var bar: some View {
        VStack(spacing: 8) {
            ForEach(buttons) { button in
                NVButton(btn: button, model: model, full: true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}
