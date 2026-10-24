import AppIntents
import Foundation

/// Apple Health through the Shortcuts app (web app 12.13+). The app has no HealthKit permission of its own (iloader
/// signs it without one), so a shortcut does the reading: «Найти образцы Здоровья» for sleep and walking + running
/// distance (an iPhone alone writes these: time in bed, and the distance the page finds runs in by their pace), and
/// with an Apple Watch also heart rate variability, resting pulse and running speed; this action takes their values
/// and times. The shortcut runs by an automation (when the app opens, or every morning); the instructions are in the web app's
/// Settings → «Здоровье». What comes in waits here until the page has saved it.
struct ImportHealthIntent: AppIntent {
    static var title: LocalizedStringResource = "Передать данные из «Здоровья»"
    static var description = IntentDescription("Сон и пробежки, а с Apple Watch ещё стадии сна, вариабельность пульса и пульс в покое — в Gym Tracker. Каждое поле — результат «Найти образцы Здоровья» и его свойство: значение, дата начала или окончания.")
    static var openAppWhenRun: Bool = false

    // no parameter summary: Shortcuts then lists every field as a row, in this order — the shortcut's steps: what an
    // iPhone writes by itself first, then what only an Apple Watch writes
    @Parameter(title: "Сон — значения", description: "Анализ сна → Значение")
    var sleepValues: [String]?
    @Parameter(title: "Сон — начало", description: "Анализ сна → Дата начала")
    var sleepStarts: [Date]?
    @Parameter(title: "Сон — конец", description: "Анализ сна → Дата окончания")
    var sleepEnds: [Date]?
    @Parameter(title: "Расстояние — значения", description: "Ходьба и бег → Значение")
    var distValues: [Double]?
    @Parameter(title: "Расстояние — начало", description: "Ходьба и бег → Дата начала")
    var distTimes: [Date]?
    @Parameter(title: "Расстояние — конец", description: "Ходьба и бег → Дата окончания")
    var distEnds: [Date]?
    @Parameter(title: "ВСР — значения", description: "Вариабельность сердечного ритма → Значение (только с Apple Watch)")
    var hrvValues: [Double]?
    @Parameter(title: "ВСР — время", description: "Вариабельность сердечного ритма → Дата начала (только с Apple Watch)")
    var hrvTimes: [Date]?
    @Parameter(title: "Пульс в покое — значения", description: "Пульс в покое → Значение (только с Apple Watch)")
    var restValues: [Double]?
    @Parameter(title: "Пульс в покое — время", description: "Пульс в покое → Дата начала (только с Apple Watch)")
    var restTimes: [Date]?
    @Parameter(title: "Скорость бега — время", description: "Скорость бега → Дата начала (только с Apple Watch)")
    var runTimes: [Date]?

    func perform() async throws -> some IntentResult {
        let ms: (Date) -> Double = { ($0.timeIntervalSince1970 * 1000).rounded() }
        var item: [String: Any] = ["id": UUID().uuidString, "at": ms(Date())]
        if let values = sleepValues, let starts = sleepStarts, let ends = sleepEnds {
            let sleep: [String: Any] = ["v": values, "s": starts.map(ms), "e": ends.map(ms)]
            item["sleep"] = sleep
        }
        if let values = hrvValues, let times = hrvTimes {
            let hrv: [String: Any] = ["v": values, "t": times.map(ms)]
            item["hrv"] = hrv
        }
        if let values = restValues, let times = restTimes {
            let rest: [String: Any] = ["v": values, "t": times.map(ms)]
            item["rest"] = rest
        }
        if let times = runTimes {
            let run: [String: Any] = ["t": times.map(ms)]
            item["run"] = run
        }
        if let values = distValues, let times = distTimes {
            var dist: [String: Any] = ["v": values, "t": times.map(ms)]
            if let ends = distEnds { dist["e"] = ends.map(ms) }
            item["dist"] = dist
        }
        HealthInbox.add(item)
        await MainActor.run { NotificationCenter.default.post(name: HealthInbox.arrived, object: nil) }
        return .result()
    }
}

/// What the shortcut brought, kept until the page says it has saved it (`{type: "healthDone", ids}`).
enum HealthInbox {
    static let arrived = Notification.Name("gymHealthArrived")
    private static let key = "healthInbox"
    private static let lock = NSLock()

    static func add(_ item: [String: Any]) {
        lock.lock(); defer { lock.unlock() }
        var list = read()
        list.append(item)
        if list.count > 40 { list.removeFirst(list.count - 40) }
        write(list)
    }

    static func items() -> [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        return read()
    }

    static func remove(ids: [String]) {
        guard !ids.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        write(read().filter { !ids.contains($0["id"] as? String ?? "") })
    }

    private static func read() -> [[String: Any]] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return list
    }

    private static func write(_ list: [[String: Any]]) {
        guard let data = try? JSONSerialization.data(withJSONObject: list) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
