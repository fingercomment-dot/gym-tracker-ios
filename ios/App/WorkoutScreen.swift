import SwiftUI

// MARK: - What the page sends

/// The workout list as the page describes it (`{type: "workout", show, state}`), every time something changes.
struct WorkoutState: Decodable, Equatable {
    struct TodayRow: Decodable, Equatable {
        let kind: String
        let t: String
        let s: String?
        let score: Double?
        let v: String?
        let tone: String?
    }

    struct Warm: Decodable, Equatable {
        let t: String
        let s: String
        let on: Bool
    }

    struct Rest: Decodable, Equatable {
        let kind: String
        let start: Double
        let end: Double
    }

    struct Ask: Decodable, Equatable {
        let kind: String
        let title: String
        let text: String
        let ok: String
        let cancel: String
        let danger: Bool
    }

    struct Finish: Decodable, Equatable {
        let t: String
        let primary: Bool
        let ask: Ask?
    }

    struct WeightWheel: Decodable, Equatable {
        let vals: [Double]
        let rows: [String]
        let unit: String
        let label: String
    }

    struct RepsWheel: Decodable, Equatable {
        let max: Int
        let units: [String]
        let label: String
    }

    struct SetRow: Decodable, Equatable, Identifiable {
        var id: Int { k }
        let k: Int
        let w: Double
        let r: Int
        let done: Bool
        let last: Bool
        let next: Bool
        let text: String
    }

    struct Item: Decodable, Equatable, Identifiable {
        var id: Int { i }
        let i: Int
        let name: String
        let w: WeightWheel?
        let r: RepsWheel
        let sets: [SetRow]
    }

    struct Block: Decodable, Equatable, Identifiable {
        var id: String { key }
        let b: Int
        let key: String
        let title: String
        let sub: String
        let done: Bool
        let quick: Bool
        let open: Bool
        let info: Bool
        let ss: Bool
        let canEnd: Bool
        let items: [Item]
    }

    let sid: String
    let title: String
    let startedAt: Double
    let today: [TodayRow]
    let warm: Warm
    let done: Int
    let total: Int
    let rest: Rest?
    let blocks: [Block]
    let finish: Finish
    let labels: [String: String]

    func label(_ key: String) -> String { labels[key] ?? "" }
}

/// The list's link to the page: the latest state, and what the person does on it.
final class WorkoutModel: ObservableObject {
    @Published var state: WorkoutState?
    @Published var accent: Color = .accentColor
    /// An exercise opened or closed here, until the page's next state says the same.
    @Published var openNow: [String: Bool] = [:]
    var send: (([String: Any]) -> Void)?

    func update(_ json: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(json),
              let data = try? JSONSerialization.data(withJSONObject: json),
              let decoded = try? JSONDecoder().decode(WorkoutState.self, from: data) else { return }
        openNow = openNow.filter { key, open in decoded.blocks.first(where: { $0.key == key })?.open != open }
        if decoded != state { state = decoded }
    }

    func act(_ action: String, _ extra: [String: Any] = [:]) {
        var message = extra
        message["type"] = "wact"
        message["a"] = action
        send?(message)
    }

    func isOpen(_ block: WorkoutState.Block) -> Bool { openNow[block.key] ?? block.open }

    func setOpen(_ block: WorkoutState.Block, _ open: Bool) {
        openNow[block.key] = open
        act("open", ["b": block.b, "open": open])
    }
}

/// Which set's drums are out.
private struct SetKey: Hashable {
    let b: Int
    let i: Int
    let k: Int
}

// MARK: - The screen

/// The workout list in iOS's own parts: a grouped list, the exercises opening into their sets, a circle to tick each
/// set off like in Reminders, the drums right under a set to change it, the rest counting in the navigation bar.
struct WorkoutScreen: View {
    @ObservedObject var model: WorkoutModel
    @State private var editing: SetKey?
    @State private var asking = false

    var body: some View {
        NavigationStack {
            if let state = model.state {
                list(state)
            } else {
                ProgressView()
            }
        }
        .tint(model.accent)
    }

