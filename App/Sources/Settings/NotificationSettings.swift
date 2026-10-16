import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Settings › Notifications: one switch for each thing Chicken can tell
/// you, and a way back in if notifications are off for Chicken entirely.
struct NotificationSettingsSection: View {
    @Environment(\.palette) private var palette
    @Environment(\.scenePhase) private var scenePhase
    @State private var isAllowed = true
    @State private var switches: [ChickenNotifications.Kind: Bool] = [:]

    /// "Books added" joins these once Chicken imports from a folder on its
    /// own; today every import is one you start, so it would never fire.
    private let kinds: [ChickenNotifications.Kind] = [.nudge, .downloads, .sync]

    var body: some View {
        ChickenSection("Notifications") {
            if !isAllowed {
                ChickenRow {
                    HStack(spacing: 14) {
                        label(icon: "bell.slash", title: "Off for Chicken", detail: "Turn them on in System Settings")
                        Spacer(minLength: 8)
                        Button("Open", action: openSystemSettings)
                            .font(.chickenUI(13, weight: .medium))
                            .foregroundStyle(palette.text)
                            .buttonStyle(.glass)
                    }
                }
            }
            ForEach(Array(kinds.enumerated()), id: \.element) { index, kind in
                ChickenRow(isLast: index == kinds.count - 1) {
                    HStack(spacing: 14) {
                        label(icon: icon(kind), title: title(kind), detail: detail(kind))
                        Spacer(minLength: 8)
                        Toggle(title(kind), isOn: binding(kind))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(palette.ribbon)
                    }
                }
                .opacity(isAllowed ? 1 : 0.5)
            }
        }
        .task(id: scenePhase) {
            isAllowed = await ChickenNotifications.shared.isAllowed()
        }
    }

    private func binding(_ kind: ChickenNotifications.Kind) -> Binding<Bool> {
        Binding(
            get: { switches[kind] ?? ChickenNotifications.shared.isOn(kind) },
            set: {
                switches[kind] = $0
                ChickenNotifications.shared.set(kind, on: $0)
            }
        )
    }

    private func title(_ kind: ChickenNotifications.Kind) -> String {
        switch kind {
        case .nudge: "Reading nudge"
        case .downloads: "Downloads ready"
        case .imports: "Books added"
        case .sync: "Sync problems"
        }
    }

    private func detail(_ kind: ChickenNotifications.Kind) -> String {
        switch kind {
        case .nudge:
            let minute = ChickenNotifications.shared.usualReadingMinute
            let time = Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date())
                .map { $0.formatted(date: .omitted, time: .shortened) } ?? ""
            return "Days you haven't read, around \(time)"
        case .downloads: return "When books you download are ready offline"
        case .imports: return "Books picked up from a shared folder"
        case .sync: return "When syncing needs you"
        }
    }

    private func icon(_ kind: ChickenNotifications.Kind) -> String {
        switch kind {
        case .nudge: "book"
        case .downloads: "arrow.down.circle"
        case .imports: "tray.and.arrow.down"
        case .sync: "icloud"
        }
    }

    private func label(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(palette.muted)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.chickenSerif(16, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text(detail)
                    .font(.chickenUI(12))
                    .foregroundStyle(palette.muted)
                    .lineLimit(2)
            }
        }
    }

    private func openSystemSettings() {
        #if os(macOS)
        let id = Bundle.main.bundleIdentifier ?? "cyberverse.Chicken"
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
        #else
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}
