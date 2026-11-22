import SwiftUI
import UserNotifications
#if os(macOS)
import AppKit
#endif

struct NotificationSettingsSection: View {
    @Environment(\.palette) private var palette
    @Environment(\.scenePhase) private var scenePhase
    @State private var status: UNAuthorizationStatus = .notDetermined

    private let notifications = ChickenNotifications.shared

    private var isAllowed: Bool {
        status == .authorized || status == .provisional
    }

    var body: some View {
        ChickenSection("Notifications") {
            if status == .notDetermined {
                ChickenRow {
                    HStack(spacing: 14) {
                        label(icon: "bell", title: "Allow notifications", detail: "Reading nudges, offline downloads, and sync alerts")
                        Spacer(minLength: 8)
                        Button("Allow") {
                            Task {
                                _ = await notifications.requestAuthorizationIfNeeded()
                                status = await notifications.authorizationStatus()
                            }
                        }
                        .font(.chickenUI(13, weight: .medium))
                        .foregroundStyle(palette.text)
                        .buttonStyle(.glass)
                    }
                }
            } else if !isAllowed {
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
            ForEach(Array(ChickenNotifications.Kind.allCases.enumerated()), id: \.element) { index, kind in
                ChickenRow(isLast: index == ChickenNotifications.Kind.allCases.count - 1) {
                    HStack(spacing: 14) {
                        label(icon: icon(kind), title: title(kind), detail: detail(kind))
                        Spacer(minLength: 8)
                        Toggle(title(kind), isOn: binding(kind))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(isAllowed ? palette.ribbon : palette.faint)
                            .disabled(status != .notDetermined && !isAllowed)
                    }
                }
                .opacity(isAllowed ? 1 : 0.62)
            }
        }
        .task(id: scenePhase) {
            status = await notifications.authorizationStatus()
        }
    }

    private func binding(_ kind: ChickenNotifications.Kind) -> Binding<Bool> {
        Binding(
            get: { notifications.isOn(kind) },
            set: { enabled in
                notifications.set(kind, on: enabled)
                if enabled && status == .notDetermined {
                    Task {
                        _ = await notifications.requestAuthorizationIfNeeded()
                        status = await notifications.authorizationStatus()
                    }
                }
            }
        )
    }

    private func title(_ kind: ChickenNotifications.Kind) -> String {
        switch kind {
        case .nudge: "Reading nudge"
        case .downloads: "Downloads ready"
        case .sync: "Sync problems"
        }
    }

    private func detail(_ kind: ChickenNotifications.Kind) -> String {
        switch kind {
        case .nudge:
            let minute = notifications.usualReadingMinute
            let time = Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date())
                .map { $0.formatted(date: .omitted, time: .shortened) } ?? ""
            return "Days you haven't read, around \(time)"
        case .downloads: return "When books you download are ready offline"
        case .sync: return "When syncing needs you"
        }
    }

    private func icon(_ kind: ChickenNotifications.Kind) -> String {
        switch kind {
        case .nudge: "book"
        case .downloads: "arrow.down.circle"
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
                    .font(.chickenUI(15, weight: .semibold))
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
