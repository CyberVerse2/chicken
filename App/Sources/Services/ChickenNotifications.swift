import ChickenKit
import SwiftUI
import UserNotifications

/// The four things Chicken tells you about, and nothing else: a nudge on
/// days you haven't read, downloads you asked for, books added from a
/// shared folder on the Mac, and sync problems that need you. Each has its
/// own switch in Settings.
@MainActor
final class ChickenNotifications: NSObject {
    static let shared = ChickenNotifications()

    enum Kind: String, CaseIterable, Identifiable {
        case nudge, downloads, imports, sync
        var id: String { rawValue }
        var defaultsKey: String { "Chicken.notify.\(rawValue)" }
    }

    /// Sync problems worth an interruption: ones syncing can't get past
    /// without you.
    enum SyncProblem: String {
        case iCloudFull, signedOut
    }

    /// Where a tap on a notification goes, beyond opening a book.
    enum Place: String {
        case downloadedBooks, recentlyAdded, settings
    }

    private let center = UNUserNotificationCenter.current()
    private weak var library: LibraryStore?
    private let defaults = UserDefaults.standard

    private override init() {
        super.init()
    }

    // MARK: Switches

    func isOn(_ kind: Kind) -> Bool {
        defaults.object(forKey: kind.defaultsKey) as? Bool ?? true
    }

    func set(_ kind: Kind, on: Bool) {
        defaults.set(on, forKey: kind.defaultsKey)
        if kind == .nudge { scheduleNudges() }
    }

    // MARK: Start

    /// Called once the library is up. Asks for permission the first time,
    /// as you chose: the nudge is on from the start.
    func start(library: LibraryStore) {
        self.library = library
        center.delegate = self
        let askedKey = "Chicken.notify.asked"
        guard !defaults.bool(forKey: askedKey) else {
            refresh()
            return
        }
        defaults.set(true, forKey: askedKey)
        Task {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            refresh()
        }
    }

    /// Whether the system lets Chicken notify at all.
    func isAllowed() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    // MARK: Reading nudge

    /// Reading state may have changed (the app came forward or went away):
    /// note when you read, and reschedule the nudge around it.
    func refresh() {
        guard let library else { return }
        library.recomputeReadingStats()
        noteReadingTime(secondsToday: library.readingSecondsToday)
        scheduleNudges()
    }

    /// When you read, learned from when today's minutes go up: the start of
    /// each new stretch is a sample of your usual reading time.
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

    /// Minutes after midnight you usually start reading; evening until
    /// there's enough to go on.
    var usualReadingMinute: Int {
        let samples = (defaults.array(forKey: "Chicken.notify.samples") as? [Int] ?? []).sorted()
        guard samples.count >= 3 else { return 20 * 60 }
        let median = samples[samples.count / 2]
        // A few minutes before you'd usually sit down, on the quarter hour.
        return max(6 * 60, (median - 10) / 15 * 15)
    }

    /// The next three days' nudges, each only on a day you haven't read
    /// yet. Reading today cancels today's; a day's nudge is replaced the
    /// next time Chicken runs, so it names the book you're on then.
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
            // `CHICKEN_DEBUG_NUDGE=<seconds>` fires the next nudge that soon, for review.
            if let seconds = ProcessInfo.processInfo.environment["CHICKEN_DEBUG_NUDGE"].flatMap(Double.init) {
                if debugNudgeScheduled { continue }
                debugNudgeScheduled = true
                trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
            }
            #endif
            let request = UNNotificationRequest(identifier: ids[offset], content: content, trigger: trigger)
            center.add(request)
        }
    }

    // MARK: Downloads, imports, sync

    /// Books you chose to download are on this device now.
    func downloadsFinished(count: Int) {
        guard isOn(.downloads), count > 0 else { return }
        post(
            id: "downloads-\(UUID().uuidString)",
            title: "Ready to read offline",
            body: "\(count) \(count == 1 ? "book" : "books") downloaded to this \(Self.deviceName)",
            place: .downloadedBooks,
            sound: true
        )
    }

    /// Chicken picked up new books from a shared folder (on the Mac).
    func booksAdded(count: Int, from folder: String) {
        guard isOn(.imports), count > 0 else { return }
        post(
            id: "imports-\(UUID().uuidString)",
            title: "Added to your library",
            body: "\(count) \(count == 1 ? "book" : "books") from \(folder)",
            place: .recentlyAdded,
            sound: false
        )
    }

    /// Syncing can't continue without you. Each problem is told once, until
    /// `syncRecovered()` says it's gone.
    func syncProblem(_ problem: SyncProblem) {
        let key = "Chicken.notify.told.\(problem.rawValue)"
        guard isOn(.sync), !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        switch problem {
        case .iCloudFull:
            post(
                id: "sync-\(problem.rawValue)",
                title: "iCloud is full",
                body: "Progress on this \(Self.deviceName) isn't reaching your other devices. Free up iCloud space to keep syncing.",
                place: .settings,
                sound: true
            )
        case .signedOut:
            post(
                id: "sync-\(problem.rawValue)",
                title: "Signed out of iCloud",
                body: "Chicken is keeping everything on this \(Self.deviceName) until you sign back in.",
                place: .settings,
                sound: true
            )
        }
    }

    /// Syncing is back; a future problem will be told again.
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
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    static var deviceName: String {
        #if os(macOS)
        "Mac"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }

    // MARK: Taps

    private func open(_ userInfo: [AnyHashable: Any]) {
        if let link = (userInfo["link"] as? String).flatMap(URL.init(string:)),
           let destination = ChickenLink.destination(for: link) {
            AppRouter.shared.pendingDestination = destination
            return
        }
        guard let place = (userInfo["place"] as? String).flatMap(Place.init(rawValue:)) else { return }
        switch place {
        case .settings:
            AppRouter.shared.showingSettings = true
        case .downloadedBooks, .recentlyAdded:
            // The library shows the right shelf; see `chickenShowLibrary`.
            NotificationCenter.default.post(name: .chickenShowLibrary, object: nil, userInfo: ["place": place.rawValue])
        }
    }
}

extension ChickenNotifications: UNUserNotificationCenterDelegate {
    // The completion-handler forms: UIKit requires these to finish on the
    // main thread, which the async forms don't guarantee (a tap crashed).

    /// In the app, the nudge would only interrupt what you're reading; the
    /// others still show.
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

extension Notification.Name {
    /// A notification asked to show part of the library. `userInfo["place"]`
    /// is a `ChickenNotifications.Place` raw value: `downloadedBooks` (the
    /// On This Device filter) or `recentlyAdded`.
    static let chickenShowLibrary = Notification.Name("ChickenShowLibrary")
}
