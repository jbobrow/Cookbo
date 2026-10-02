import Foundation
import Combine
import SwiftUI
import UserNotifications
#if os(iOS) && canImport(AlarmKit)
import AlarmKit
#endif

/// A kitchen timer started from a recipe step.
struct CookTimer: Identifiable, Codable, Equatable {
    var id = UUID()
    let recipeID: UUID
    let recipeTitle: String
    let step: Int
    let label: String
    var end: Date
    /// Time left when it was paused from the lock screen or Dynamic Island.
    var pausedRemaining: TimeInterval?
    /// Run by the system (AlarmKit), which shows and rings it; otherwise a
    /// notification stands in for the alarm.
    var isSystemTimer: Bool?
    /// How long "More Minutes" adds when it goes off.
    var extraSeconds: Int?

    var isPaused: Bool { pausedRemaining != nil }

    func isDone(at date: Date) -> Bool { !isPaused && date >= end }

    func remainingText(at date: Date) -> String {
        let left = pausedRemaining ?? end.timeIntervalSince(date)
        let seconds = max(0, Int(left.rounded(.up)))
        if seconds == 0 { return "Done" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

/// Every running timer. On iOS 26 and later a timer is a system timer
/// (AlarmKit): its countdown shows in the Dynamic Island and on the lock
/// screen, it rings even on silent, and it's paused, snoozed or stopped from
/// there. Elsewhere, or if alarms aren't allowed, a notification goes off
/// instead. Either way a timer ends only when someone stops it.
@MainActor
final class CookTimerStore: ObservableObject {
    static let shared = CookTimerStore()

    @Published private(set) var timers: [CookTimer] = []

    private let defaultsKey = "cookTimers"
    private let alertPresenter = ForegroundAlertPresenter()
    #if os(iOS) && canImport(AlarmKit)
    /// Last state seen for each system timer, to spot pauses and snoozes.
    private var systemStates: [UUID: String] = [:]
    /// Timers being rescheduled, which briefly vanish from the system's list.
    private var rescheduling: Set<UUID> = []
    #endif

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode([CookTimer].self, from: data) {
            // A finished timer stays until it's cleared, but not forever
            let stale = Date().addingTimeInterval(-12 * 3600)
            timers = saved.filter { $0.isPaused || $0.end > stale }
        }
        UNUserNotificationCenter.current().delegate = alertPresenter
        watchSystemTimers()
    }

    func timer(for recipeID: UUID, step: Int, label: String) -> CookTimer? {
        timers.first { $0.recipeID == recipeID && $0.step == step && $0.label == label }
    }

    func timers(for recipeID: UUID) -> [CookTimer] {
        timers.filter { $0.recipeID == recipeID }
    }

    /// Whether this device shows timers itself (Dynamic Island, lock screen),
    /// so the app doesn't need to.
    var systemShowsTimers: Bool {
        #if os(iOS) && canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return AlarmManager.shared.authorizationState != .denied
        }
        #endif
        return false
    }

    func start(recipe: Recipe, step: Int, duration: CookDuration) {
        let timer = CookTimer(
            recipeID: recipe.id,
            recipeTitle: recipe.title,
            step: step,
            label: duration.label,
            end: Date().addingTimeInterval(TimeInterval(duration.seconds)),
            extraSeconds: duration.extraSeconds
        )
        timers.append(timer)
        save()

        #if os(iOS) && canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            Task {
                if await scheduleSystemTimer(timer) {
                    guard var scheduled = timers.first(where: { $0.id == timer.id }) else {
                        // Stopped while it was being set up
                        try? AlarmManager.shared.cancel(id: timer.id)
                        return
                    }
                    scheduled.isSystemTimer = true
                    update(scheduled)
                } else {
                    scheduleNotification(for: timer)
                }
            }
            return
        }
        #endif
        scheduleNotification(for: timer)
    }

    /// Stops a running timer, or clears a finished one.
    func stop(_ timer: CookTimer) {
        #if os(iOS) && canImport(AlarmKit)
        CookTimerStops.record(timer.id)
        #endif
        timers.removeAll { $0.id == timer.id }
        save()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [timer.id.uuidString])
        #if os(iOS) && canImport(AlarmKit)
        if #available(iOS 26.0, *), timer.isSystemTimer == true {
            try? AlarmManager.shared.cancel(id: timer.id)
        }
        #endif
    }

    private func update(_ timer: CookTimer) {
        guard let index = timers.firstIndex(where: { $0.id == timer.id }) else { return }
        timers[index] = timer
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(timers) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    // MARK: - System timers (AlarmKit)

    #if os(iOS) && canImport(AlarmKit)
    @available(iOS 26.0, *)
    private func scheduleSystemTimer(_ timer: CookTimer) async -> Bool {
        let manager = AlarmManager.shared
        if manager.authorizationState == .notDetermined {
            _ = try? await manager.requestAuthorization()
        }
        guard manager.authorizationState == .authorized else { return false }

        let extraMinutes = max(1, (timer.extraSeconds ?? 300) / 60)
        let moreButton = AlarmButton(text: "\(extraMinutes) More Minutes", textColor: .white, systemImageName: "goforward")
        let title: LocalizedStringResource = "Step \(timer.step + 1) · \(timer.label)"
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: title, secondaryButton: moreButton, secondaryButtonBehavior: .countdown)
        } else {
            alert = AlarmPresentation.Alert(
                title: title,
                stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill"),
                secondaryButton: moreButton,
                secondaryButtonBehavior: .countdown
            )
        }
        let presentation = AlarmPresentation(
            alert: alert,
            countdown: AlarmPresentation.Countdown(
                title: "\(timer.recipeTitle)",
                pauseButton: AlarmButton(text: "Pause", textColor: .orange, systemImageName: "pause.fill")
            ),
            paused: AlarmPresentation.Paused(
                title: "Paused",
                resumeButton: AlarmButton(text: "Resume", textColor: .orange, systemImageName: "play.fill")
            )
        )
        let attributes = AlarmAttributes<CookTimerMetadata>(
            presentation: presentation,
            metadata: CookTimerMetadata(recipeTitle: timer.recipeTitle, stepNumber: timer.step + 1, label: timer.label),
            tintColor: .orange
        )
        let configuration = AlarmManager.AlarmConfiguration<CookTimerMetadata>(
            // What's left, not the full time: answering the permission prompt
            // takes a few seconds, and the two countdowns should agree
            countdownDuration: Alarm.CountdownDuration(
                preAlert: max(1, timer.end.timeIntervalSinceNow),
                postAlert: TimeInterval(extraMinutes * 60)
            ),
            attributes: attributes,
            stopIntent: StopCookTimerIntent(id: timer.id)
        )
        do {
            _ = try await manager.schedule(id: timer.id, configuration: configuration)
            return true
        } catch {
            #if DEBUG
            print("Cook mode: couldn't schedule a system timer: \(error)")
            #endif
            return false
        }
    }

    /// Keeps the in-app copy in step with what happens on the lock screen and
    /// in the Dynamic Island: pause, resume, More Minutes, and Stop.
    private func watchSystemTimers() {
        guard #available(iOS 26.0, *) else { return }
        // Stopped from the alarm or the lock screen
        NotificationCenter.default.addObserver(forName: CookTimerStops.didStop, object: nil, queue: .main) { [weak self] note in
            guard let id = note.object as? UUID else { return }
            MainActor.assumeIsolated {
                guard let self, self.timers.contains(where: { $0.id == id }) else { return }
                self.timers.removeAll { $0.id == id }
                self.save()
            }
        }
        // Catch up on anything that happened while the app wasn't running
        if let alarms = try? AlarmManager.shared.alarms { sync(with: alarms) }
        refreshCountdownsAfterUpdate()
        Task { [weak self] in
            for await alarms in AlarmManager.shared.alarmUpdates {
                self?.sync(with: alarms)
            }
        }
    }

    /// Installing a new version of the app ends its Live Activities, so a
    /// running timer keeps counting and will ring, but its countdown vanishes
    /// from the lock screen and Dynamic Island. Scheduling it again with the
    /// time left brings the countdown back.
    @available(iOS 26.0, *)
    private func refreshCountdownsAfterUpdate() {
        let key = "cookTimersAppVersion"
        let modified = Bundle.main.executableURL
            .flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date }
        let version = "\(Bundle.main.infoDictionary?["CFBundleVersion"] ?? "")-\(modified?.timeIntervalSince1970 ?? 0)"
        defer { UserDefaults.standard.set(version, forKey: key) }
        guard UserDefaults.standard.string(forKey: key) != version else { return }

        let now = Date()
        for timer in timers where timer.isSystemTimer == true && !timer.isPaused && timer.end > now {
            rescheduling.insert(timer.id)
            Task {
                try? AlarmManager.shared.cancel(id: timer.id)
                if await !scheduleSystemTimer(timer) { scheduleNotification(for: timer) }
                rescheduling.remove(timer.id)
            }
        }
    }

    @available(iOS 26.0, *)
    private func sync(with alarms: [Alarm]) {
        let now = Date()
        let byID = Dictionary(uniqueKeysWithValues: alarms.map { ($0.id, $0) })
        var changed = false

        for var timer in timers where timer.isSystemTimer == true && !rescheduling.contains(timer.id) {
            guard let alarm = byID[timer.id] else {
                systemStates[timer.id] = nil
                if CookTimerStops.contains(timer.id) {
                    // Stopped from the alarm or the lock screen
                    timers.removeAll { $0.id == timer.id }
                    changed = true
                } else if !timer.isPaused, timer.end > now {
                    // Gone without anyone stopping it: put it back
                    timer.isSystemTimer = false
                    update(timer)
                    Task {
                        guard await scheduleSystemTimer(timer) else {
                            scheduleNotification(for: timer)
                            return
                        }
                        if var restored = timers.first(where: { $0.id == timer.id }) {
                            restored.isSystemTimer = true
                            update(restored)
                        }
                    }
                }
                // Otherwise it ran out and stays on screen as Done until cleared
                continue
            }
            let previous = systemStates[timer.id]
            let state = "\(alarm.state)"
            systemStates[timer.id] = state
            guard previous != state else { continue }

            switch alarm.state {
            case .paused where timer.pausedRemaining == nil:
                timer.pausedRemaining = max(0, timer.end.timeIntervalSince(now))
            case .countdown where previous == "\(Alarm.State.paused)":
                timer.end = now.addingTimeInterval(timer.pausedRemaining ?? 0)
                timer.pausedRemaining = nil
            case .countdown where previous == "\(Alarm.State.alerting)":
                // More Minutes
                timer.end = now.addingTimeInterval(alarm.countdownDuration?.postAlert ?? 300)
            case .alerting:
                timer.end = min(timer.end, now)
            default:
                continue
            }
            update(timer)
            changed = true
        }
        if changed { save() }
    }
    #else
    private func watchSystemTimers() {}
    #endif

    // MARK: - Notification fallback

    /// Permission is asked the first time someone starts a timer.
    private func scheduleNotification(for timer: CookTimer) {
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

/// Shows a timer's notification even while the app is open, since you may be
/// on another recipe when it goes off.
private final class ForegroundAlertPresenter: NSObject, UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
