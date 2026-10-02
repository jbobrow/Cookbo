import Foundation
import Combine
import UserNotifications

/// A kitchen timer started from a recipe step.
struct CookTimer: Identifiable, Codable, Equatable {
    var id = UUID()
    let recipeID: UUID
    let recipeTitle: String
    let step: Int
    let label: String
    let end: Date

    func isDone(at date: Date) -> Bool { date >= end }

    func remainingText(at date: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(date).rounded(.up)))
        if seconds == 0 { return "Done" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

/// Every running timer, app-wide. A timer outlives cook mode, the recipe
/// page and the app itself (it's saved, and its alert is scheduled with the
/// system), and it ends only when someone stops it. A finished timer stays
/// until it's cleared, so a missed alert is still on screen.
@MainActor
final class CookTimerStore: ObservableObject {
    static let shared = CookTimerStore()

    @Published private(set) var timers: [CookTimer] = []

    private let defaultsKey = "cookTimers"
    private let alertPresenter = ForegroundAlertPresenter()

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode([CookTimer].self, from: data) {
            timers = saved
        }
        UNUserNotificationCenter.current().delegate = alertPresenter
    }

    func timers(for recipeID: UUID) -> [CookTimer] {
        timers.filter { $0.recipeID == recipeID }
    }

    func timer(for recipeID: UUID, step: Int) -> CookTimer? {
        timers.first { $0.recipeID == recipeID && $0.step == step }
    }

    func start(recipe: Recipe, step: Int, duration: CookDuration) {
        let timer = CookTimer(
            recipeID: recipe.id,
            recipeTitle: recipe.title,
            step: step,
            label: duration.label,
            end: Date().addingTimeInterval(TimeInterval(duration.seconds))
        )
        timers.append(timer)
        save()
        scheduleAlert(for: timer)
    }

    /// Stops a running timer, or clears a finished one.
    func stop(_ timer: CookTimer) {
        timers.removeAll { $0.id == timer.id }
        save()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [timer.id.uuidString])
    }

    private func save() {
        if let data = try? JSONEncoder().encode(timers) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    /// Permission is asked the first time someone starts a timer.
    private func scheduleAlert(for timer: CookTimer) {
        let interval = timer.end.timeIntervalSinceNow
        guard interval > 1 else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = "Timer done"
            content.body = "\(timer.recipeTitle) · Step \(timer.step + 1) · \(timer.label)"
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: timer.id.uuidString,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            )
            try? await center.add(request)
        }
    }
}

/// Shows a timer's alert even while the app is open, since you may be on
/// another recipe when it goes off.
private final class ForegroundAlertPresenter: NSObject, UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
