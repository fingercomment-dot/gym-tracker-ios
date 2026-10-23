import SwiftUI
import UIKit

/// One column of drums: its values, the unit beside them, which one is picked.
struct WheelColumn: Equatable {
    var rows: [String]
    /// The unit beside the value: none, one for every row, or one per row («1 раз», «2 раза»).
    var units: [String]
    var label: String
    var selected: Int

    init(rows: [String], units: [String], label: String, selected: Int) {
        self.rows = rows
        self.units = units
        self.label = label
        self.selected = rows.isEmpty ? 0 : min(max(selected, 0), rows.count - 1)
    }

    init?(json: [String: Any]) {
        guard let raw = json["rows"] as? [Any], !raw.isEmpty else { return nil }
        self.init(rows: raw.map { "\($0)" }, units: (json["units"] as? [Any])?.map { "\($0)" } ?? [],
                  label: json["label"] as? String ?? "", selected: (json["sel"] as? NSNumber)?.intValue ?? 0)
    }

    func unit(at row: Int) -> String? {
        if units.isEmpty { return nil }
        if units.count == 1 { return units[0] }
        return units[min(max(row, 0), units.count - 1)]
    }
}

/// The phone's own drums, one per column, spread across the width — the first against the left edge, the last
/// against the right — each with its unit standing still beside the middle row, like the Clock app's timer.
final class WheelsView: UIView, UIPickerViewDataSource, UIPickerViewAccessibilityDelegate {
    /// After every stop of a drum: what is picked in each column now.
    var onChange: (([Int]) -> Void)?

    var labelColor: UIColor = .label {
        didSet {
            for drum in drums {
                drum.unitLabel.textColor = labelColor
                drum.reloadAllComponents()
            }
        }
    }

    private var drums: [Drum] = []

    fileprivate static let valueFont = UIFont.monospacedDigitSystemFont(ofSize: 23, weight: .regular)
    fileprivate static let unitFont = UIFont.systemFont(ofSize: 17, weight: .semibold)
    fileprivate static let unitGap: CGFloat = 6
    private static let rowHeight: CGFloat = 34
    private static let sideInset: CGFloat = 12
    private static let columnGap: CGFloat = 10

    var selection: [Int] { drums.map { $0.column.selected } }

    /// New columns (the same drums, given new values, when the number of columns is the same). A drum gets its
    /// column before it is told who feeds it, so any question it asks right away has an answer.
    func setColumns(_ columns: [WheelColumn]) {
        if drums.count != columns.count {
            for drum in drums {
                drum.dataSource = nil
                drum.delegate = nil
                drum.removeFromSuperview()
                drum.unitLabel.removeFromSuperview()
            }
            drums = columns.enumerated().map { c, column in
                let drum = Drum(column: column)
                drum.accessibilityIdentifier = "wheels.drum.\(c)"
                drum.unitLabel.textColor = labelColor
                drum.dataSource = self
                drum.delegate = self
                addSubview(drum)
                // the unit goes over the drum and takes no touches: a drag on «кг» turns the weight drum
                addSubview(drum.unitLabel)
                return drum
            }
            layoutDrums()
            for drum in drums {
                drum.reloadAllComponents()
                drum.selectRow(drum.column.selected, inComponent: 0, animated: false)
            }
            return
        }
        for (drum, column) in zip(drums, columns) {
            let rowsChanged = drum.column.rows != column.rows || drum.column.units != column.units
            let moved = drum.column.selected != column.selected
            drum.column = column
            if rowsChanged { drum.reloadAllComponents() }
            if rowsChanged || moved, drum.selectedRow(inComponent: 0) != column.selected {
                drum.selectRow(column.selected, inComponent: 0, animated: !rowsChanged && window != nil)
            }
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutDrums()
    }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 216) }

    /// The drums side by side; each unit right after where its column's values end.
    private func layoutDrums() {
        let n = drums.count
        guard n > 0 else { return }
        let width = (bounds.width - Self.sideInset * 2 - Self.columnGap * CGFloat(n - 1)) / CGFloat(n)
        guard width > 20 else { return }
        for (c, drum) in drums.enumerated() {
            let frame = CGRect(x: Self.sideInset + CGFloat(c) * (width + Self.columnGap), y: 0, width: width, height: bounds.height)
            if drum.frame != frame {
                let resized = drum.frame.width != frame.width
                drum.frame = frame
                if resized {
                    drum.reloadAllComponents()
                    drum.selectRow(drum.column.selected, inComponent: 0, animated: false)
                }
            }
            let component = drum.componentWidth
            let start = max(0, (component - drum.numberWidth - drum.unitSpace) / 2)
            let x = frame.minX + (frame.width - component) / 2 + start + drum.numberWidth + Self.unitGap
            drum.unitLabel.frame = CGRect(x: x, y: frame.midY - 15, width: drum.unitWidth + 4, height: 30)
        }
    }

    // MARK: - Data for the drums

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
        onChange?(selection)
    }

    func pickerView(_ pickerView: UIPickerView, accessibilityLabelForComponent component: Int) -> String? {
        guard let label = (pickerView as? Drum)?.column.label, !label.isEmpty else { return nil }
        return label
    }
}

/// One drum: a picker that carries its column and its sizes, and the unit label that stands beside it.
private final class Drum: UIPickerView {
    var column: WheelColumn {
        didSet { measure() }
    }
    /// The widest value of the column: the values line up on their right edge, the unit goes after it.
    private(set) var numberWidth: CGFloat = 0
    private(set) var unitWidth: CGFloat = 0
    let unitLabel = UILabel()

    var unitSpace: CGFloat { column.units.isEmpty ? 0 : WheelsView.unitGap + unitWidth }
    var componentWidth: CGFloat { max(60, bounds.width - 16) }

    init(column: WheelColumn) {
        self.column = column
        super.init(frame: .zero)
        unitLabel.font = WheelsView.unitFont
        unitLabel.isUserInteractionEnabled = false
        measure()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func measure() {
        numberWidth = Self.width(of: column.rows, font: WheelsView.valueFont) + 2
        unitWidth = Self.width(of: column.units, font: WheelsView.unitFont)
        unitLabel.text = column.unit(at: column.selected)
        unitLabel.isHidden = column.units.isEmpty
    }

    private static func width(of texts: [String], font: UIFont) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return texts.reduce(0) { max($0, ceil(($1 as NSString).size(withAttributes: attributes).width)) }
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
        label.font = WheelsView.valueFont
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

/// The same drums inside a SwiftUI list row.
struct Wheels: UIViewRepresentable {
    var columns: [WheelColumn]
    var onChange: ([Int]) -> Void

    func makeUIView(context: Context) -> WheelsView {
        let view = WheelsView()
        view.setColumns(columns)
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: WheelsView, context: Context) {
        view.onChange = onChange
        view.setColumns(columns)
    }
}
