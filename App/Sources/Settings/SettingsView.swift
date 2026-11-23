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
    @State private var showingHardcoverToken = false
    @State private var hasHardcoverToken = CatalogTokenStore.hasHardcoverToken

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

            ChickenSection("Book Metadata") {
                ChickenRow {
                    HStack(spacing: 14) {
                        Image(systemName: "sparkles.rectangle.stack")
                            .font(.system(size: 17, weight: .light))
                            .foregroundStyle(palette.muted)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-fetch metadata")
                                .font(.chickenUI(15, weight: .semibold))
                                .foregroundStyle(palette.text)
                            Text("Fill missing synopses, covers, and details using Hardcover and Open Library.")
                                .font(.chickenUI(12))
                                .foregroundStyle(palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Toggle(
                            "Auto-fetch metadata",
                            isOn: Binding(
                                get: { library.preferences.autoEnrichMetadata },
                                set: { library.preferences.autoEnrichMetadata = $0 }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(palette.ribbon)
                    }
                }
                ChickenRow {
                    actionRow(
                        icon: "key",
                        title: "Hardcover API",
                        detail: hasHardcoverToken ? "Connected" : "Open Library only (optional token)",
                        button: "Configure"
                    ) { showingHardcoverToken = true }
                }
                ChickenRow(isLast: true) {
                    actionRow(
                        icon: "text.magnifyingglass",
                        title: "Enrich library",
                        detail: enrichDetail,
                        button: library.catalogEnrichState.isEnriching ? "Enriching…" : "Enrich"
                    ) { library.enrichMissingMetadata() }
                    .disabled(library.catalogEnrichState.isEnriching)
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
        .sheet(isPresented: $showingHardcoverToken, onDismiss: {
            hasHardcoverToken = CatalogTokenStore.hasHardcoverToken
        }) {
            NavigationStack {
                HardcoverTokenSheet()
            }
            .readingTheme(library.preferences.theme)
        }
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

    private var enrichDetail: String {
        switch library.catalogEnrichState {
        case .idle: return ""
        case .enriching(let completed, let total): return "\(completed) of \(total)"
        case .finished(let updated): return "Updated \(updated)"
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

private struct HardcoverTokenSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var token = CatalogTokenStore.loadHardcoverToken() ?? ""
    @State private var isTesting = false
    @State private var statusMessage: String?
    @State private var isError = false
    @State private var hasStoredToken = CatalogTokenStore.hasHardcoverToken

    var body: some View {
        ChickenPage(
            title: "Hardcover API",
            subtitle: "Optional personal token for richer metadata, series info, and high-resolution covers."
        ) {
            ChickenSection("Personal Access Token") {
                ChickenRow {
                    SecureField("Paste Hardcover API token", text: $token)
                        .font(.chickenMono(13))
                        .textFieldStyle(.plain)
                        .foregroundStyle(palette.text)
                }
                ChickenRow(isLast: true) {
                    HStack(spacing: 12) {
                        Button(isTesting ? "Testing…" : "Test & Save") {
                            Task { await testAndSave() }
                        }
                        .font(.chickenUI(13, weight: .semibold))
                        .inkProminentButton()
                        .disabled(isTesting || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if hasStoredToken {
                            Button("Remove", role: .destructive) {
                                CatalogTokenStore.deleteHardcoverToken()
                                token = ""
                                hasStoredToken = false
                                isError = false
                                statusMessage = "Token removed."
                            }
                            .font(.chickenUI(13, weight: .medium))
                            .buttonStyle(.glass)
                        }

                        Spacer()

                        if let url = URL(string: "https://hardcover.app/account/api") {
                            Link("Get token", destination: url)
                                .font(.chickenUI(13, weight: .medium))
                                .foregroundStyle(palette.ribbon)
                        }
                    }
                }
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.chickenUI(13))
                    .foregroundStyle(isError ? .red : palette.ribbon)
            }
        }
        .pageTitle("Hardcover API")
        .toolbar { SheetDoneButton { dismiss() } }
    }

    private func testAndSave() async {
        isTesting = true
        statusMessage = nil
        isError = false
        defer { isTesting = false }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let username = try await BookCatalogClient.shared.testHardcoverToken(trimmed)
            CatalogTokenStore.saveHardcoverToken(trimmed)
            hasStoredToken = true
            isError = false
            statusMessage = "Connected as @\(username)."
        } catch {
            isError = true
            statusMessage = error.localizedDescription
        }
    }
}
