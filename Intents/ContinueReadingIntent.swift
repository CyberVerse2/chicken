import AppIntents

struct ContinueReadingIntent: AppIntent {
    static var title: LocalizedStringResource = "Continue Reading"

    func perform() async throws -> some IntentResult {
        .result()
    }
}
