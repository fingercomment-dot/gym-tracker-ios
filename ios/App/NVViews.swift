import Charts
import SwiftUI

/// A tab drawn by the app from the page's description: the iPhone's grouped list under a large title, with the
/// page's own pages pushed over it (Settings → Appearance) and its buttons in the toolbar.
struct NVTabRoot: View {
    @ObservedObject var model: NVTabModel

    var body: some View {
        NavigationStack(path: Binding(get: { model.path }, set: { model.setPath($0) })) {
            Group {
                if let root = model.root {
                    NVScreenView(screen: root, model: model)
                } else {
                    Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                }
            }
            .navigationDestination(for: String.self) { _ in
                if let top = model.top {
                    NVScreenView(screen: top, model: model)
                } else {
                    Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                }
            }
        }
        .tint(model.accent)
    }
}

struct NVScreenView: View {
    let screen: NVNode
    @ObservedObject var model: NVTabModel

    var body: some View {
        List {
            ForEach(screen.list("secs")) { sec in
                NVSectionView(sec: sec, model: model)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(screen.str("title") ?? "")
        .navigationBarTitleDisplayMode(.large)
        .modifier(NVSubtitle(text: screen.str("sub")))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ForEach(screen.list("right")) { item in
                    NVToolbarButton(item: item, model: model)
                }
            }
        }
        .accessibilityIdentifier("nv.screen." + screen.id)
    }
}

/// The date under the large title (iOS 26 and later).
private struct NVSubtitle: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), let text {
            content.navigationSubtitle(text)
        } else {
            content
        }
    }
}

private struct NVToolbarButton: View {
    let item: NVNode
    @ObservedObject var model: NVTabModel

    var body: some View {
        Button {
            model.act(item.str("fn"))
        } label: {
            if let title = item.str("t") {
                Label(title, systemImage: item.str("sf") ?? "circle").labelStyle(.titleAndIcon)
            } else {
                Image(systemName: item.str("sf") ?? "circle")
            }
        }
        .tint(NVTone.color(item.str("tone"), accent: model.accent, otherwise: model.accent))
        .accessibilityLabel(item.str("label") ?? item.str("t") ?? "")
        .accessibilityIdentifier("nv.item." + item.id)
    }
}

/// good / warn / bad / tint — the page's tones as the phone's colours.
enum NVTone {
    static func color(_ tone: String?, accent: Color, otherwise: Color) -> Color {
        switch tone {
        case "good": return .green
        case "warn": return .orange
        case "bad": return .red
        case "tint": return accent
        default: return otherwise
        }
    }
}

// MARK: - Sections

struct NVSectionView: View {
    let sec: NVNode
    @ObservedObject var model: NVTabModel
    /// A fold opened or closed here, until the page says the same.
    @State private var openLocal: Bool?

    var body: some View {
        let fold = sec.node("fold")
        let pageOpen = fold.map { $0.flag("open") } ?? true
        let open = openLocal ?? pageOpen
        let plain = sec.flag("plain")
        let rows = sec.list("rows")
        let mover: ((IndexSet, Int) -> Void)? = sec.str("move") == nil ? nil : { from, to in model.move(section: sec, from: from, to: to) }
        Section {
            if open {
                ForEach(rows) { row in
                    NVRowView(row: row, plain: plain, model: model)
                        .moveDisabled(row.str("key") == nil)
                }
                .onMove(perform: mover)
            }
        } header: {
            NVSectionHeader(sec: sec, weeks: rows.first(where: { $0.kind == "weeks" }), open: open, model: model) {
                guard let fold else { return }
                let next = !open
                withAnimation { openLocal = next }
                model.act(fold.str("fn"), next)
            }
        } footer: {
            if let foot = sec.str("f") { Text(foot) }
        }
        .onChange(of: pageOpen) { _, _ in openLocal = nil }
    }
}

private struct NVSectionHeader: View {
    let sec: NVNode
    /// The week strip in this section: the title follows the week on screen.
    let weeks: NVNode?
    let open: Bool
    @ObservedObject var model: NVTabModel
    let toggle: () -> Void

