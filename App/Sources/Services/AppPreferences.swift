import ChickenKit
import Foundation
import Observation

/// Device-level preferences. Kept in UserDefaults (not the library store)
/// because theme and goals are per-device choices.
@Observable
final class AppPreferences {
    private let defaults: UserDefaults
    @ObservationIgnored var onWidgetRelevantChange: (() -> Void)?

    var theme: ReadingTheme {
        didSet {
            defaults.set(theme.rawValue, forKey: Keys.theme)
            if oldValue != theme { onWidgetRelevantChange?() }
        }
    }

    /// Minutes of reading to aim for each day.
    var dailyGoalMinutes: Int {
        didSet {
            let clamped = min(max(dailyGoalMinutes, Self.dailyGoalRange.lowerBound), Self.dailyGoalRange.upperBound)
            if dailyGoalMinutes != clamped {
                dailyGoalMinutes = clamped
                return
            }
            defaults.set(dailyGoalMinutes, forKey: Keys.dailyGoal)
            if oldValue != dailyGoalMinutes { onWidgetRelevantChange?() }
        }
    }

    /// Books to finish in the current calendar year.
    var annualBookGoal: Int {
        didSet {
            let clamped = min(max(annualBookGoal, Self.annualGoalRange.lowerBound), Self.annualGoalRange.upperBound)
            if annualBookGoal != clamped {
                annualBookGoal = clamped
                return
            }
            defaults.set(annualBookGoal, forKey: Keys.annualGoal)
            if oldValue != annualBookGoal { onWidgetRelevantChange?() }
        }
    }

    /// Identifies this device's reading-time rows in the synced library.
    let deviceID: String

    /// Download every book in iCloud to this device, new ones included.
    /// On by default on the Mac, which has the room.
    var downloadsAllBooks: Bool {
        didSet { defaults.set(downloadsAllBooks, forKey: Keys.downloadsAll) }
    }

    /// Books kept on this device: downloaded, and fetched again if the
    /// system clears them to free space.
    var keptBookIDs: Set<UUID> {
        didSet { defaults.set(keptBookIDs.map(\.uuidString), forKey: Keys.keptBooks) }
    }

    var minutesPerPage: Double {
        didSet {
            let clamped = min(max(minutesPerPage, ReadingEstimate.paceRange.lowerBound), ReadingEstimate.paceRange.upperBound)
            if minutesPerPage != clamped {
                minutesPerPage = clamped
                return
            }
            defaults.set(minutesPerPage, forKey: Keys.minutesPerPage)
        }
    }

    var autoEnrichMetadata: Bool {
        didSet { defaults.set(autoEnrichMetadata, forKey: Keys.autoEnrichMetadata) }
    }

    var hasCalibratedPace: Bool {
        defaults.object(forKey: Keys.minutesPerPage) != nil
    }

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
        dailyGoalMinutes = daily > 0
            ? min(max(daily, Self.dailyGoalRange.lowerBound), Self.dailyGoalRange.upperBound)
            : 30
        let annual = defaults.integer(forKey: Keys.annualGoal)
        annualBookGoal = annual > 0
            ? min(max(annual, Self.annualGoalRange.lowerBound), Self.annualGoalRange.upperBound)
            : 12
        #if os(macOS)
        downloadsAllBooks = defaults.object(forKey: Keys.downloadsAll) as? Bool ?? true
        #else
        downloadsAllBooks = defaults.object(forKey: Keys.downloadsAll) as? Bool ?? false
        #endif
        keptBookIDs = Set((defaults.stringArray(forKey: Keys.keptBooks) ?? []).compactMap(UUID.init(uuidString:)))
        let storedPace = defaults.double(forKey: Keys.minutesPerPage)
        minutesPerPage = storedPace > 0
            ? min(max(storedPace, ReadingEstimate.paceRange.lowerBound), ReadingEstimate.paceRange.upperBound)
            : ReadingEstimate.minutesPerPage
        autoEnrichMetadata = defaults.object(forKey: Keys.autoEnrichMetadata) as? Bool ?? true
        if let existing = defaults.string(forKey: Keys.deviceID) {
            deviceID = existing
        } else {
            deviceID = UUID().uuidString
            defaults.set(deviceID, forKey: Keys.deviceID)
        }
    }

    private enum Keys {
        static let theme = "Chicken.readingTheme"
        static let dailyGoal = "Chicken.dailyReadingMinutesGoal"
        static let annualGoal = "Chicken.annualBookGoal"
        static let deviceID = "Chicken.deviceID"
        static let downloadsAll = "Chicken.downloadsAllBooks"
        static let keptBooks = "Chicken.keptBooks"
        static let minutesPerPage = "Chicken.minutesPerPage"
        static let autoEnrichMetadata = "Chicken.autoEnrichMetadata"
    }
}
