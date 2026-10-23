import UIKit

/// The phone's own wheels for the page: the drums of the Clock app's timer, docked at the bottom like a keyboard.
///
/// The page says what to show — `{type: "picker", id, title, sub, done, cols: [{rows, sel, units, label}]}` — and
/// gets every stop of a drum straight back (`{type: "picker", id, ev: "change", sel}`). It also hears when the
/// wheels come up and how tall they are (`ev: "open", h`), so it can keep what is being changed in sight, and when
/// they go away (`ev: "close", sel`) after «Готово» or a swipe down.
///
/// Every column is a drum of its own, spread across the panel — the first one against the left edge, the last one
/// against the right — and its unit («кг», «раз») stays still beside the middle row like on the timer, so a finger
/// can't catch it and drag it along.
final class PickerPanel: UIView {
    typealias Column = WheelColumn

    /// Messages for the page.
    var onEvent: (([String: Any]) -> Void)?

    private(set) var id: String?
    private var hiding = false

    private let card = UIView()
    private let header = UIView()
    private let grabber = UIView()
    private let titleLabel = UILabel()
    private let subLabel = UILabel()
    private let doneButton = UIButton(configuration: .plain())
    private let wheels = WheelsView()

    private var labelColor: UIColor = .label

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func build() {
        backgroundColor = .clear
        accessibilityIdentifier = "picker.panel"
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.28
        layer.shadowRadius = 18
        layer.shadowOffset = CGSize(width: 0, height: -2)

        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 24
        card.layer.cornerCurve = .continuous
        card.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        card.clipsToBounds = true
        addSubview(card)

        header.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(header)

        grabber.translatesAutoresizingMaskIntoConstraints = false
        grabber.backgroundColor = .tertiaryLabel
        grabber.layer.cornerRadius = 2.5
        header.addSubview(grabber)

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        subLabel.font = .systemFont(ofSize: 13, weight: .regular)
        subLabel.lineBreakMode = .byTruncatingTail
        let titles = UIStackView(arrangedSubviews: [titleLabel, subLabel])
        titles.axis = .vertical
        titles.spacing = 1
        titles.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(titles)

        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.accessibilityIdentifier = "picker.done"
        doneButton.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        doneButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        header.addSubview(doneButton)

        wheels.translatesAutoresizingMaskIntoConstraints = false
        wheels.onChange = { [weak self] selection in
            guard let self, let id = self.id else { return }
            self.onEvent?(["type": "picker", "id": id, "ev": "change", "sel": selection])
        }
        card.addSubview(wheels)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: topAnchor),
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),

            header.topAnchor.constraint(equalTo: card.topAnchor),
            header.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: card.trailingAnchor),

            grabber.topAnchor.constraint(equalTo: header.topAnchor, constant: 6),
            grabber.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            grabber.widthAnchor.constraint(equalToConstant: 36),
            grabber.heightAnchor.constraint(equalToConstant: 5),

            titles.topAnchor.constraint(equalTo: header.topAnchor, constant: 20),
            titles.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            titles.trailingAnchor.constraint(lessThanOrEqualTo: doneButton.leadingAnchor, constant: -8),
            titles.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -2),

            doneButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            doneButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -8),

            wheels.topAnchor.constraint(equalTo: header.bottomAnchor),
            wheels.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            wheels.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            wheels.heightAnchor.constraint(equalToConstant: 216),
            wheels.bottomAnchor.constraint(equalTo: card.safeAreaLayoutGuide.bottomAnchor, constant: -4),
        ])

        // drag the top of the panel down to put it away (the drums keep their own vertical drags)
        header.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragged(_:))))
    }

    // MARK: - Look

    /// The app's own sheet colours, so the wheels look like part of it.
    func style(sheet: UIColor?, label: UIColor?, secondary: UIColor?, tint: UIColor?, dark: Bool) {
        overrideUserInterfaceStyle = dark ? .dark : .light
        card.backgroundColor = sheet ?? .secondarySystemBackground
        labelColor = label ?? .label
        titleLabel.textColor = labelColor
        subLabel.textColor = secondary ?? .secondaryLabel
        doneButton.tintColor = tint ?? tintColor
        wheels.labelColor = labelColor
    }

    // MARK: - Showing and hiding

    func show(id: String, title: String, sub: String, done: String, columns: [Column]) {
        self.id = id
        titleLabel.text = title
        subLabel.text = sub
        subLabel.isHidden = sub.isEmpty
        var doneTitle = AttributedString(done)
        doneTitle.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        doneButton.configuration?.attributedTitle = doneTitle

        let wasHidden = isHidden
        isHidden = false
        hiding = false
        // our own size first: the drums are made at their final width
        superview?.layoutIfNeeded()
        wheels.setColumns(columns)
        layoutIfNeeded()

        if wasHidden { transform = CGAffineTransform(translationX: 0, y: bounds.height + 40) }
        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0,
                       options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.transform = .identity
        }
        onEvent?(["type": "picker", "id": id, "ev": "open", "h": Double(bounds.height)])
    }

    /// `notify`: tell the page (it didn't ask for this itself).
    func hide(notify: Bool) {
        guard !isHidden, !hiding else { return }
        hiding = true
        let closed = id
        let selection = wheels.selection
        id = nil
        UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
            self.transform = CGAffineTransform(translationX: 0, y: self.bounds.height + 40)
        } completion: { _ in
            guard self.hiding else { return }
            self.hiding = false
            self.isHidden = true
            self.transform = .identity
        }
        if notify, let closed {
            onEvent?(["type": "picker", "id": closed, "ev": "close", "sel": selection])
        }
    }

    @objc private func doneTapped() {
        hide(notify: true)
    }

    @objc private func dragged(_ pan: UIPanGestureRecognizer) {
        guard !hiding else { return }
        let dy = pan.translation(in: self).y
        switch pan.state {
        case .changed:
            transform = CGAffineTransform(translationX: 0, y: dy > 0 ? dy : dy / 8)
        case .ended, .cancelled, .failed:
            if dy > 70 || pan.velocity(in: self).y > 650 {
                hide(notify: true)
            } else {
                UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0,
                               options: [.allowUserInteraction, .beginFromCurrentState]) {
                    self.transform = .identity
                }
            }
        default:
            break
        }
    }
}
