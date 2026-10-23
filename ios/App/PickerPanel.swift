import UIKit

/// The phone's own wheels for the page: the drums of the Clock app's timer, docked at the bottom like a keyboard.
///
/// The page says what to show — `{type: "picker", id, title, sub, done, cols: [{rows, sel, units, label}]}` — and
/// gets every stop of a drum straight back (`{type: "picker", id, ev: "change", sel}`). It also hears when the
/// wheels come up and how tall they are (`ev: "open", h`), so it can keep what is being changed in sight, and when
/// they go away (`ev: "close", sel`) after «Готово» or a swipe down.
final class PickerPanel: UIView {
    struct Column {
        var rows: [String]
        /// The unit beside the value: none, one for every row, or one per row («1 раз», «2 раза»).
        var units: [String]
        var label: String
        var selected: Int

        init?(json: [String: Any]) {
            guard let raw = json["rows"] as? [Any], !raw.isEmpty else { return nil }
            rows = raw.map { "\($0)" }
            units = (json["units"] as? [Any])?.map { "\($0)" } ?? []
            label = json["label"] as? String ?? ""
            let sel = (json["sel"] as? NSNumber)?.intValue ?? 0
            selected = min(max(sel, 0), rows.count - 1)
        }

        func unit(at row: Int) -> String? {
            if units.isEmpty { return nil }
            if units.count == 1 { return units[0] }
            return units[min(max(row, 0), units.count - 1)]
        }
    }

    /// What each drum of the picker is: a column of values, the unit beside it, or the space between two columns.
    private enum Part {
        case values(Int)
        case unit(Int)
        case gap
    }

    /// Messages for the page.
    var onEvent: (([String: Any]) -> Void)?

    private(set) var id: String?
    private var columns: [Column] = []
    private var parts: [Part] = []
    private var hiding = false

    private let card = UIView()
    private let header = UIView()
    private let grabber = UIView()
    private let titleLabel = UILabel()
    private let subLabel = UILabel()
    private let doneButton = UIButton(configuration: .plain())
    private let picker = UIPickerView()

    private var labelColor: UIColor = .label
    private static let valueFont = UIFont.monospacedDigitSystemFont(ofSize: 23, weight: .regular)
    private static let unitFont = UIFont.systemFont(ofSize: 17, weight: .semibold)
    private static let rowHeight: CGFloat = 34
    private static let gapWidth: CGFloat = 18

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func build() {
        backgroundColor = .clear
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
        doneButton.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        doneButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        header.addSubview(doneButton)

        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.dataSource = self
        picker.delegate = self
        card.addSubview(picker)

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

            picker.topAnchor.constraint(equalTo: header.bottomAnchor),
            picker.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            picker.heightAnchor.constraint(equalToConstant: 216),
            picker.bottomAnchor.constraint(equalTo: card.safeAreaLayoutGuide.bottomAnchor, constant: -4),
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
        picker.reloadAllComponents()
    }

    // MARK: - Showing and hiding

    func show(id: String, title: String, sub: String, done: String, columns: [Column]) {
        self.id = id
        self.columns = columns
        parts = []
        for (c, column) in columns.enumerated() {
            if c > 0 { parts.append(.gap) }
            parts.append(.values(c))
            if !column.units.isEmpty { parts.append(.unit(c)) }
        }
        titleLabel.text = title
        subLabel.text = sub
        subLabel.isHidden = sub.isEmpty
        var doneTitle = AttributedString(done)
        doneTitle.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        doneButton.configuration?.attributedTitle = doneTitle

        picker.reloadAllComponents()
        for (component, part) in parts.enumerated() {
            if case .values(let c) = part { picker.selectRow(columns[c].selected, inComponent: component, animated: false) }
        }

        let wasHidden = isHidden
        isHidden = false
        hiding = false
        superview?.layoutIfNeeded()
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
        let selection = columns.map(\.selected)
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

    // MARK: - Sizes

    private func width(of texts: [String], font: UIFont) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return texts.reduce(0) { max($0, ceil(($1 as NSString).size(withAttributes: attributes).width)) }
    }
}

extension PickerPanel: UIPickerViewDataSource, UIPickerViewAccessibilityDelegate {
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        parts.count
    }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        guard component < parts.count else { return 0 }
        if case .values(let c) = parts[component] { return columns[c].rows.count }
        return 1
    }

    func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
        guard component < parts.count else { return 0 }
        switch parts[component] {
        case .values(let c):
            return max(44, width(of: columns[c].rows, font: Self.valueFont) + 14)
        case .unit(let c):
            return max(18, width(of: columns[c].units, font: Self.unitFont) + 8)
        case .gap:
            return Self.gapWidth
        }
    }

    func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
        Self.rowHeight
    }

    func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
        let label = (view as? UILabel) ?? UILabel()
        label.textColor = labelColor
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        guard component < parts.count else { label.text = nil; return label }
        switch parts[component] {
        case .values(let c):
            let column = columns[c]
            label.text = row < column.rows.count ? column.rows[row] : nil
            label.font = Self.valueFont
            label.textAlignment = column.units.isEmpty ? .center : .right
        case .unit(let c):
            label.text = columns[c].unit(at: columns[c].selected)
            label.font = Self.unitFont
            label.textAlignment = .left
        case .gap:
            label.text = nil
        }
        return label
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        guard component < parts.count, case .values(let c) = parts[component], let id else { return }
        columns[c].selected = row
        if columns[c].units.count > 1, let unitComponent = parts.firstIndex(where: {
            if case .unit(let u) = $0 { return u == c }
            return false
        }) {
            pickerView.reloadComponent(unitComponent)
        }
        onEvent?(["type": "picker", "id": id, "ev": "change", "sel": columns.map(\.selected)])
    }

    func pickerView(_ pickerView: UIPickerView, accessibilityLabelForComponent component: Int) -> String? {
        guard component < parts.count, case .values(let c) = parts[component] else { return nil }
        return columns[c].label.isEmpty ? nil : columns[c].label
    }
}
