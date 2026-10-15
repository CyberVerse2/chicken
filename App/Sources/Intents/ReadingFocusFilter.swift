import AppIntents
import Foundation

/// A Focus filter: set up a Reading (or Sleep, or any) Focus to change how
/// Chicken looks while it's on, say Ink and no controls at night, and
/// Chicken puts things back when the Focus ends.
struct ReadingFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Set Reading Style"
    static let description: IntentDescription? = IntentDescription("Choose a theme, and whether books open with the controls hidden, while this Focus is on.")

    @Parameter(title: "Theme")
    var theme: FocusTheme?

    @Parameter(title: "Hide reader controls", default: false)
    var hidesControls: Bool

    var displayRepresentation: DisplayRepresentation {
        let parts = [theme.map { "\($0.label) theme" }, hidesControls ? "Controls hidden" : nil].compactMap { $0 }
        return DisplayRepresentation(
            title: "Reading Style",
            subtitle: parts.isEmpty ? "No changes" : "\(parts.joined(separator: " · "))"
        )
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        ReadingFocus.apply(theme: theme?.readingTheme, hidesControls: hidesControls)
        return .result()
    }
}

nonisolated enum FocusTheme: String, AppEnum {
    case paper, sepia, ink

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Theme"
    static let caseDisplayRepresentations: [FocusTheme: DisplayRepresentation] = [
        .paper: "Paper",
        .sepia: "Sepia",
        .ink: "Ink",
    ]

    nonisolated var label: String {
        switch self {
        case .paper: "Paper"
        case .sepia: "Sepia"
        case .ink: "Ink"
        }
    }

    @MainActor var readingTheme: ReadingTheme {
        switch self {
        case .paper: .paper
        case .sepia: .sepia
        case .ink: .ink
        }
    }
}

/// What the active Focus asks of Chicken, and the theme to go back to.
@MainActor
enum ReadingFocus {
    private static let defaults = UserDefaults.standard
    private static let themeKey = "Chicken.focus.previousTheme"
    private static let controlsKey = "Chicken.focus.hidesControls"

    /// Books open with the controls hidden while the Focus is on.
    static var hidesControls: Bool { defaults.bool(forKey: controlsKey) }

    static func apply(theme: ReadingTheme?, hidesControls: Bool) {
        let preferences = LibraryStore.shared.preferences
        if let theme {
            // Remember the reader's own theme once, so a second filter
            // change doesn't overwrite it with the Focus theme.
            if defaults.string(forKey: themeKey) == nil {
                defaults.set(preferences.theme.rawValue, forKey: themeKey)
            }
            preferences.theme = theme
        } else if let previous = defaults.string(forKey: themeKey).flatMap(ReadingTheme.init(rawValue:)) {
            preferences.theme = previous
            defaults.removeObject(forKey: themeKey)
        }
        defaults.set(hidesControls, forKey: controlsKey)
    }
}
