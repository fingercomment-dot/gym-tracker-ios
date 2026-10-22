import UIKit

/// Real taps under the finger. The web page asks for them by name.
@MainActor
enum Haptics {
    private static let selection = UISelectionFeedbackGenerator()
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let notification = UINotificationFeedbackGenerator()

    static func play(_ style: String) {
        switch style {
        case "light":
            light.impactOccurred(); light.prepare()
        case "medium":
            medium.impactOccurred(); medium.prepare()
        case "heavy":
            heavy.impactOccurred(); heavy.prepare()
        case "rigid":
            rigid.impactOccurred(); rigid.prepare()
        case "soft":
            soft.impactOccurred(); soft.prepare()
        case "success":
            notification.notificationOccurred(.success)
        case "warning":
            notification.notificationOccurred(.warning)
        case "error":
            notification.notificationOccurred(.error)
        default:
            selection.selectionChanged(); selection.prepare()
        }
    }
}
