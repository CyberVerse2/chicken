import ChickenKit
import Observation
import os
import SwiftUI
import UserNotifications

@Observable
final class ChickenNotifications: NSObject {
    static let shared = ChickenNotifications()

    enum Kind: String, CaseIterable, Identifiable {
        case nudge, downloads, sync
        var id: String { rawValue }
        var defaultsKey: String { "Chicken.notify.\(rawValue)" }
    }

    enum SyncProblem: String {
        case iCloudFull, signedOut
    }

    enum Place: String, Equatable {
        case downloadedBooks, settings
    }

    private(set) var enabledKinds: Set<Kind>

    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    @ObservationIgnored private weak var library: LibraryStore?
    @ObservationIgnored private let defaults = UserDefaults.standard

    private override init() {
        let defaults = UserDefaults.standard
        enabledKinds = Set(Kind.allCases.filter { defaults.object(forKey: $0.defaultsKey) as? Bool ?? true })
        super.init()
    }

    func isOn(_ kind: Kind) -> Bool {
        enabledKinds.contains(kind)
    }

    func set(_ kind: Kind, on: Bool) {
        if on {
            enabledKinds.insert(kind)
        } else {
            enabledKinds.remove(kind)
        }
        defaults.set(on, forKey: kind.defaultsKey)
        if kind == .nudge { scheduleNudges() }
    }

    func start(library: LibraryStore) {
        self.library = library
        center.delegate = self
        refresh()
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        let status = await authorizationStatus()
        if status == .authorized || status == .provisional { return true }
        guard status == .notDetermined else { return false }
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            if granted { refresh() }
            return granted
        } catch {
            ChickenLog.notifications.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func isAllowed() async -> Bool {
        let status = await authorizationStatus()
        return status == .authorized || status == .provisional
    }

    func refresh() {
        guard let library else { return }
        library.recomputeReadingStats()
        noteReadingTime(secondsToday: library.readingSecondsToday)
        scheduleNudges()
    }

    private func noteReadingTime(secondsToday: Int) {
        let today = ReadingLog.dayKey(for: Date())
        let seenDay = defaults.string(forKey: "Chicken.notify.seenDay")
        let seen = seenDay == today ? defaults.integer(forKey: "Chicken.notify.seenSeconds") : 0
        defer {
            defaults.set(today, forKey: "Chicken.notify.seenDay")
            defaults.set(secondsToday, forKey: "Chicken.notify.seenSeconds")
        }
        let added = secondsToday - seen
        guard added >= 120 else { return }
        let started = Date().addingTimeInterval(-Double(added))
        let parts = Calendar.current.dateComponents([.hour, .minute], from: started)
        let minute = (parts.hour ?? 20) * 60 + (parts.minute ?? 0)
        var samples = defaults.array(forKey: "Chicken.notify.samples") as? [Int] ?? []
        samples.append(minute)
        defaults.set(Array(samples.suffix(20)), forKey: "Chicken.notify.samples")
    }

    var usualReadingMinute: Int {
        let samples = (defaults.array(forKey: "Chicken.notify.samples") as? [Int] ?? []).sorted()
        guard samples.count >= 3 else { return 20 * 60 }
        let median = samples[samples.count / 2]
        return max(6 * 60, (median - 10) / 15 * 15)
    }

    private func scheduleNudges() {
        let ids = (0..<3).map { "nudge-\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard isOn(.nudge), let library, let book = library.continueReadingBook() else { return }
        let goal = library.preferences.dailyGoalMinutes
        let calendar = Calendar.current
        let minute = usualReadingMinute
        let now = Date()
        #if DEBUG
        var debugNudgeScheduled = false
        #endif

        for offset in 0..<3 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                  let fire = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day)
            else { continue }
            if offset == 0 && (library.readingSecondsToday > 0 || fire < now.addingTimeInterval(300)) { continue }

            let content = UNMutableNotificationContent()
            content.title = book.displayTitle
            let chapter = book.lastChapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let goalLine = "\(goal) minutes reaches today's goal"
            content.body = chapter.isEmpty ? goalLine : "\(chapter) · \(goalLine)"
            content.threadIdentifier = "nudge"
            content.userInfo = ["link": ChickenLink.book(book.id).absoluteString]

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            var trigger: UNNotificationTrigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            #if DEBUG
            if let seconds = ProcessInfo.processInfo.environment["CHICKEN_DEBUG_NUDGE"].flatMap(Double.init) {
                if debugNudgeScheduled { continue }
                debugNudgeScheduled = true
                trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
            }
            #endif
            let request = UNNotificationRequest(identifier: ids[offset], content: content, trigger: trigger)
            center.add(request) { error in
                if let error {
                    ChickenLog.notifications.error("Failed to schedule nudge: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    func downloadsFinished(count: Int) {
        guard isOn(.downloads), count > 0 else { return }
        post(
            id: "downloads-\(UUID().uuidString)",
            title: "Ready to read offline",
            body: "\(count) \(count == 1 ? "book" : "books") downloaded to this \(Platform.deviceName)",
            place: .downloadedBooks,
            sound: true
        )
    }

    func syncProblem(_ problem: SyncProblem) {
        let key = "Chicken.notify.told.\(problem.rawValue)"
        guard isOn(.sync), !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        switch problem {
        case .iCloudFull:
            post(
                id: "sync-\(problem.rawValue)",
                title: "iCloud is full",
                body: "Progress on this \(Platform.deviceName) isn't reaching your other devices. Free up iCloud space to keep syncing.",
                place: .settings,
                sound: true
            )
        case .signedOut:
            post(
                id: "sync-\(problem.rawValue)",
                title: "Signed out of iCloud",
                body: "Chicken is keeping everything on this \(Platform.deviceName) until you sign back in.",
                place: .settings,
                sound: true
            )
        }
    }

    func syncRecovered() {
        for problem in [SyncProblem.iCloudFull, .signedOut] {
            defaults.removeObject(forKey: "Chicken.notify.told.\(problem.rawValue)")
        }
        center.removeDeliveredNotifications(withIdentifiers: ["sync-iCloudFull", "sync-signedOut"])
    }

    private func post(id: String, title: String, body: String, place: Place, sound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound ? .default : nil
        content.threadIdentifier = place.rawValue
        content.userInfo = ["place": place.rawValue]
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { error in
            if let error {
                ChickenLog.notifications.error("Failed to post notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func open(_ userInfo: [AnyHashable: Any]) {
        if let link = (userInfo["link"] as? String).flatMap(URL.init(string:)),
           let destination = ChickenLink.destination(for: link) {
            AppRouter.shared.pendingDestination = destination
            return
        }
        guard let place = (userInfo["place"] as? String).flatMap(Place.init(rawValue:)) else { return }
        switch place {
        case .settings:
            AppRouter.shared.activeSheet = .settings
        case .downloadedBooks:
            AppRouter.shared.pendingLibraryPlace = .downloadedBooks
        }
    }
}

extension ChickenNotifications: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let isNudge = notification.request.content.threadIdentifier == "nudge"
        nonisolated(unsafe) let complete = completionHandler
        DispatchQueue.main.async {
            complete(isNudge ? [] : [.banner, .list, .sound])
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        nonisolated(unsafe) let info = response.notification.request.content.userInfo
        nonisolated(unsafe) let complete = completionHandler
        DispatchQueue.main.async {
            MainActor.assumeIsolated { ChickenNotifications.shared.open(info) }
            complete()
        }
    }
}
