import OSLog

public enum ChickenLog {
    public static let subsystem = "cyberverse.Chicken"

    public static let archive = Logger(subsystem: subsystem, category: "archive")
    public static let epub = Logger(subsystem: subsystem, category: "epub")
    public static let library = Logger(subsystem: subsystem, category: "library")
    public static let sync = Logger(subsystem: subsystem, category: "sync")
    public static let reader = Logger(subsystem: subsystem, category: "reader")
    public static let widgets = Logger(subsystem: subsystem, category: "widgets")
    public static let notifications = Logger(subsystem: subsystem, category: "notifications")
}
