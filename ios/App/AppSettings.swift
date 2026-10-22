import UIKit

enum AppSettings {
    private static let urlKey = "artifactURL"
    private static let focusKey = "focusMode"
    private static let backgroundKey = "pageBackground"

    /// The link to your Gym Tracker in Claude.
    static var artifactURL: URL? {
        get { UserDefaults.standard.string(forKey: urlKey).flatMap { URL(string: $0) } }
        set { UserDefaults.standard.set(newValue?.absoluteString, forKey: urlKey) }
    }

    /// Only the app on screen, without Claude's page around it.
    static var focusMode: Bool {
        get { UserDefaults.standard.object(forKey: focusKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: focusKey) }
    }

    /// The app's background colour last time, so the next launch starts in it.
    static var pageBackground: String? {
        get { UserDefaults.standard.string(forKey: backgroundKey) }
        set { UserDefaults.standard.set(newValue, forKey: backgroundKey) }
    }

    static var startBackground: UIColor {
        pageBackground.flatMap { UIColor(hexString: $0) } ?? UIColor(named: "LaunchBackground") ?? .black
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
}

/// Which links stay inside the app and which go out to Safari or other apps.
enum Hosts {
    private static let claude = ["claude.ai", "claude.com", "anthropic.com", "claudeusercontent.com", "claude.site"]
    private static let signIn = ["accounts.google.com", "accounts.youtube.com", "appleid.apple.com", "idmsa.apple.com"]

    private static func matches(_ host: String, _ list: [String]) -> Bool {
        list.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private static func host(_ url: URL) -> String? {
        url.host()?.lowercased()
    }

    /// Claude itself and sign-in pages.
    static func keepsInside(_ url: URL) -> Bool {
        guard let host = host(url) else { return true }
        return matches(host, claude) || matches(host, signIn)
    }

    /// A window a page opens to sign in (Google, Apple, Claude's own login).
    static func isSignIn(_ url: URL) -> Bool {
        guard let host = host(url) else { return true }
        if matches(host, signIn) { return true }
        if matches(host, ["claude.ai", "claude.com"]) {
            let path = url.path.lowercased()
            return path.hasPrefix("/login") || path.hasPrefix("/api/auth") || path.hasPrefix("/magic-link") || path.hasPrefix("/oauth")
        }
        return false
    }
}
