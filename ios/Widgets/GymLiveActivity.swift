import ActivityKit
import SwiftUI
import WidgetKit

@main
struct GymWidgetsBundle: WidgetBundle {
    var body: some Widget {
        GymLiveActivity()
    }
}

/// The workout on the Lock Screen and in the Dynamic Island: what to do now, and the rest timer
/// counting down by itself while the phone sleeps.
struct GymLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GymAttributes.self) { context in
            LockScreenView(context: context)
        } dynamicIsland: { context in
            let s = context.state
            let stale = context.isStale
            let accent = Color(hexString: s.accent, fallback: .blue)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PhaseIcon(phase: s.phase, accent: accent)
                        .font(.title2)
                        .frame(maxHeight: .infinity)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    BigValue(state: s, stale: stale, accent: accent, size: 28)
                        .frame(maxHeight: .infinity)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 1) {
                        Text(headline(s, stale: stale))
                            .font(.headline)
                            .lineLimit(1)
                        Text(s.sub)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        if s.phase == "rest", let start = s.restStart, let end = s.restEnd {
                            RestBar(start: start, end: end, accent: stale ? Color.orange : accent)
                        }
                        if !s.detail.isEmpty {
                            Text(s.detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                PhaseIcon(phase: s.phase, accent: stale ? Color.orange : accent)
            } compactTrailing: {
                CompactValue(state: s, stale: stale, accent: accent)
            } minimal: {
                MinimalValue(state: s, stale: stale, accent: accent)
            }
            .keylineTint(accent)
        }
    }
}

/// «Отдых окончен» once the rest time is up, otherwise the title the app sent.
func headline(_ s: GymAttributes.ContentState, stale: Bool) -> String {
    s.phase == "rest" && stale && !s.overTitle.isEmpty ? s.overTitle : s.title
}

struct LockScreenView: View {
    let context: ActivityViewContext<GymAttributes>

    var body: some View {
        let s = context.state
        let stale = context.isStale
        let accent = Color(hexString: s.accent, fallback: .blue)
        let cap = s.phase == "rest" && stale && !s.overCap.isEmpty ? s.overCap : s.cap
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(accent)
                Text(s.workout)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(context.attributes.startedAt, style: .timer)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 90, alignment: .trailing)
            }
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline(s, stale: stale))
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(s.sub)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    BigValue(state: s, stale: stale, accent: accent, size: 36)
                    if !cap.isEmpty {
                        Text(cap)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            if s.phase == "rest", let start = s.restStart, let end = s.restEnd {
                RestBar(start: start, end: end, accent: stale ? Color.orange : accent)
            }
            if !s.detail.isEmpty {
                Text(s.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(16)
        .activitySystemActionForegroundColor(accent)
    }
}

/// The big number: the rest timer, the set («2/4»), or how many exercises are done.
struct BigValue: View {
    let state: GymAttributes.ContentState
    let stale: Bool
    let accent: Color
    var size: CGFloat = 34

    var body: some View {
        Group {
            switch state.phase {
            case "rest":
                if let end = state.restEnd {
                    RestTimerText(end: end, over: stale)
                        .foregroundStyle(stale ? Color.orange : accent)
                } else {
                    Text(verbatim: "—")
                }
            case "set":
                Text(verbatim: "\(state.setNo)/\(state.setTotal)")
                    .foregroundStyle(accent)
            case "trans":
                if let since = state.since {
                    Text(since, style: .timer)
                        .foregroundStyle(accent)
                } else {
                    Text(verbatim: "→")
                        .foregroundStyle(accent)
                }
            default:
                Text(verbatim: "\(state.done)/\(state.total)")
                    .foregroundStyle(accent)
            }
        }
        .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
        .multilineTextAlignment(.trailing)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: size * 3.2, alignment: .trailing)
    }
}

/// Counts down to the end of the rest; past the end it counts on with a minus in front, like the app does.
struct RestTimerText: View {
    let end: Date
    let over: Bool

    var body: some View {
        if over {
            Text(verbatim: "−") + Text(end, style: .timer)
        } else {
            Text(end, style: .timer)
        }
    }
}

struct CompactValue: View {
    let state: GymAttributes.ContentState
    let stale: Bool
    let accent: Color

    var body: some View {
        Group {
            if state.phase == "rest", let end = state.restEnd {
                RestTimerText(end: end, over: stale)
                    .foregroundStyle(stale ? Color.orange : accent)
                    .frame(width: stale ? 52 : 44, alignment: .trailing)
            } else if state.phase == "set" {
                Text(verbatim: "\(state.setNo)/\(state.setTotal)")
                    .foregroundStyle(accent)
            } else if state.phase == "trans", let since = state.since {
                Text(since, style: .timer)
                    .foregroundStyle(accent)
                    .frame(width: 44, alignment: .trailing)
            } else {
                Text(verbatim: "\(state.done)/\(state.total)")
                    .foregroundStyle(accent)
            }
        }
        .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
        .multilineTextAlignment(.trailing)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

struct MinimalValue: View {
    let state: GymAttributes.ContentState
    let stale: Bool
    let accent: Color

    var body: some View {
        if state.phase == "rest", let end = state.restEnd, !stale {
            Text(end, style: .timer)
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(accent)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 34)
        } else {
            PhaseIcon(phase: state.phase, accent: stale ? Color.orange : accent)
        }
    }
}

struct PhaseIcon: View {
    let phase: String
    let accent: Color

    var body: some View {
        Image(systemName: Self.symbol(for: phase))
            .foregroundStyle(accent)
    }

    static func symbol(for phase: String) -> String {
        switch phase {
        case "rest": return "timer"
        case "trans": return "forward.fill"
        default: return "dumbbell.fill"
        }
    }
}

/// The rest as a bar that empties by itself.
struct RestBar: View {
    let start: Date
    let end: Date
    let accent: Color

    var body: some View {
        ProgressView(timerInterval: start...end, countsDown: true) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.linear)
        .tint(accent)
    }
}
