import ChickenKit
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router: AppRouter?
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Query private var books: [Book]
    @State private var confirmingRemoveDownloads = false

    var body: some View {
        let preferences = library.preferences

        ChickenPage(title: "Settings") {
            ChickenSection("Reading theme") {
                ThemeSwatchPicker()
                    .padding(14)
            }

            ChickenSection("Library") {
                ChickenRow {
                    actionRow(
                        icon: "folder",
                        title: "Shared folders",
                        detail: library.folders.isEmpty ? "None yet" : library.folders.map(\.name).joined(separator: ", "),
                        button: "Manage"
                    ) { openDiscovery() }
                }
                ChickenRow(isLast: true) {
                    actionRow(
                        icon: "photo.on.rectangle.angled",
                        title: "Covers",
                        detail: coverDetail,
                        button: library.coverRefreshState.isRefreshing ? "Refreshing…" : "Refresh"
                    ) { library.refreshAllCovers() }
                    .disabled(library.coverRefreshState.isRefreshing)
                }
            }

            if library.iCloudStatus == .on {
                storageSection
            }

            NotificationSettingsSection()

            ChickenSection("Privacy") {
                ChickenRow(isLast: true) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: privacy.icon)
                            .font(.system(size: 18, weight: .light))
                            .foregroundStyle(palette.muted)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(privacy.title)
                                .font(.chickenSerif(16, weight: .semibold))
                                .foregroundStyle(palette.text)
                            // With iCloud on, Storage says how many books are here.
                            Text(library.iCloudStatus == .on ? privacy.detail : "\(privacy.detail) \(books.count) books · \(library.librarySizeDescription())")
                                .font(.chickenUI(13))
                                .foregroundStyle(palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            VStack(spacing: 8) {
                BrandLockup(size: 16)
                Text("Version \(Bundle.main.appVersion)")
                    .font(.chickenSerif(12, italic: true))
                    .foregroundStyle(palette.faint)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
        .pageTitle("Settings")
        #if !os(macOS)
        .toolbar { SheetDoneButton { dismiss() } }
        #endif
        .animation(.easeInOut(duration: 0.3), value: library.preferences.theme)
    }

    /// Books whose files are on this device, and the switch that brings
    /// them all down.
    private var storageSection: some View {
        let downloaded = library.downloadedBooks()
        let downloadsAll = library.preferences.downloadsAllBooks
        return ChickenSection("Storage") {
            ChickenRow {
                HStack(spacing: 14) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 17, weight: .light))
                        .foregroundStyle(palette.muted)
                        .frame(width: 26)
                    Text("Download all books")
                        .font(.chickenSerif(16, weight: .semibold))
                        .foregroundStyle(palette.text)
                    Spacer(minLength: 8)
                    Toggle("Download all books", isOn: Binding(get: { downloadsAll }, set: { library.setDownloadsAllBooks($0) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(palette.ribbon)
                }
            }
            ChickenRow(isLast: true) {
                if downloadsAll || downloaded.count == 0 {
                    actionRowLabel(icon: "internaldrive", title: "On this \(Self.deviceName)", detail: storageDetail(downloaded))
                } else {
                    actionRow(icon: "internaldrive", title: "On this \(Self.deviceName)", detail: storageDetail(downloaded), button: "Remove…") {
                        confirmingRemoveDownloads = true
                    }
                }
            }
        }
        .confirmationDialog("Remove downloaded books from this \(Self.deviceName)?", isPresented: $confirmingRemoveDownloads, titleVisibility: .visible) {
            Button("Remove Downloads", role: .destructive) { library.removeDownload(books) }
        } message: {
            Text("They stay in iCloud. Books you keep on this \(Self.deviceName) stay here.")
        }
    }

    private func storageDetail(_ downloaded: (count: Int, bytes: Int64)) -> String {
        "\(downloaded.count) of \(books.count) books · \(ByteCountFormatter.string(fromByteCount: downloaded.bytes, countStyle: .file))"
    }

    private static var deviceName: String {
        #if os(macOS)
        "Mac"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }

    private var privacy: (icon: String, title: String, detail: String) {
        switch library.iCloudStatus {
        case .on:
            return ("icloud", "Synced with your iCloud", "Books, progress, and highlights sync through your own iCloud account. No Chicken account, no tracking.")
        case .unavailable:
            return ("icloud.slash", "Everything stays on this device", "To sync with your other devices, sign in to iCloud and turn it on for Chicken.")
        case .off, .checking:
            return ("lock", "Everything stays on this device", "No account, no tracking, nothing sent anywhere.")
        }
    }

    private var coverDetail: String {
        switch library.coverRefreshState {
        case .idle: return ""
        case .refreshing(let completed, let total): return "\(completed) of \(total)"
        case .finished(let refreshed): return "Refreshed \(refreshed)"
        }
    }

    private func openDiscovery() {
        #if os(macOS)
        router?.showingDiscovery = true
        #else
        dismiss()
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            router?.showingDiscovery = true
        }
        #endif
    }

    private func actionRow(icon: String, title: String, detail: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            actionRowLabel(icon: icon, title: title, detail: detail)
            Spacer(minLength: 8)
            Button(button, action: action)
                .font(.chickenUI(13, weight: .medium))
                .foregroundStyle(palette.text)
                .buttonStyle(.glass)
        }
    }

    private func actionRowLabel(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(palette.muted)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.chickenSerif(16, weight: .semibold))
                    .foregroundStyle(palette.text)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.chickenUI(12))
                        .foregroundStyle(palette.muted)
                        .lineLimit(2)
                }
            }
        }
    }
}

extension Bundle {
    var appVersion: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }
}
