import Charts
import SwiftUI
import UIKit

// More of what the page describes (the app's drawing 2): the month calendar, charts, legends, a menu to pick from,
// a progress bar, wheels inside a list.

// MARK: - Month calendar

/// The iPhone's own month calendar (UICalendarView): a workout done — a dot in its colour, planned — a ring,
/// a run or a ski — a small runner. A tap on a day opens it on the page.
struct NVCalendarRow: UIViewRepresentable {
    let row: NVNode
    let model: NVTabModel

    struct Mark: Equatable {
        var done: [String] = []
        var planned: [String] = []
        var cardio = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UICalendarView {
        let view = UICalendarView()
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let locale = Locale(identifier: row.str("loc") ?? "ru_RU")
        calendar.locale = locale
        view.calendar = calendar
        view.locale = locale
        view.delegate = context.coordinator
        let selection = UICalendarSelectionSingleDate(delegate: context.coordinator)
        view.selectionBehavior = selection
        view.availableDateRange = DateInterval(start: .distantPast, end: .distantFuture)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.row = row
        context.coordinator.model = model
        context.coordinator.marks = Self.marks(row)
        if let month = row.str("month"), let comps = Self.month(month) {
            view.setVisibleDateComponents(comps, animated: false)
        }
        context.coordinator.shownMonth = row.str("month")
        return view
    }

    func updateUIView(_ view: UICalendarView, context: Context) {
        let c = context.coordinator
        c.row = row
        c.model = model
        view.tintColor = UIColor(model.accent)
        let fresh = Self.marks(row)
        let changed = Set(c.marks.keys).union(fresh.keys).filter { c.marks[$0] != fresh[$0] }
        c.marks = fresh
        let days = changed.compactMap(Self.day)
        if !days.isEmpty { view.reloadDecorations(forDateComponents: days, animated: true) }
        // the page moved to another month itself
        if let month = row.str("month"), month != c.shownMonth, let comps = Self.month(month) {
            c.shownMonth = month
            view.setVisibleDateComponents(comps, animated: true)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UICalendarView, context: Context) -> CGSize? {
        let width = proposal.width ?? 360
        let size = uiView.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                                  withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        return CGSize(width: width, height: max(size.height, 300))
    }

    static func marks(_ row: NVNode) -> [String: Mark] {
        guard let raw = row.d["marks"] as? [String: Any] else { return [:] }
        var out: [String: Mark] = [:]
        for (day, value) in raw {
            guard let m = value as? [String: Any] else { continue }
            out[day] = Mark(done: (m["d"] as? [String]) ?? [], planned: (m["r"] as? [String]) ?? [], cardio: (m["cm"] as? Bool) ?? false)
        }
        return out
    }

    static func day(_ key: String) -> DateComponents? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return DateComponents(calendar: Calendar(identifier: .gregorian), year: p[0], month: p[1], day: p[2])
    }

    static func month(_ key: String) -> DateComponents? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count >= 2 else { return nil }
        return DateComponents(calendar: Calendar(identifier: .gregorian), year: p[0], month: p[1], day: 1)
    }

    static func key(_ c: DateComponents) -> String? {
        guard let y = c.year, let m = c.month, let d = c.day else { return nil }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        var row: NVNode?
        weak var model: NVTabModel?
        var marks: [String: Mark] = [:]
        var shownMonth: String?

        /// The calendar's own marks: a dot in the workout's colour when one was done, a ring when one is planned,
        /// a runner for a run or a ski.
        func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? {
            guard let key = NVCalendarRow.key(dateComponents), let mark = marks[key] else { return nil }
            if let hex = mark.done.first { return .default(color: UIColor(hexString: hex) ?? .systemBlue, size: .large) }
            if let hex = mark.planned.first { return .image(UIImage(systemName: "circle"), color: UIColor(hexString: hex) ?? .systemGray, size: .small) }
            if mark.cardio { return .image(UIImage(systemName: "figure.run"), color: .secondaryLabel, size: .small) }
            return nil
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
            guard let dateComponents, let key = NVCalendarRow.key(dateComponents) else { return }
            model?.act(row?.str("fn"), key)
            selection.setSelected(nil, animated: true)
        }

        func calendarView(_ calendarView: UICalendarView, didChangeVisibleDateComponentsFrom previousDateComponents: DateComponents) {
            let c = calendarView.visibleDateComponents
            guard let y = c.year, let m = c.month else { return }
            let month = String(format: "%04d-%02d", y, m)
            shownMonth = month
            model?.act(row?.str("mfn"), month)
        }
    }
}

