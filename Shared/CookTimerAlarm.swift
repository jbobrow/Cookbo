// Shared by the app and the CookTimerWidget extension: what a cook mode timer
// carries into the system's AlarmKit countdown, and the actions behind the
// buttons on its Live Activity.

#if os(iOS) && canImport(AlarmKit)
import AlarmKit
import AppIntents
import Foundation

@available(iOS 26.0, *)
nonisolated struct CookTimerMetadata: AlarmMetadata {
    /// Opens cook mode at this timer's step.
    var url: URL? {
        guard let recipeID else { return nil }
        return URL(string: "cookbook://cook?recipe=\(recipeID.uuidString)&step=\(stepNumber)")
    }

    var recipeTitle: String
    /// For the link back into cook mode; nil on timers started before it existed
    var recipeID: UUID? = nil
    var stepNumber: Int
    /// "20–25 min"
    var label: String
}

/// Timers someone chose to stop. A system timer that disappears without being
/// in here (say, the app was reinstalled) gets put back with its time left,
/// because a timer only ends when someone stops it.
nonisolated enum CookTimerStops {
    private static let key = "cookTimersStoppedByUser"
    /// Posted with the timer's id when it's stopped from outside the app's UI.
    static let didStop = Notification.Name("CookTimerStopped")

    static func record(_ id: UUID) {
        var ids = UserDefaults.standard.stringArray(forKey: key) ?? []
        ids.append(id.uuidString)
        UserDefaults.standard.set(Array(ids.suffix(50)), forKey: key)
    }

    static func contains(_ id: UUID) -> Bool {
        UserDefaults.standard.stringArray(forKey: key)?.contains(id.uuidString) ?? false
    }
}

@available(iOS 26.0, *)
nonisolated struct PauseCookTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause Timer"
    static let isDiscoverable = false

    @Parameter(title: "Timer")
    var timerID: String

    init() {}
    init(id: UUID) { timerID = id.uuidString }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: timerID) { try AlarmManager.shared.pause(id: id) }
        return .result()
    }
}

@available(iOS 26.0, *)
nonisolated struct ResumeCookTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resume Timer"
    static let isDiscoverable = false

    @Parameter(title: "Timer")
    var timerID: String

    init() {}
    init(id: UUID) { timerID = id.uuidString }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: timerID) { try AlarmManager.shared.resume(id: id) }
        return .result()
    }
}

@available(iOS 26.0, *)
nonisolated struct StopCookTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Timer"
    static let isDiscoverable = false

    @Parameter(title: "Timer")
    var timerID: String

    init() {}
    init(id: UUID) { timerID = id.uuidString }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: timerID) {
            CookTimerStops.record(id)
            try? AlarmManager.shared.cancel(id: id)
            NotificationCenter.default.post(name: CookTimerStops.didStop, object: id)
        }
        return .result()
    }
}
#endif
