import AppIntents
import ChickenKit

struct ContinueReadingIntent: AppIntent {
    static let title: LocalizedStringResource = "Continue Reading"
    static let description = IntentDescription("Opens the book you were reading most recently.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.pendingDestination = .continueReading
        return .result()
    }
}

struct ChickenShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ContinueReadingIntent(),
            phrases: [
                "Continue reading in \(.applicationName)",
                "Open my book in \(.applicationName)",
            ],
            shortTitle: "Continue Reading",
            systemImageName: "book"
        )
    }
}
