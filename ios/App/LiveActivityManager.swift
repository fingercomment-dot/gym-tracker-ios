import ActivityKit
import Foundation

/// The workout on the Lock Screen and in the Dynamic Island.
/// The web app sends the whole state each time something changes; nil means no workout is running.
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var lastSent: GymAttributes.ContentState?

    var isEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func apply(_ payload: [String: Any]?) {
        guard let payload, let sid = payload["sid"] as? String, !sid.isEmpty else {
            endAll()
            return
        }
        let state = Self.state(from: payload)
        // when the rest time is up the system marks the activity stale and redraws it as «Отдых окончен»
        let content = ActivityContent(state: state, staleDate: state.phase == "rest" ? state.restEnd : nil)
        let running = Activity<GymAttributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }

        if let current = running.first(where: { $0.attributes.sid == sid }) {
            for other in running where other.id != current.id {
                Task { await other.end(nil, dismissalPolicy: .immediate) }
            }
            guard state != lastSent else { return }
            lastSent = state
            Task { await current.update(content) }
            return
        }

        for other in running {
            Task { await other.end(nil, dismissalPolicy: .immediate) }
        }
        guard isEnabled else { return }
        do {
            let attributes = GymAttributes(sid: sid, startedAt: Self.date(payload["startedAt"]) ?? Date())
            _ = try Activity<GymAttributes>.request(attributes: attributes, content: content, pushType: nil)
            lastSent = state
        } catch {
            NSLog("Gym Tracker: Live Activity did not start: %@", error.localizedDescription)
        }
    }

    func endAll() {
        lastSent = nil
        for activity in Activity<GymAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    private static func date(_ value: Any?) -> Date? {
        guard let n = value as? NSNumber else { return nil }
        let ms = n.doubleValue
        return ms > 0 ? Date(timeIntervalSince1970: ms / 1000) : nil
    }

    private static func int(_ value: Any?) -> Int { (value as? NSNumber)?.intValue ?? 0 }

    private static func str(_ value: Any?) -> String { value as? String ?? "" }

    private static func state(from p: [String: Any]) -> GymAttributes.ContentState {
        var restStart = date(p["restStart"])
        var restEnd = date(p["restEnd"])
        if let a = restStart, let b = restEnd, b <= a { restStart = nil; restEnd = nil }
        return GymAttributes.ContentState(
            phase: str(p["phase"]),
            workout: str(p["workout"]),
            title: str(p["title"]),
            sub: str(p["sub"]),
            detail: str(p["detail"]),
            cap: str(p["cap"]),
            accent: str(p["accent"]),
            restStart: restStart,
            restEnd: restEnd,
            since: date(p["since"]),
            setNo: int(p["setNo"]),
            setTotal: int(p["setTotal"]),
            done: int(p["done"]),
            total: int(p["total"]),
            overTitle: str(p["overTitle"]),
            overCap: str(p["overCap"])
        )
    }
}
