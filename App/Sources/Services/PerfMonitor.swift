import Foundation
import os

nonisolated enum PerfMonitor {
    static let enabled = ProcessInfo.processInfo.environment["CHICKEN_PERF_LOG"] == "1"
    private static let logger = Logger(subsystem: "cyberverse.Chicken", category: "perf")
    private static let signposter = OSSignposter(logger: logger)

    static func beginInterval(_ name: StaticString) -> OSSignpostIntervalState {
        signposter.beginInterval(name)
    }

    static func endInterval(_ name: StaticString, _ state: OSSignpostIntervalState) {
        signposter.endInterval(name, state)
    }

    static func log(_ event: String, ms: Double? = nil, bytes: Int? = nil, detail: String = "") {
        guard enabled else { return }
        var parts = [event]
        if let ms { parts.append(String(format: "ms=%.2f", ms)) }
        if let bytes { parts.append("bytes=\(bytes)") }
        if !detail.isEmpty { parts.append(detail) }
        logger.notice("\(parts.joined(separator: " "), privacy: .public)")
    }
}
