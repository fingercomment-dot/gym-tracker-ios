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
    private let wheels = WheelsBox()
    /// One drum per column. Each drum carries its own column, so what it shows can't get out of step with it.
    private var drums: [Drum] = []

    private var labelColor: UIColor = .label

    fileprivate static let valueFont = UIFont.monospacedDigitSystemFont(ofSize: 23, weight: .regular)
    fileprivate static let unitFont = UIFont.systemFont(ofSize: 17, weight: .semibold)
    private static let rowHeight: CGFloat = 34
    /// Space between a value and its unit.
    fileprivate static let unitGap: CGFloat = 6
    /// From the panel's sides to the outer drums, and between two drums.
    private static let sideInset: CGFloat = 12
    private static let columnGap: CGFloat = 10

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
        wheels.onLayout = { [weak self] in self?.layoutDrums() }
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
        for drum in drums {
            drum.unitLabel.textColor = labelColor
            drum.reloadAllComponents()
        }
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
        setUpDrums(columns)
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
        let selection = drums.map { $0.column.selected }
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

    // MARK: - The drums

    /// Fresh drums for these columns (the same ones, given new values, when the number of columns is the same).
    /// A drum gets its column before it is told who feeds it, so any question it asks right away has an answer.
    private func setUpDrums(_ columns: [Column]) {
        if drums.count != columns.count {
            for drum in drums {
                drum.dataSource = nil
                drum.delegate = nil
                drum.removeFromSuperview()
                drum.unitLabel.removeFromSuperview()
            }
            drums = columns.enumerated().map { c, column in
                let drum = Drum(column: column)
                drum.accessibilityIdentifier = "picker.drum.\(c)"
                drum.unitLabel.textColor = labelColor
                drum.dataSource = self
                drum.delegate = self
                wheels.addSubview(drum)
                // the unit goes over the drum and takes no touches: a drag on «кг» turns the weight drum
                wheels.addSubview(drum.unitLabel)
                return drum
            }
        } else {
            for (drum, column) in zip(drums, columns) {
                drum.column = column
                drum.unitLabel.textColor = labelColor
            }
        }
        layoutDrums()
        for drum in drums {
            drum.reloadAllComponents()
            drum.selectRow(drum.column.selected, inComponent: 0, animated: false)
        }
    }

    /// The drums side by side across the panel; each unit right after where its column's values end.
    private func layoutDrums() {
        let n = drums.count
        guard n > 0 else { return }
        let box = wheels.bounds
        let width = (box.width - Self.sideInset * 2 - Self.columnGap * CGFloat(n - 1)) / CGFloat(n)
        guard width > 20 else { return }
        for (c, drum) in drums.enumerated() {
            let frame = CGRect(x: Self.sideInset + CGFloat(c) * (width + Self.columnGap), y: 0, width: width, height: box.height)
            drum.frame = frame
            let component = drum.componentWidth
            let start = max(0, (component - drum.numberWidth - drum.unitSpace) / 2)
            let x = frame.minX + (frame.width - component) / 2 + start + drum.numberWidth + Self.unitGap
            drum.unitLabel.frame = CGRect(x: x, y: frame.midY - 15, width: drum.unitWidth + 4, height: 30)
        }
    }
}

extension PickerPanel: UIPickerViewDataSource, UIPickerViewAccessibilityDelegate {
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        1
    }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        (pickerView as? Drum)?.column.rows.count ?? 0
    }

    func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
        (pickerView as? Drum)?.componentWidth ?? 60
    }

    func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
        Self.rowHeight
    }

    func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
        let cell = (view as? WheelRow) ?? WheelRow()
        guard let drum = pickerView as? Drum else {
            cell.label.text = nil
            return cell
        }
        let rows = drum.column.rows
        let text = rows.indices.contains(row) ? rows[row] : nil
        cell.numberWidth = drum.numberWidth
        cell.unitSpace = drum.unitSpace
        cell.label.textColor = labelColor
        cell.label.text = text
        cell.accessibilityLabel = text
        cell.setNeedsLayout()
        return cell
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        guard let drum = pickerView as? Drum, drum.column.rows.indices.contains(row) else { return }
        drum.column.selected = row
        drum.unitLabel.text = drum.column.unit(at: row)
        guard let id else { return }
        onEvent?(["type": "picker", "id": id, "ev": "change", "sel": drums.map { $0.column.selected }])
    }

    func pickerView(_ pickerView: UIPickerView, accessibilityLabelForComponent component: Int) -> String? {
        guard let label = (pickerView as? Drum)?.column.label, !label.isEmpty else { return nil }
        return label
    }
}

/// One drum: a picker that carries its column and its sizes, and the unit label that stands beside it.
private final class Drum: UIPickerView {
    var column: PickerPanel.Column {
        didSet { measure() }
    }
    /// The widest value of the column: the values line up on their right edge, the unit goes after it.
    private(set) var numberWidth: CGFloat = 0
    private(set) var unitWidth: CGFloat = 0
    let unitLabel = UILabel()

    var unitSpace: CGFloat { column.units.isEmpty ? 0 : PickerPanel.unitGap + unitWidth }
    var componentWidth: CGFloat { max(60, bounds.width - 16) }

    init(column: PickerPanel.Column) {
        self.column = column
        super.init(frame: .zero)
        unitLabel.font = PickerPanel.unitFont
        unitLabel.isUserInteractionEnabled = false
        measure()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func measure() {
        numberWidth = Self.width(of: column.rows, font: PickerPanel.valueFont) + 2
        unitWidth = Self.width(of: column.units, font: PickerPanel.unitFont)
        unitLabel.text = column.unit(at: column.selected)
        unitLabel.isHidden = column.units.isEmpty
    }

    private static func width(of texts: [String], font: UIFont) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return texts.reduce(0) { max($0, ceil(($1 as NSString).size(withAttributes: attributes).width)) }
    }
}

/// The strip the drums sit in: lays them out itself, once its own size is known.
private final class WheelsBox: UIView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

/// A row of a drum: the value, right-aligned where the column's values end (so «7» and «12,5» line up and the unit
/// can stand still right after them), or centred when the column has no unit.
private final class WheelRow: UIView {
    let label = UILabel()
    var numberWidth: CGFloat = 0
    var unitSpace: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        label.font = PickerPanel.valueFont
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if unitSpace > 0 {
            let start = max(0, (bounds.width - numberWidth - unitSpace) / 2)
            label.textAlignment = .right
            label.frame = CGRect(x: start, y: 0, width: min(numberWidth, bounds.width), height: bounds.height)
        } else {
            label.textAlignment = .center
            label.frame = bounds
        }
    }
}
