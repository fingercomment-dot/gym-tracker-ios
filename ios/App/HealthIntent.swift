import AppIntents
import Foundation

/// Apple Health through the Shortcuts app (web app 12.13+). The app has no HealthKit permission of its own (iloader
/// signs it without one), so a shortcut does the reading: «Найти образцы Здоровья» for sleep, heart rate variability,
/// resting pulse, running speed and walking + running distance, and this action takes their values and times. The
/// shortcut runs by an automation (when the app opens, or every morning); the instructions are in the web app's
/// Settings → «Здоровье». What comes in waits here until the page has saved it.
struct ImportHealthIntent: AppIntent {
    static var title: LocalizedStringResource = "Передать данные из «Здоровья»"
    static var description = IntentDescription("Сон по стадиям, вариабельность пульса, пульс в покое и пробежки — в Gym Tracker. Каждое поле — результат «Найти образцы Здоровья» и его свойство: значение, дата начала или окончания.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Сон — значения", description: "Анализ сна → Значение")
    var sleepValues: [String]?
    @Parameter(title: "Сон — начало", description: "Анализ сна → Дата начала")
    var sleepStarts: [Date]?
    @Parameter(title: "Сон — конец", description: "Анализ сна → Дата окончания")
    var sleepEnds: [Date]?
    @Parameter(title: "ВСР — значения", description: "Вариабельность сердечного ритма → Значение")
    var hrvValues: [Double]?
    @Parameter(title: "ВСР — время", description: "Вариабельность сердечного ритма → Дата начала")
    var hrvTimes: [Date]?
    @Parameter(title: "Пульс в покое — значения", description: "Пульс в покое → Значение")
    var restValues: [Double]?
    @Parameter(title: "Пульс в покое — время", description: "Пульс в покое → Дата начала")
    var restTimes: [Date]?
    @Parameter(title: "Скорость бега — время", description: "Скорость бега → Дата начала")
    var runTimes: [Date]?
    @Parameter(title: "Расстояние — значения", description: "Ходьба и бег → Значение")
    var distValues: [Double]?
    @Parameter(title: "Расстояние — время", description: "Ходьба и бег → Дата начала")
    var distTimes: [Date]?

    static var parameterSummary: some ParameterSummary {
        Summary("Передать в Gym Tracker") {
            \.$sleepValues
            \.$sleepStarts
            \.$sleepEnds
            \.$hrvValues
            \.$hrvTimes
            \.$restValues
            \.$restTimes
            \.$runTimes
            \.$distValues
            \.$distTimes
        }
    }

    func perform() async throws -> some IntentResult {
        let ms: (Date) -> Double = { ($0.timeIntervalSince1970 * 1000).rounded() }
        var item: [String: Any] = ["id": UUID().uuidString, "at": ms(Date())]
        if let values = sleepValues, let starts = sleepStarts, let ends = sleepEnds {
            item["sleep"] = ["v": values, "s": starts.map(ms), "e": ends.map(ms)]
        }
        if let values = hrvValues, let times = hrvTimes { item["hrv"] = ["v": values, "t": times.map(ms)] }
        if let values = restValues, let times = restTimes { item["rest"] = ["v": values, "t": times.map(ms)] }
        if let times = runTimes { item["run"] = ["t": times.map(ms)] }
        if let values = distValues, let times = distTimes { item["dist"] = ["v": values, "t": times.map(ms)] }
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
