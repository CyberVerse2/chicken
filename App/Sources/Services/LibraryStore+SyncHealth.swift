import CloudKit
import CoreData
import Foundation

/// Problems that stop syncing and need the user: iCloud full (for the
/// database or for book files) and signing out. Each is told once through
/// `ChickenNotifications`; recovery is only declared when the database
/// uploads again with nothing else wrong, so a problem that persists across
/// launches isn't told every launch.
extension LibraryStore {
    func watchSyncHealth() {
        cloudObservers.append(NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
                  event.type == .export, event.endDate != nil else { return }
            let full = Self.isQuotaError(event.error)
            let succeeded = event.succeeded
            MainActor.assumeIsolated { self?.cloudKitExportEnded(succeeded: succeeded, full: full) }
        })
        cloudObservers.append(NotificationCenter.default.addObserver(
            forName: .NSUbiquityIdentityDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.iCloudAccountChanged() }
        })
    }

    func iCloudFilesOverQuota(_ overQuota: Bool) {
        if overQuota {
            let inserted = syncIssues.insert(.filesFull).inserted
            guard inserted else { return }
            hasCompletedHealthyExport = false
            ChickenNotifications.shared.syncProblem(.iCloudFull)
        } else {
            syncIssues.remove(.filesFull)
        }
    }

    private func cloudKitExportEnded(succeeded: Bool, full: Bool) {
        if full {
            syncIssues.insert(.databaseFull)
            hasCompletedHealthyExport = false
            ChickenNotifications.shared.syncProblem(.iCloudFull)
        } else if succeeded {
            syncIssues.remove(.databaseFull)
            if syncIssues.isEmpty && downloadedCloudCovers != nil {
                declareSyncHealthy()
            }
        }
    }

    private func iCloudAccountChanged() {
        let signedIn = FileManager.default.ubiquityIdentityToken != nil
        if !signedIn {
            guard iCloudStatus == .on else { return }
            disconnectICloud()
            syncIssues.insert(.signedOut)
            hasCompletedHealthyExport = false
            ChickenNotifications.shared.syncProblem(.signedOut)
        } else if iCloudStatus == .unavailable {
            syncIssues.remove(.signedOut)
            connectToICloud()
        }
    }

    private func declareSyncHealthy() {
        guard !hasCompletedHealthyExport else { return }
        hasCompletedHealthyExport = true
        ChickenNotifications.shared.syncRecovered()
    }

    private nonisolated static func isQuotaError(_ error: Error?) -> Bool {
        guard let error = error as? CKError else { return false }
        if error.code == .quotaExceeded { return true }
        return error.partialErrorsByItemID?.values.contains { ($0 as? CKError)?.code == .quotaExceeded } ?? false
    }
}
