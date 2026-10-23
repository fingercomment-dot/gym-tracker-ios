import SwiftUI

/// A piece of a screen the page described (see 48v_nv.js in the web app): a screen, a section, a row, a button…
/// It stays the JSON dictionary it came in as; the views read what they need from it.
struct NVNode: Identifiable {
    let d: [String: Any]

    init(_ d: [String: Any]) { self.d = d }

    var id: String { d["id"] as? String ?? "" }
    var kind: String { d["k"] as? String ?? "row" }

    func str(_ key: String) -> String? {
        guard let s = d[key] as? String, !s.isEmpty else { return nil }
        return s
    }
    func flag(_ key: String) -> Bool { (d[key] as? Bool) ?? false }
    func has(_ key: String) -> Bool { d[key] != nil && !(d[key] is NSNull) }
    func number(_ key: String) -> Double? { (d[key] as? NSNumber)?.doubleValue }
    func node(_ key: String) -> NVNode? { (d[key] as? [String: Any]).map(NVNode.init) }
    func list(_ key: String) -> [NVNode] { (d[key] as? [[String: Any]] ?? []).map(NVNode.init) }
    func numbers(_ key: String) -> [Double] { (d[key] as? [Any] ?? []).compactMap { ($0 as? NSNumber)?.doubleValue } }
    func color(_ key: String) -> Color? { str(key).flatMap { UIColor(hexString: $0) }.map { Color(uiColor: $0) } }
}

/// One tab drawn by the app: the page's latest description of it (and of the page under it, when the page shows
/// something inside Settings), and the way back to the page for every tap.
final class NVTabModel: ObservableObject {
    let tab: String
    @Published private(set) var root: NVNode?
    /// A page opened over the root (Settings → Appearance): the root stays underneath for the back swipe.
    @Published private(set) var top: NVNode?
    @Published private(set) var path: [String] = []
    @Published var accent: Color = .accentColor
    /// Which week the week strip shows, by row (the section's title follows it).
    @Published var pages: [String: Int] = [:]
    var send: (([String: Any]) -> Void)?

    private var rootDict: [String: Any]?
    private var topDict: [String: Any]?
    private var lastScreen = ""
    private var lastRoot = ""

    init(tab: String) { self.tab = tab }

    var isShown: Bool { root != nil || top != nil }

    /// `screen` nil: the page draws this tab itself again.
    func update(screen: [String: Any]?, root newRoot: [String: Any]?) {
        guard let screen else {
            rootDict = nil; topDict = nil; root = nil; top = nil; path = []
            lastScreen = ""; lastRoot = ""
            return
        }
        let screenKey = Self.key(screen)
        let rootKey = newRoot.map(Self.key) ?? ""
        let id = screen["id"] as? String ?? ""
        if let parent = screen["parent"] as? String, !parent.isEmpty {
            if let newRoot, rootKey != lastRoot { rootDict = newRoot; root = NVNode(newRoot); lastRoot = rootKey }
            if screenKey != lastScreen { topDict = screen; top = NVNode(screen); lastScreen = screenKey }
            if path != [id] { path = [id] }
        } else {
            if screenKey != lastScreen || rootDict == nil { rootDict = screen; root = NVNode(screen); lastScreen = screenKey; lastRoot = screenKey }
            if !path.isEmpty { path = [] }
        }
    }

    /// The person went back (the back button or a swipe): the page goes back too.
    func setPath(_ newPath: [String]) {
        if newPath.isEmpty, !path.isEmpty, let back = top?.str("back") { act(back) }
        path = newPath
    }

    func act(_ fn: String?, _ value: Any? = nil) {
        guard let fn else { return }
        var message: [String: Any] = ["type": "nva", "tab": tab, "fn": fn]
        if let value { message["v"] = value }
        send?(message)
    }

    /// Rows dragged into a new order: shown at once, the page saves it and sends the list again.
    func move(section: NVNode, from: IndexSet, to: Int) {
        var rows = section.d["rows"] as? [[String: Any]] ?? []
        rows.move(fromOffsets: from, toOffset: to)
        let keys = rows.compactMap { $0["key"] as? String }
        replaceRows(of: section.id, with: rows)
        act(section.str("move"), keys)
    }

    private func replaceRows(of sectionID: String, with rows: [[String: Any]]) {
        func fix(_ screen: [String: Any]?) -> [String: Any]? {
            guard var screen, var secs = screen["secs"] as? [[String: Any]],
                  let i = secs.firstIndex(where: { ($0["id"] as? String) == sectionID }) else { return nil }
            secs[i]["rows"] = rows
            screen["secs"] = secs
            return screen
        }
        if let changed = fix(topDict) { topDict = changed; top = NVNode(changed) }
        if let changed = fix(rootDict) { rootDict = changed; root = NVNode(changed) }
    }

    private static func key(_ dict: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]) else { return UUID().uuidString }
        return String(decoding: data, as: UTF8.self)
    }
}