    private func list(_ st: WorkoutState) -> some View {
        List {
            Section(st.label("today")) {
                ForEach(Array(st.today.enumerated()), id: \.offset) { _, row in
                    TodayRowView(row: row)
                }
            }
            Section(st.label("warm")) {
                Toggle(isOn: Binding(get: { st.warm.on }, set: { model.act("warm", ["on": $0]) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(st.warm.t)
                        Text(st.warm.s)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                ForEach(st.blocks) { block in
                    BlockView(block: block, state: st, model: model, editing: $editing, accent: model.accent)
                }
            } header: {
                HStack {
                    Text(st.label("exercises"))
                    Spacer()
                    Text("\(st.done)\(st.label("of"))\(st.total)")
                }
            }
            Section {
                Button {
                    if st.finish.ask != nil {
                        asking = true
                    } else {
                        model.act("finish", ["kind": "finish"])
                    }
                } label: {
                    Text(st.finish.t)
                        .fontWeight(st.finish.primary ? .semibold : .regular)
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("workout.finish")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(st.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    model.act("min")
                } label: {
                    Label(st.label("minimize"), systemImage: "chevron.down")
                }
                .accessibilityIdentifier("workout.minimize")
            }
            ToolbarItem(placement: .principal) {
                RestTimer(rest: st.rest, restLabel: st.label("rest"), noRestLabel: st.label("noRest"), accent: model.accent)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Text(Date(timeIntervalSince1970: st.startedAt / 1000), style: .timer)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog(st.finish.ask?.title ?? "", isPresented: $asking, titleVisibility: .visible) {
            if let ask = st.finish.ask {
                Button(ask.ok, role: ask.danger ? .destructive : nil) {
                    model.act("finish", ["kind": ask.kind])
                }
                Button(ask.cancel, role: .cancel) {}
            }
        } message: {
            if let ask = st.finish.ask { Text(ask.text) }
        }
    }
}

/// A row of the «Сегодня» section: readiness, a note, or the check-in skipped.
private struct TodayRowView: View {
    let row: WorkoutState.TodayRow

    var body: some View {
        switch row.kind {
        case "ready":
            HStack(spacing: 12) {
                Text("\(Int((row.score ?? 0).rounded()))")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text(row.t)
                Spacer()
                Text(row.v ?? "")
                    .foregroundStyle(toneColor(row.tone))
            }
        case "info":
            Label {
                Text(row.t)
                    .font(.subheadline)
            } icon: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.orange)
            }
        default:
            VStack(alignment: .leading, spacing: 2) {
                Text(row.t)
                if let s = row.s, !s.isEmpty {
                    Text(s)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func toneColor(_ tone: String?) -> Color {
        switch tone {
        case "good": return .green
        case "warn": return .orange
        case "bad": return .red
        default: return .secondary
        }
    }
}

/// An exercise: its row opens into its sets, like a reminder with subtasks.
private struct BlockView: View {
    let block: WorkoutState.Block
    let state: WorkoutState
    @ObservedObject var model: WorkoutModel
    @Binding var editing: SetKey?
    let accent: Color

    var body: some View {
        DisclosureGroup(isExpanded: Binding(get: { model.isOpen(block) }, set: { model.setOpen(block, $0) })) {
            ForEach(block.items) { item in
                if block.ss {
                    Text(item.name)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(item.sets) { set in
                    let key = SetKey(b: block.b, i: item.i, k: set.k)
                    SetRowView(set: set, label: (block.ss ? state.label("round") : state.label("set")) + " \(set.k + 1)",
                               editing: editing == key, accent: accent, id: "\(block.b).\(item.i).\(set.k)",
                               tick: { tick(item, set) },
                               tap: { withAnimation { editing = editing == key ? nil : key } })
                    if editing == key {
                        SetWheels(block: block, item: item, set: set, model: model)
                    }
                }
            }
            HStack {
                Button {
                    model.act("add", ["b": block.b])
                } label: {
                    Label(block.ss ? state.label("addRound") : state.label("addSet"), systemImage: "plus")
                }
                .buttonStyle(.borderless)
                Spacer()
                Menu {
                    if block.canEnd {
                        Button {
                            model.act("end", ["b": block.b])
                        } label: {
                            Label(state.label("endBlock"), systemImage: "checkmark.circle")
                        }
                    }
                    Button {
                        model.act("old", ["b": block.b])
                    } label: {
                        Label(state.label("old"), systemImage: "list.bullet.rectangle")
                    }
                } label: {
                    Label(state.label("more"), systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
            }
        } label: {
            HStack(spacing: 12) {
                CompletionCircle(done: block.done, accent: accent) {
                    if block.quick || !block.done { model.act("quick", ["b": block.b]) }
                }
                .accessibilityLabel(block.quick ? state.label("unquick") : state.label("quick"))
                .accessibilityIdentifier("quick.\(block.b)")
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.title)
                        .foregroundStyle(block.done ? Color.secondary : Color.primary)
                    Text(block.sub)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if block.info {
                    Button {
                        model.act("info", ["b": block.b])
                    } label: {
                        Label(state.label("info"), systemImage: "info.circle")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("info.\(block.b)")
                }
            }
        }
    }

    /// The circle of a set: ticks it off (and any skipped before it); on the last one done, takes it back.
    private func tick(_ item: WorkoutState.Item, _ set: WorkoutState.SetRow) {
        if !set.done {
            if editing?.b == block.b { editing = nil }
            model.act("log", ["b": block.b, "i": item.i, "k": set.k])
        } else if set.last {
            model.act("unlog", ["b": block.b, "i": item.i])
        }
    }
}

/// A set: the circle like in Reminders, then «Подход 1» and its weight × reps; a tap on the row brings out the drums.
private struct SetRowView: View {
    let set: WorkoutState.SetRow
    let label: String
    let editing: Bool
    let accent: Color
    let id: String
    let tick: () -> Void
    let tap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CompletionCircle(done: set.done, accent: accent, action: tick)
                .accessibilityIdentifier("tick.\(id)")
            Button(action: tap) {
                HStack {
                    Text(label)
                        .foregroundStyle(set.done ? Color.secondary : Color.primary)
                    Spacer()
                    Text(set.text)
                        .monospacedDigit()
                        .foregroundStyle(editing ? accent : Color.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("set.\(id)")
        }
    }
}

/// The empty circle that fills when done, as in Reminders.
private struct CompletionCircle: View {
    let done: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: done ? "largecircle.fill.circle" : "circle")
                .font(.title2)
                .foregroundStyle(done ? accent : Color(uiColor: .tertiaryLabel))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
    }
}

/// The drums of one set, right under it in the list: weight and reps (only reps without a weight).
private struct SetWheels: View {
    let block: WorkoutState.Block
    let item: WorkoutState.Item
    let set: WorkoutState.SetRow
    @ObservedObject var model: WorkoutModel

    var body: some View {
        Wheels(columns: columns) { selection in
            var message: [String: Any] = ["b": block.b, "i": item.i, "k": set.k]
            if let w = item.w, selection.count > 1 {
                if w.vals.indices.contains(selection[0]) { message["w"] = w.vals[selection[0]] }
                message["r"] = selection[1]
            } else if let r = selection.first {
                message["r"] = r
            }
            model.act("val", message)
        }
        .frame(height: 180)
        .listRowInsets(EdgeInsets())
    }

    private var columns: [WheelColumn] {
        var columns: [WheelColumn] = []
        if let w = item.w {
            let index = w.vals.indices.min(by: { abs(w.vals[$0] - set.w) < abs(w.vals[$1] - set.w) }) ?? 0
            columns.append(WheelColumn(rows: w.rows, units: [w.unit], label: w.label, selected: index))
        }
        let rows = (0...max(item.r.max, set.r)).map(String.init)
        columns.append(WheelColumn(rows: rows, units: item.r.units, label: item.r.label, selected: set.r))
        return columns
    }
}

/// The rest in the navigation bar: counting down (and past the end with a minus, in orange), or the time since the
/// first half of a superset.
private struct RestTimer: View {
    let rest: WorkoutState.Rest?
    let restLabel: String
    let noRestLabel: String
    let accent: Color

    var body: some View {
        if let rest {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let now = context.date.timeIntervalSince1970 * 1000
                if now - rest.start < 15 * 60 * 1000 {
                    if rest.kind == "trans" {
                        Label(clock((now - rest.start) / 1000), systemImage: "forward.fill")
                            .accessibilityLabel(noRestLabel)
                    } else {
                        let left = (rest.end - now) / 1000
                        Label(left >= 0 ? clock(left.rounded(.up)) : "−" + clock((-left).rounded(.up)), systemImage: "timer")
                            .foregroundStyle(left >= 0 ? accent : Color.orange)
                            .accessibilityLabel(restLabel)
                    }
                }
            }
            .labelStyle(.titleAndIcon)
            .font(.headline)
            .monospacedDigit()
        }
    }

    private func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
