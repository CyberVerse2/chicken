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
        ChickenPage(title: "Settings") {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Reading theme")
                ThemeSwatchPicker()
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
                            .font(.system(size: 17, weight: .light))
                            .foregroundStyle(palette.muted)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(privacy.title)
                                .font(.chickenUI(15, weight: .semibold))
                                .foregroundStyle(palette.text)
                            Text(library.iCloudStatus == .on ? privacy.detail : "\(privacy.detail) \(books.count) books · \(library.librarySizeDescription(for: books))")
                                .font(.chickenUI(13))
                                .foregroundStyle(palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            VStack(spacing: 6) {
                BrandLockup(size: 16)
                Text("Version \(Bundle.main.appVersion)")
                    .font(.chickenMono(11.5))
                    .foregroundStyle(palette.faint)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
        .pageTitle("Settings")
        #if !os(macOS)
        .toolbar { SheetDoneButton { dismiss() } }
        #endif
    }

    private var storageSection: some View {
        let downloaded = library.downloadedBooks(in: books)
        let downloadsAll = library.preferences.downloadsAllBooks
        return ChickenSection("Storage") {
            ChickenRow {
                HStack(spacing: 14) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 17, weight: .light))
                        .foregroundStyle(palette.muted)
                        .frame(width: 26)
                    Text("Download all books")
                        .font(.chickenUI(15, weight: .semibold))
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
                    actionRowLabel(icon: "internaldrive", title: "On this \(Platform.deviceName)", detail: storageDetail(downloaded))
                } else {
                    actionRow(icon: "internaldrive", title: "On this \(Platform.deviceName)", detail: storageDetail(downloaded), button: "Remove…") {
                        confirmingRemoveDownloads = true
                    }
                }
            }
        }
        .confirmationDialog("Remove downloaded books from this \(Platform.deviceName)?", isPresented: $confirmingRemoveDownloads, titleVisibility: .visible) {
            Button("Remove Downloads", role: .destructive) { library.removeDownload(books) }
        } message: {
            Text("They stay in iCloud. Books you keep on this \(Platform.deviceName) stay here.")
        }
    }

    private func storageDetail(_ downloaded: (count: Int, bytes: Int64)) -> String {
        "\(downloaded.count) of \(books.count) books · \(ByteCountFormatter.string(fromByteCount: downloaded.bytes, countStyle: .file))"
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
        router?.presentSheet(.discovery)
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
                    .font(.chickenUI(15, weight: .semibold))
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
