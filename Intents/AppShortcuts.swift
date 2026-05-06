import AppIntents

struct ChickenShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ContinueReadingIntent(),
            phrases: ["Continue reading in \(.applicationName)"],
            shortTitle: "Continue",
            systemImageName: "book"
        )
    }
}
