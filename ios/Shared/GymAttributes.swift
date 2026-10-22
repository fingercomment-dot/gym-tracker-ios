import ActivityKit
import Foundation

/// One workout on the Lock Screen and in the Dynamic Island.
/// The web app sends every line as ready-made text in its own language, so the widget needs no translations.
struct GymAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// "set" — doing a set, "rest" — resting, "trans" — superset, straight on to the next exercise,
        /// "intro" — about to start an exercise, "hub" — on the list of exercises.
        var phase: String
        /// The workout's name, e.g. «Тренировка A».
        var workout: String
        /// The big line: the exercise, or «Отдых».
        var title: String
        /// The line under it: «Подход 2 из 4», «Жим лёжа · подход 2 из 4».
        var sub: String
        /// What comes next: «60 кг × 8 раз», «Дальше: подход 3 · 60 кг × 8 раз».
        var detail: String
        /// The small caption under the big number: «подход», «из 2:30».
        var cap: String
        /// The app's accent colour, "#RRGGBB".
        var accent: String
        var restStart: Date?
        var restEnd: Date?
        /// When the current set (or the superset transition) began.
        var since: Date?
        var setNo: Int
        var setTotal: Int
        /// Exercises done and in total.
        var done: Int
        var total: Int
        /// Shown once the rest time is up: «Отдых окончен», «сверх отдыха».
        var overTitle: String
        var overCap: String
    }

    /// The workout's own id: a new workout means a new Live Activity.
    var sid: String
    var startedAt: Date
}
