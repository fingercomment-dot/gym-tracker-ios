import UIKit

/// A short note from the page while the app's own screens cover it («Отчёт скопирован…», «Заметка сохранена»):
/// a capsule with a symbol and the text, the way iOS shows such a confirmation, at the top of the screen over
/// everything (sheets included); it goes away by itself after a couple of seconds.
final class ToastHUD {
    private static weak var current: UIView?

    static func show(_ text: String, symbol: String, in window: UIWindow?, dark: Bool) {
        guard let window, !text.isEmpty else { return }
        current?.removeFromSuperview()

        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
        blur.overrideUserInterfaceStyle = dark ? .dark : .light
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.layer.cornerCurve = .continuous
        blur.clipsToBounds = true

        let image = UIImageView(image: UIImage(systemName: symbol) ?? UIImage(systemName: "checkmark"))
        image.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .subheadline, scale: .medium)
        image.tintColor = .label
        image.setContentHuggingPriority(.required, for: .horizontal)

        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.numberOfLines = 2

        let stack = UIStackView(arrangedSubviews: [image, label])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        blur.contentView.addSubview(stack)
        window.addSubview(blur)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: blur.contentView.topAnchor, constant: 11),
            stack.bottomAnchor.constraint(equalTo: blur.contentView.bottomAnchor, constant: -11),
            blur.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            blur.topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: 6),
            blur.widthAnchor.constraint(lessThanOrEqualTo: window.widthAnchor, constant: -32),
        ])
        blur.accessibilityIdentifier = "toast"
        blur.isAccessibilityElement = true
        blur.accessibilityLabel = text
        // touches go through to what's under it (the bar's «Готово»), like the system's own pills
        blur.isUserInteractionEnabled = false
        window.layoutIfNeeded()
        blur.layer.cornerRadius = min(blur.bounds.height / 2, 26)
        current = blur
        UIAccessibility.post(notification: .announcement, argument: text)

        blur.alpha = 0
        blur.transform = CGAffineTransform(translationX: 0, y: -24).scaledBy(x: 0.92, y: 0.92)
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
            blur.alpha = 1
            blur.transform = .identity
        }
        // the fade-out starts later on its own: an animation with a delay would set alpha 0 right away,
        // and the capsule would be gone for VoiceOver while it is still on the screen
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak blur] in
            guard let blur, blur.superview != nil else { return }
            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseIn]) {
                blur.alpha = 0
                blur.transform = CGAffineTransform(translationX: 0, y: -16)
            } completion: { _ in
                blur.removeFromSuperview()
            }
        }
    }
}