// MARK: - Charts

/// The page's charts with Swift Charts: a line over time (weights, body weight), stacked bars (workouts a week),
/// horizontal bars (sets per muscle). Touch and slide to read the values.
struct NVChartRow: View {
    let row: NVNode
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch row.str("kind") {
            case "bars": NVBarsChart(row: row, accent: accent)
            case "hbars": NVHBarsChart(row: row, accent: accent)
            default: NVLineChart(row: row, accent: accent)
            }
            if let caption = row.str("cap") {
                Text(caption).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct NVPoint: Identifiable {
    let id: Int
    let series: Int
    let date: Date
    let y: Double
    let label: String
    let value: String
    let sub: String?
}

private struct NVLineChart: View {
    let row: NVNode
    let accent: Color
    @State private var selected: Date?
    /// The page's language (dates on the axis like «27.09», whatever the phone's region).
    @Environment(\.locale) private var locale

    var body: some View {
        let series = row.list("series")
        let colors = series.map { $0.color("c") ?? accent }
        var points: [NVPoint] = []
        for (si, s) in series.enumerated() {
            for p in s.list("pts") {
                points.append(NVPoint(id: points.count, series: si, date: Date(timeIntervalSince1970: (p.number("x") ?? 0) / 1000),
                                      y: p.number("y") ?? 0, label: p.str("l") ?? "", value: p.str("v") ?? "", sub: p.str("s")))
            }
        }
        let tipSeries = Int(row.number("tip") ?? 0)
        let base = points.filter { $0.series == tipSeries }
        let near = selected.flatMap { sel in base.min(by: { abs($0.date.timeIntervalSince(sel)) < abs($1.date.timeIntervalSince(sel)) }) }
        let ys = points.map(\.y)
        let low = ys.min() ?? 0, high = ys.max() ?? 1
        let pad = max((high - low) * 0.15, max(abs(high) * 0.03, 0.5))
        let lower = row.flag("zero") ? 0 : low - pad
        let ghost = row.flag("ghost")
        let last = series.indices.last.flatMap { li in points.last(where: { $0.series == li }) }
        return Chart {
            ForEach(points) { p in
                let s = series[p.series]
                if s.flag("line") && series[p.series].list("pts").count > 1 {
                    LineMark(x: .value("date", p.date), y: .value("value", p.y), series: .value("series", p.series))
                        .foregroundStyle(colors[p.series])
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
                if s.flag("dots") {
                    let r = s.number("r") ?? 4
                    PointMark(x: .value("date", p.date), y: .value("value", p.y))
                        .foregroundStyle(colors[p.series])
                        .symbolSize(r * r * 3.2)
                }
            }
            if row.flag("end"), let last {
                PointMark(x: .value("date", last.date), y: .value("value", last.y))
                    .foregroundStyle(colors[last.series])
                    .symbolSize(10)
                    .annotation(position: .trailing, alignment: .center, spacing: 4) {
                        Text(last.value).font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(colors[last.series])
                    }
            }
            if let near, !ghost {
                RuleMark(x: .value("date", near.date))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                    .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(near.label).font(.caption.weight(.semibold))
                            ForEach(points.filter { $0.date == near.date }) { p in
                                HStack(spacing: 4) {
                                    Circle().fill(colors[p.series]).frame(width: 6, height: 6)
                                    Text(p.value).font(.caption).monospacedDigit()
                                    Text(series[p.series].str("n") ?? "").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            if let sub = near.sub { Text(sub).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
                        }
                        .padding(6)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
            }
        }
        .chartYScale(domain: lower...(high + pad))
        .chartXSelection(value: $selected)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine()
                AxisValueLabel(format: Date.FormatStyle.dateTime.day().month(.twoDigits).locale(locale))
            }
        }
        .opacity(ghost ? 0.45 : 1)
        .frame(height: CGFloat(row.number("h") ?? 180))
        .accessibilityLabel(row.str("label") ?? "")
    }
}

private struct NVBarsChart: View {
    let row: NVNode
    let accent: Color
    @State private var selected: String?

    private struct Part: Identifiable {
        let id: Int
        let key: String
        let label: String
        let value: Double
        let text: String
        let name: String
        let color: Color
        let order: Int
    }

    var body: some View {
        let groups = row.list("groups")
        var parts: [Part] = []
        var labels: [String: String] = [:]
        var tips: [String: String] = [:]
        var totals: [Double] = []
        for (gi, g) in groups.enumerated() {
            let key = String(gi)
            labels[key] = g.str("l") ?? ""
            tips[key] = g.str("tip") ?? g.str("l") ?? ""
            var total = 0.0
            for (pi, p) in g.list("parts").enumerated() where (p.number("v") ?? 0) > 0 {
                let v = p.number("v") ?? 0
                total += v
                parts.append(Part(id: parts.count, key: key, label: g.str("l") ?? "", value: v, text: p.str("vt") ?? "", name: p.str("n") ?? "", color: p.color("c") ?? accent, order: pi))
            }
            totals.append(total)
        }
        let goal = row.number("goal")
        let top = max(row.number("yMin") ?? 1, goal ?? 0, (totals.max() ?? 0).rounded(.up))
        let keys = groups.indices.map(String.init)
        return Chart {
            ForEach(parts) { p in
                BarMark(x: .value("group", p.key), y: .value("value", p.value), width: .ratio(0.6))
                    .foregroundStyle(p.color)
                    .opacity(selected == nil || selected == p.key ? 1 : 0.45)
            }
            if let goal {
                RuleMark(y: .value("goal", goal))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.secondary)
                    .annotation(position: .top, alignment: .trailing, spacing: 2) {
                        Text(row.str("goalT") ?? "").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            if let selected {
                RuleMark(x: .value("group", selected))
                    .foregroundStyle(Color.clear)
                    .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tips[selected] ?? "").font(.caption.weight(.semibold))
                            let mine = parts.filter { $0.key == selected }
                            if mine.isEmpty, let empty = row.str("empty") {
                                Text(empty).font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(mine) { p in
                                HStack(spacing: 4) {
                                    Circle().fill(p.color).frame(width: 6, height: 6)
                                    Text(p.text).font(.caption).monospacedDigit()
                                    Text(p.name).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(6)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
            }
        }
        .chartXScale(domain: keys)
        .chartYScale(domain: 0...top)
        .chartXSelection(value: $selected)
        .chartXAxis {
            AxisMarks(values: keys) { value in
                AxisValueLabel {
                    Text(labels[value.as(String.self) ?? ""] ?? "").font(.caption2)
                }
            }
        }
        .frame(height: CGFloat(row.number("h") ?? 160))
        .accessibilityLabel(row.str("label") ?? "")
    }
}

private struct NVHBarsChart: View {
    let row: NVNode
    let accent: Color

    private struct Bar: Identifiable {
        let id: Int
        let label: String
        let value: Double
    }

    var body: some View {
        let bars = row.list("rows").enumerated().map { Bar(id: $0.offset, label: $0.element.str("l") ?? "", value: $0.element.number("v") ?? 0) }
        let top = max(row.number("max") ?? 1, bars.map(\.value).max() ?? 1)
        let color = row.color("c") ?? accent
        return Chart(bars) { bar in
            BarMark(x: .value("sets", bar.value), y: .value("muscle", bar.label), height: .ratio(0.55))
                .foregroundStyle(color)
                .annotation(position: .trailing, alignment: .leading, spacing: 4) {
                    Text(String(Int(bar.value))).font(.caption.weight(.semibold)).monospacedDigit()
                }
        }
        .chartXScale(domain: 0...(top * 1.12))
        .chartXAxis(.hidden)
        .frame(height: CGFloat(max(1, bars.count)) * 28)
    }
}

/// A small line at the end of a row (the pull-up ladder over the last workouts).
struct NVSparkline: View {
    let points: [Double]
    let color: Color

    var body: some View {
        if points.count >= 2, let low = points.min(), let high = points.max() {
            let pad = max((high - low) * 0.15, 0.5)
            Chart {
                ForEach(Array(points.enumerated()), id: \.offset) { i, y in
                    LineMark(x: .value("i", i), y: .value("v", y))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }
            .foregroundStyle(color)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: (low - pad)...(high + pad))
            .frame(width: 110, height: 40)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Legend, picker, progress, wheels

/// What the colours mean: dots, rings, a line, a runner — wrapping onto more lines when needed.
struct NVLegendRow: View {
    let row: NVNode

    var body: some View {
        NVFlow(spacing: 12, lineSpacing: 6) {
            ForEach(Array(row.list("items").enumerated()), id: \.offset) { _, item in
                HStack(spacing: 5) {
                    let color = item.color("c") ?? .secondary
                    switch item.str("kind") {
                    case "ring": Circle().strokeBorder(color, lineWidth: 1.5).frame(width: 8, height: 8)
                    case "line": Capsule().fill(color).frame(width: 14, height: 3)
                    case "cardio": Image(systemName: "figure.run").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    default: Circle().fill(color).frame(width: 8, height: 8)
                    }
                    Text(item.str("t") ?? "").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Lays its views out left to right and onto the next line when one is full.
struct NVFlow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += line + lineSpacing
                x = 0
                line = 0
            }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: width.isFinite ? width : widest, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += line + lineSpacing
                x = bounds.minX
                line = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}

/// One of many to pick (which exercise the chart shows): the iPhone's pop-up menu in a row.
struct NVPickRow: View {
    let row: NVNode
    @ObservedObject var model: NVTabModel
    @State private var local: String?

    var body: some View {
        let options = row.list("opts")
        let pageSel = row.str("sel") ?? ""
        Picker(row.str("t") ?? "", selection: Binding(get: { local ?? pageSel }, set: { value in
            local = value
            model.act(row.str("fn"), value)
        })) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Text(option.str("t") ?? "").tag(option.str("v") ?? "")
            }
        }
        .pickerStyle(.menu)
        .onChange(of: pageSel) { _, _ in local = nil }
        .accessibilityIdentifier("nv.pick." + row.id)
    }
}

struct NVMeterRow: View {
    let row: NVNode
    let accent: Color

    var body: some View {
        ProgressView(value: min(max(row.number("f") ?? 0, 0), 1))
            .tint(NVTone.color(row.str("tone"), accent: accent, otherwise: accent))
            .padding(.vertical, 4)
    }
}

/// Wheels right in the list (a run's distance and time, body weight): every stop goes to the page at once.
struct NVWheelsRow: View {
    let row: NVNode
    @ObservedObject var model: NVTabModel

    var body: some View {
        let columns = (row.d["cols"] as? [[String: Any]] ?? []).compactMap(WheelColumn.init(json:))
        VStack(alignment: .leading, spacing: 0) {
            Wheels(columns: columns) { selection in
                model.act(row.str("fn"), selection)
            }
            .frame(height: 180)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
        .accessibilityIdentifier("nv.wheels." + row.id)
    }
}
