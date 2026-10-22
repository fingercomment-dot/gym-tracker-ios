import SwiftUI
import UIKit

extension UIColor {
    /// "#RRGGBB" or "#RRGGBBAA".
    convenience init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let hasAlpha = s.count == 8
        let r = CGFloat((v >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = CGFloat((v >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = CGFloat((v >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a: CGFloat = hasAlpha ? CGFloat(v & 0xFF) / 255 : 1
        self.init(red: r, green: g, blue: b, alpha: a)
    }

    /// 0 for black … 1 for white.
    var luminance: CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}

extension Color {
    init(hexString: String, fallback: Color) {
        if let ui = UIColor(hexString: hexString) {
            self.init(uiColor: ui)
        } else {
            self = fallback
        }
    }
}
