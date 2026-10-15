import Foundation
import Observation

/// Device-level preferences. Kept in UserDefaults (not the library store)
/// because theme and goals are per-device choices.
@Observable
final class AppPreferences {
    private let defaults: UserDefaults

    var theme: ReadingTheme {
        didSet { defaults.set(theme.rawValue, forKey: Keys.theme) }
    }

    /// Minutes of reading to aim for each day.
    var dailyGoalMinutes: Int {
        didSet { defaults.set(dailyGoalMinutes, forKey: Keys.dailyGoal) }
    }

    /// Books to finish in the current calendar year.
    var annualBookGoal: Int {
        didSet { defaults.set(annualBookGoal, forKey: Keys.annualGoal) }
    }

    /// Identifies this device's reading-time rows in the synced library.
    let deviceID: String

    static let dailyGoalRange = 5...180
    static let annualGoalRange = 1...365

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = defaults.string(forKey: Keys.theme).flatMap(ReadingTheme.init(rawValue:)) ?? .paper
        #if DEBUG
        if let forced = ProcessInfo.processInfo.environment["CHICKEN_DEBUG_THEME"].flatMap(ReadingTheme.init(rawValue:)) {
            theme = forced
        }
        #endif
        let daily = defaults.integer(forKey: Keys.dailyGoal)
        dailyGoalMinutes = daily > 0 ? daily : 30
        let annual = defaults.integer(forKey: Keys.annualGoal)
        annualBookGoal = annual > 0 ? annual : 12
        if let existing = defaults.string(forKey: Keys.deviceID) {
            deviceID = existing
        } else {
            deviceID = UUID().uuidString
            defaults.set(deviceID, forKey: Keys.deviceID)
        }
    }

    // Same keys as Chicken 1.x so existing choices carry over.
    private enum Keys {
        static let theme = "Chicken.readingTheme"
        static let dailyGoal = "Chicken.dailyReadingMinutesGoal"
        static let annualGoal = "Chicken.annualBookGoal"
        static let deviceID = "Chicken.deviceID"
    }
}