    var body: some View {
        let page = weeks.flatMap { w -> NVNode? in
            let pages = w.list("pages")
            let i = model.pages[w.id] ?? Int(w.number("page") ?? 0)
            return pages.indices.contains(i) ? pages[i] : nil
        }
        let title = page?.str("h") ?? sec.str("h")
        let right = page?.str("hr") ?? sec.str("hr")
        if title != nil || right != nil || sec.has("hb") || sec.has("fold") {
            let content = HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let dot = sec.color("hc") {
                    Circle().fill(dot).frame(width: 9, height: 9)
                }
                if let title { Text(title) }
                Spacer(minLength: 8)
                if let right {
                    Text(right).monospacedDigit()
                }
                if let button = sec.node("hb") {
                    Button {
                        model.act(button.str("fn"))
                    } label: {
                        if let sf = button.str("sf") {
                            Label(button.str("t") ?? "", systemImage: sf)
                        } else {
                            Text(button.str("t") ?? "")
                        }
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("nv.hb." + sec.id)
                }
                if sec.has("fold") {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
            }
            if sec.has("fold") {
                Button(action: toggle) { content.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("nv.fold." + sec.id)
                    .accessibilityValue(open ? "1" : "0")
            } else {
                content
            }
        }
    }
}

// MARK: - Rows

struct NVRowView: View {
    let row: NVNode
    let plain: Bool
    @ObservedObject var model: NVTabModel

    var body: some View {
        Group {
            switch row.kind {
            case "toggle": NVToggleRow(row: row, model: model)
            case "stepper": NVStepperRow(row: row, model: model)
            case "seg": NVSegRow(row: row, model: model)
            case "btn": NVButton(btn: row, model: model, full: true).listRowSeparator(.hidden)
            case "btns": NVButtonsRow(row: row, model: model)
            case "note": NVNoteRow(row: row, model: model)
            case "text": NVTextRow(row: row, plain: plain)
            case "hero": NVHeroRow(row: row, model: model)
            case "weeks": NVWeeksRow(row: row, model: model)
            case "stat": NVStatRow(row: row, accent: model.accent)
            case "details": NVDetailsRow(row: row)
            case "field": NVFieldRow(row: row, model: model, multiline: false)
            case "area": NVFieldRow(row: row, model: model, multiline: true)
            case "swatches": NVSwatchesRow(row: row, model: model)
            case "unit": NVUnitRow(row: row, model: model)
            case "cal": NVCalendarRow(row: row, model: model).listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
            case "chart": NVChartRow(row: row, accent: model.accent)
            case "legend": NVLegendRow(row: row)
            case "pick": NVPickRow(row: row, model: model)
            case "meter": NVMeterRow(row: row, accent: model.accent)
            case "wheels": NVWheelsRow(row: row, model: model)
            default: NVPlainRow(row: row, model: model)
            }
        }
        .modifier(NVPlainBackground(plain: plain))
    }
}

/// Text and buttons outside the white cards: no card behind them.
private struct NVPlainBackground: ViewModifier {
    let plain: Bool

    func body(content: Content) -> some View {
        if plain {
            content.listRowBackground(Color.clear).listRowSeparator(.hidden)
        } else {
            content
        }
    }
}

/// The usual row: an icon, a title with a line under it, a value, a tick or a chevron.
struct NVPlainRow: View {
    let row: NVNode
    @ObservedObject var model: NVTabModel
    var inUnit = false

    var body: some View {
        if let fn = row.str("fn") {
            if inUnit {
                Button { model.act(fn) } label: { content }
                    .buttonStyle(.borderless)
                    .disabled(row.flag("off"))
                    .accessibilityIdentifier("nv.row." + row.id)
            } else {
                Button { model.act(fn) } label: { content }
                    .disabled(row.flag("off"))
                    .accessibilityIdentifier("nv.row." + row.id)
            }
        } else {
            content.accessibilityIdentifier("nv.row." + row.id)
        }
    }

    private var titleColor: Color {
        switch row.str("tt") {
        case "tint": return model.accent
        case "bad": return .red
        default: return .primary
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            if let lead = row.node("lead") {
                NVLead(lead: lead, accent: model.accent)
            }
            if row.flag("center") {
                Text(row.str("t") ?? "")
                    .foregroundStyle(titleColor)
                    .frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.str("t") ?? "")
                        .font(row.flag("bold") ? .headline : row.flag("small") ? .subheadline : .body)
                        .foregroundStyle(titleColor)
                        .monospacedDigit()
                    if let sub = row.str("s") {
                        Text(sub)
                            .font(.subheadline)
                            .foregroundStyle(NVTone.color(row.str("st"), accent: model.accent, otherwise: .secondary))
                    }
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if let value = row.str("v") {
                    Text(value)
                        .font(row.flag("big") ? .title3.weight(.semibold) : .body)
                        .monospacedDigit()
                        .foregroundStyle(NVTone.color(row.str("vt"), accent: model.accent, otherwise: row.flag("big") ? .primary : .secondary))
                        .multilineTextAlignment(.trailing)
                }
                if let trail = row.node("trail") {
                    NVTrail(trail: trail, model: model)
                }
                ForEach(Array(row.list("trails").enumerated()), id: \.offset) { _, trail in
                    NVTrail(trail: trail, model: model)
                }
                if let spark = row.node("spark") {
                    NVSparkline(points: spark.numbers("pts"), color: spark.color("c") ?? model.accent)
                }
                if row.has("check") {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(model.accent)
                        .opacity(row.flag("check") ? 1 : 0)
                        .accessibilityHidden(!row.flag("check"))
                }
                if row.has("disc") {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(row.flag("disc") ? 90 : 0))
                } else if row.flag("chev") {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

/// What stands at the start of a row: a workout's letter badge, a Settings-style icon, a symbol, a colour dot.
struct NVLead: View {
    let lead: NVNode
    let accent: Color

    var body: some View {
        switch lead.kind {
        case "badge":
            Text(lead.str("t") ?? "")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(lead.color("on") ?? .white)
                .frame(width: 30, height: 30)
                .background(lead.color("c") ?? .gray, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        case "icon":
            Image(systemName: lead.str("sf") ?? "circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(lead.color("c") ?? .gray, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        case "sym":
            Image(systemName: lead.str("sf") ?? "circle")
                .font(.title3)
                .foregroundStyle(lead.color("c") ?? accent)
                .frame(width: 30)
        case "plate":
            if lead.flag("ring") {
                Circle().strokeBorder(lead.color("c") ?? .gray, lineWidth: 2).frame(width: 10, height: 10)
            } else {
                Circle().fill(lead.color("c") ?? .gray).frame(width: 10, height: 10)
            }
        case "num":
            Text(lead.str("t") ?? "")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 22)
        default:
            EmptyView()
        }
    }
}

private struct NVTrail: View {
    let trail: NVNode
    @ObservedObject var model: NVTabModel

    var body: some View {
        switch trail.kind {
        case "pill":
            let color = NVTone.color(trail.str("tone"), accent: model.accent, otherwise: .secondary)
            Text(trail.str("t") ?? "")
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(color.opacity(0.16), in: Capsule())
        case "date", "time":
            NVDateField(trail: trail, model: model)
        case "btn":
            Button(trail.str("t") ?? "") { model.act(trail.str("fn")) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        case "ibtn":
            Button { model.act(trail.str("fn")) } label: {
                Image(systemName: trail.str("sf") ?? "circle")
            }
            .buttonStyle(.borderless)
            .tint(NVTone.color(trail.str("tone"), accent: model.accent, otherwise: model.accent))
            .accessibilityLabel(trail.str("label") ?? "")
        default:
            Text(trail.str("t") ?? "").foregroundStyle(.secondary)
        }
    }
}

/// The page's date and time fields as the phone's compact date picker.
private struct NVDateField: View {
    let trail: NVNode
    @ObservedObject var model: NVTabModel

    private var isTime: Bool { trail.kind == "time" }

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = format
        return f
    }

    var body: some View {
        let format = Self.formatter(isTime ? "HH:mm" : "yyyy-MM-dd")
        let value = trail.str("v").flatMap(format.date(from:)) ?? Date()
        let lower = trail.str("min").flatMap(format.date(from:)) ?? .distantPast
        let upper = trail.str("max").flatMap(format.date(from:)) ?? .distantFuture
        let binding = Binding<Date>(get: { value }, set: { model.act(trail.str("fn"), format.string(from: $0)) })
        if isTime {
            DatePicker("", selection: binding, displayedComponents: .hourAndMinute).labelsHidden()
        } else {
            DatePicker("", selection: binding, in: lower...upper, displayedComponents: .date).labelsHidden()
        }
    }
}

struct NVToggleRow: View {
    let row: NVNode
    @ObservedObject var model: NVTabModel
    @State private var local: Bool?

    var body: some View {
        let pageOn = row.flag("on")
        Toggle(isOn: Binding(get: { local ?? pageOn }, set: { value in
            local = value
            model.act(row.str("fn"), value)
        })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.str("t") ?? "")
                if let sub = row.str("s") {
                    Text(sub).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .disabled(row.flag("off"))
        .onChange(of: pageOn) { _, _ in local = nil }
        .task(id: local) {
            guard local != nil else { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            local = nil
        }
        .accessibilityIdentifier("nv.toggle." + row.id)
    }
}

struct NVStepperRow: View {
    let row: NVNode
    @ObservedObject var model: NVTabModel

    var body: some View {
        let inc = row.str("inc"), dec = row.str("dec")
        Stepper {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.str("t") ?? "")
                    if let sub = row.str("s") {
                        Text(sub).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Text(row.str("v") ?? "").monospacedDigit().foregroundStyle(.secondary)
            }
        } onIncrement: {
            if let inc { model.act(inc) }
        } onDecrement: {
            if let dec { model.act(dec) }
        }
        .accessibilityIdentifier("nv.stepper." + row.id)
    }
}

struct NVSegRow: View {
    let row: NVNode
    @ObservedObject var model: NVTabModel
    @State private var local: String?

    var body: some View {
        let options = row.list("opts")
        let pageSel = row.str("sel") ?? ""
        VStack(spacing: 6) {
            Picker("", selection: Binding(get: { local ?? pageSel }, set: { value in
                local = value
                model.act(row.str("fn"), value)
            })) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Text(option.str("t") ?? "").tag(option.str("v") ?? "")
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if row.has("lo") || row.has("hi") {
                HStack {
                    Text(row.str("lo") ?? "")
                    Spacer()
                    Text(row.str("hi") ?? "")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .onChange(of: pageSel) { _, _ in local = nil }
        .accessibilityIdentifier("nv.seg." + row.id)
    }
}

/// A button: filled for the main action, grey for the others; tap runs it, press and hold opens its menu.
struct NVButton: View {
    let btn: NVNode
    @ObservedObject var model: NVTabModel
    let full: Bool

    var body: some View {
        let label = HStack(spacing: 6) {
            if let sf = btn.str("sf") { Image(systemName: sf) }
            Text(btn.str("t") ?? "").lineLimit(1)
        }
        .frame(maxWidth: full ? .infinity : nil)
        Group {
            if let menu = btn.node("menu") {
                Menu {
                    NVMenuItems(menu: menu, model: model)
                } label: {
                    label
                } primaryAction: {
                    model.act(btn.str("fn"))
                }
                .menuStyle(.button)
            } else {
                Button { model.act(btn.str("fn")) } label: { label }
            }
        }
        .modifier(NVButtonLook(style: btn.str("style")))
        .disabled(btn.flag("off"))
        .accessibilityIdentifier("nv.btn." + btn.id)
    }
}

private struct NVButtonLook: ViewModifier {
    let style: String?

    func body(content: Content) -> some View {
        switch style {
        case "primary":
            content.buttonStyle(.borderedProminent).controlSize(.large).buttonBorderShape(.capsule)
        case "plain":
            content.buttonStyle(.borderless)
        case "danger":
            content.buttonStyle(.bordered).controlSize(.large).buttonBorderShape(.capsule).tint(.red)
        case "tinted":
            content.buttonStyle(.bordered).controlSize(.large).buttonBorderShape(.capsule)
        default:
            content.buttonStyle(.bordered).controlSize(.large).buttonBorderShape(.capsule).foregroundStyle(.primary)
        }
    }
}

/// The menu's picks, the chosen one ticked.
private struct NVMenuItems: View {
    let menu: NVNode
    @ObservedObject var model: NVTabModel

    var body: some View {
        let items = menu.list("items")
        Section(menu.str("title") ?? "") {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Toggle(isOn: Binding(get: { item.flag("on") }, set: { _ in model.act(item.str("fn")) })) {
                    Label {
                        Text(item.str("t") ?? "")
                        if let sub = item.str("s") { Text(sub) }
                    } icon: {
                        Image(systemName: item.str("sf") ?? "circle")
                    }
                }
            }
        }
    }
}

private struct NVButtonsRow: View {
    let row: NVNode
    @ObservedObject var model: NVTabModel

    var body: some View {
        HStack(spacing: 12) {
            ForEach(row.list("items")) { item in
                NVButton(btn: item, model: model, full: true)
            }
        }
        .listRowSeparator(.hidden)
    }
}

private struct NVNoteRow: View {
    let row: NVNode
    @ObservedObject var model: NVTabModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let sf = row.str("sf") {
                Image(systemName: sf).foregroundStyle(NVTone.color(row.str("tone"), accent: model.accent, otherwise: model.accent))
            }
            Text(row.str("t") ?? "").font(.subheadline)
            Spacer(minLength: 4)
            if let button = row.node("btn") {
                Button(button.str("t") ?? "") { model.act(button.str("fn")) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .accessibilityIdentifier("nv.note." + row.id)
    }
}

private struct NVTextRow: View {
    let row: NVNode
    let plain: Bool

    var body: some View {
        let small = row.flag("small")
        Text(row.str("t") ?? "")
            .font(small ? .footnote : .subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(small ? .center : .leading)
            .frame(maxWidth: .infinity, alignment: small ? .center : .leading)
    }
}

/// The top of Today: the week's ring, what's next, the workout's name.
private struct NVHeroRow: View {
    let row: NVNode
    @ObservedObject var model: NVTabModel

    var body: some View {
        HStack(spacing: 14) {
            if let ring = row.node("ring") {
                let value = ring.number("v") ?? 0, top = max(1, ring.number("max") ?? 3)
                Gauge(value: min(value, top), in: 0...top) {
                    EmptyView()
                } currentValueLabel: {
                    Text(ring.str("t") ?? "").font(.caption.weight(.semibold)).monospacedDigit()
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(value >= top ? .green : model.accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if let dot = row.color("c") { Circle().fill(dot).frame(width: 8, height: 8) }
                    Text(row.str("eye") ?? "").font(.subheadline).foregroundStyle(.secondary)
                }
                Text(row.str("t") ?? "").font(.title2.weight(.bold))
                if let sub = row.str("s") {
                    Text(sub).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("nv.hero")
    }
}

/// Four weeks side by side, swiped like pages; a day shows its workouts as dots, like the Calendar app.
private struct NVWeeksRow: View {
    let row: NVNode
    @ObservedObject var model: NVTabModel

    var body: some View {
        let pages = row.list("pages")
        let current = model.pages[row.id] ?? Int(row.number("page") ?? 0)
        TabView(selection: Binding(get: { current }, set: { i in
            model.pages[row.id] = i
            model.act(row.str("fn"), i)
        })) {
            ForEach(Array(pages.enumerated()), id: \.offset) { i, page in
                HStack(spacing: 0) {
                    ForEach(Array(page.list("days").enumerated()), id: \.offset) { _, day in
                        NVDayView(day: day, model: model)
                    }
                }
                .padding(.bottom, 22)
                .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .never))
        .frame(height: 104)
        .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 0, trailing: 4))
        .accessibilityIdentifier("nv.weeks")
    }
}

private struct NVDayView: View {
    let day: NVNode
    @ObservedObject var model: NVTabModel

    var body: some View {
        let today = day.flag("today")
        let dots = day.list("dots")
        Button {
            model.act(day.str("fn"))
        } label: {
            VStack(spacing: 4) {
                Text(day.str("l") ?? "")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(day.flag("we") ? .tertiary : .secondary)
                Text(day.str("n") ?? "")
                    .font(.body.weight(today ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(today ? Color.white : Color.primary)
                    .frame(width: 34, height: 34)
                    .background {
                        if today { Circle().fill(model.accent) }
                    }
                HStack(spacing: 3) {
                    ForEach(Array(dots.prefix(3).enumerated()), id: \.offset) { _, dot in
                        if dot.flag("ring") {
                            Circle().strokeBorder(dot.color("c") ?? .gray, lineWidth: 1.5).frame(width: 7, height: 7)
                        } else {
                            Circle().fill(dot.color("c") ?? .gray).frame(width: 7, height: 7)
                        }
                    }
                    if day.flag("cm") {
                        Image(systemName: "figure.run").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                    }
                }
                .frame(height: 8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel((day.str("l") ?? "") + " " + (day.str("n") ?? ""))
        .accessibilityIdentifier("nv.day." + (day.str("d") ?? ""))
    }
}

/// A big number with its line (body weight's trend), drawn with Swift Charts.
private struct NVStatRow: View {
    let row: NVNode
    let accent: Color

    var body: some View {
        let points = row.numbers("spark")
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                (Text(row.str("v") ?? "").font(.system(.largeTitle, design: .rounded).weight(.bold))
                    + Text(" " + (row.str("u") ?? "")).font(.title3.weight(.semibold)).foregroundColor(.secondary))
                    .monospacedDigit()
                if let sub = row.str("s") {
                    Text(sub).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if points.count >= 2, let low = points.min(), let high = points.max() {
                let pad = max((high - low) * 0.15, 0.05)
                let color = row.color("c") ?? accent
                Chart {
                    ForEach(Array(points.enumerated()), id: \.offset) { i, y in
                        LineMark(x: .value("day", i), y: .value("kg", y))
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    }
                    PointMark(x: .value("day", points.count - 1), y: .value("kg", points[points.count - 1]))
                        .symbolSize(40)
                }
                .foregroundStyle(color)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: (low - pad)...(high + pad))
                .frame(width: 140, height: 52)
                .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct NVDetailsRow: View {
    let row: NVNode
    @State private var open = false

    var body: some View {
        DisclosureGroup(isExpanded: $open) {
            Text(row.str("p") ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
        } label: {
            Text(row.str("t") ?? "").foregroundStyle(.primary)
        }
    }
}

private struct NVFieldRow: View {
    let row: NVNode
    @ObservedObject var model: NVTabModel
    let multiline: Bool
    @State private var text = ""
    @State private var started = false
    @FocusState private var focused: Bool

    var body: some View {
        let pageText = row.str("v") ?? ""
        Group {
            if multiline {
                TextField(row.str("ph") ?? "", text: $text, axis: .vertical).lineLimit(4...12)
            } else {
                TextField(row.str("ph") ?? "", text: $text)
            }
        }
        .focused($focused)
        .onAppear {
            if !started { text = pageText; started = true }
        }
        .onChange(of: text) { _, value in
            var value = value
            if let limit = row.number("max"), value.count > Int(limit) {
                value = String(value.prefix(Int(limit)))
                text = value
            }
            if value != pageText { model.act(row.str("fn"), value) }
        }
        .onChange(of: pageText) { _, value in
            if !focused { text = value }
        }
        .accessibilityIdentifier("nv.field." + row.id)
    }
}

/// Colour circles, the chosen one ringed (like a list's colour in Reminders).
private struct NVSwatchesRow: View {
    let row: NVNode
    @ObservedObject var model: NVTabModel
    @State private var local: String?

    var body: some View {
        let options = row.list("opts")
        let selected = local ?? row.str("sel")
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let value = option.str("v") ?? ""
                Button {
                    local = value
                    model.act(row.str("fn"), value)
                } label: {
                    Circle()
                        .fill(option.color("c") ?? .gray)
                        .frame(width: 30, height: 30)
                        .padding(5)
                        .overlay {
                            if value == selected {
                                Circle().strokeBorder(Color.secondary, lineWidth: 2.5)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.str("t") ?? value)
                .accessibilityAddTraits(value == selected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
        .onChange(of: row.str("sel")) { _, _ in local = nil }
        .accessibilityIdentifier("nv.swatches." + row.id)
    }
}

/// A superset in the program: its exercises as one row (they move together).
private struct NVUnitRow: View {
    let row: NVNode
    @ObservedObject var model: NVTabModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(row.list("kids").enumerated()), id: \.offset) { i, kid in
                if i > 0 { Divider() }
                NVPlainRow(row: kid, model: model, inUnit: true)
            }
        }
        .padding(.vertical, 2)
    }
}
