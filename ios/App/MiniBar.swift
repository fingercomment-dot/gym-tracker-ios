import SwiftUI

/// A minimised workout, as the page describes it (`{type: "mini", show, t, letter, c, on, startedAt, rest, label, …}`).
final class MiniModel: ObservableObject {
    @Published var title = ""
    @Published var letter = ""
    @Published var color: Color = .blue
    @Published var onColor: Color = .white
    @Published var startedAt: Double = 0
    @Published var rest: (start: Double, end: Double)?
    @Published var label = ""
    @Published var restLabel = ""
    @Published var overLabel = ""
    @Published var warn = false
    @Published var openLabel = ""
    @Published var accent: Color = .accentColor
    var send: (([String: Any]) -> Void)?

    func update(_ body: [String: Any]) {
        title = body["t"] as? String ?? ""
        letter = body["letter"] as? String ?? ""
        color = Color(hexString: body["c"] as? String ?? "", fallback: .blue)
        onColor = Color(hexString: body["on"] as? String ?? "", fallback: .white)
        startedAt = (body["startedAt"] as? NSNumber)?.doubleValue ?? 0
        if let r = body["rest"] as? [String: Any], let start = (r["start"] as? NSNumber)?.doubleValue, let end = (r["end"] as? NSNumber)?.doubleValue {
            rest = (start, end)
        } else {
            rest = nil
        }
        label = body["label"] as? String ?? ""
        restLabel = body["restT"] as? String ?? ""
        overLabel = body["overT"] as? String ?? ""
        warn = (body["warn"] as? Bool) ?? false
        openLabel = body["open"] as? String ?? ""
    }

    func open() { send?(["type": "mini", "a": "open"]) }
}

/// The player bar over the tab bar (like Music's): the workout's badge and name, the rest counting down or the time
/// it has been going; a tap opens the workout.
struct MiniBarView: View {
    @ObservedObject var model: MiniModel

    var body: some View {
        Button {
            model.open()
        } label: {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let now = context.date.timeIntervalSince1970 * 1000
                let line = Self.line(model, now: now)
                HStack(spacing: 12) {
                    Text(model.letter)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(model.onColor)
                        .frame(width: 28, height: 28)
                        .background(model.color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(model.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(line.label).font(.caption).foregroundStyle(line.over || model.warn ? Color.orange : Color.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(line.clock)
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(line.over ? Color.orange : line.resting ? model.accent : Color.primary)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.openLabel)
        .accessibilityIdentifier("mini.open")
    }

    private struct Line {
        let label: String
        let clock: String
        let resting: Bool
        let over: Bool
    }

    private static func line(_ m: MiniModel, now: Double) -> Line {
        if let rest = m.rest, now - rest.start < 15 * 60 * 1000 {
            let left = (rest.end - now) / 1000
            if left >= 0 { return Line(label: m.restLabel, clock: clock(left.rounded(.up)), resting: true, over: false) }
            return Line(label: m.overLabel, clock: "−" + clock((-left).rounded(.up)), resting: false, over: true)
        }
        let s = max(0, Int((now - m.startedAt) / 1000))
        let text = s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
        return Line(label: m.label, clock: text, resting: false, over: false)
    }

    private static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
