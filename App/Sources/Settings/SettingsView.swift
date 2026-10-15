import ChickenKit
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router: AppRouter?
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Query private var books: [Book]

    var body: some View {
        let preferences = library.preferences

        ChickenPage(title: "Settings") {
            ChickenSection("Reading theme") {
                ThemeSwatchPicker()
                    .padding(14)
            }

            ChickenSection("Goals", footer: "Reading time counts only while a book is open and in front of you.") {
                ChickenRow {
                    goalRow(
                        label: "Daily reading",
                        value: "\(preferences.dailyGoalMinutes)",
                        unit: "min",
                        canDecrease: preferences.dailyGoalMinutes > AppPreferences.dailyGoalRange.lowerBound,
                        canIncrease: preferences.dailyGoalMinutes < AppPreferences.dailyGoalRange.upperBound,
                        decrease: { preferences.dailyGoalMinutes -= 5 },
                        increase: { preferences.dailyGoalMinutes += 5 }
                    )
                }
                ChickenRow(isLast: true) {
                    goalRow(
                        label: "Books this year",
                        value: "\(preferences.annualBookGoal)",
                        unit: preferences.annualBookGoal == 1 ? "book" : "books",
                        canDecrease: preferences.annualBookGoal > AppPreferences.annualGoalRange.lowerBound,
                        canIncrease: preferences.annualBookGoal < AppPreferences.annualGoalRange.upperBound,
                        decrease: { preferences.annualBookGoal -= 1 },
                        increase: { preferences.annualBookGoal += 1 }
                    )
                }
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

            ChickenSection("Privacy") {
                ChickenRow(isLast: true) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "lock")
                            .font(.system(size: 18, weight: .light))
                            .foregroundStyle(palette.muted)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Everything stays on this device")
                                .font(.chickenSerif(16, weight: .semibold))
                                .foregroundStyle(palette.text)
                            Text("No account, no tracking, nothing sent anywhere. \(books.count) books · \(library.librarySizeDescription())")
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

    private func goalRow(
        label: String, value: String, unit: String,
        canDecrease: Bool, canIncrease: Bool,
        decrease: @escaping () -> Void, increase: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.chickenUI(13))
                    .foregroundStyle(palette.muted)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.chickenDisplay(26))
                        .foregroundStyle(palette.text)
                        .contentTransition(.numericText())
                    Text(unit)
                        .font(.chickenSerif(14, italic: true))
                        .foregroundStyle(palette.muted)
                }
                .monospacedDigit()
            }
            Spacer()
            GlassStepper(label: label, canDecrease: canDecrease, canIncrease: canIncrease, decrease: {
                withAnimation(.snappy) { decrease() }
            }, increase: {
                withAnimation(.snappy) { increase() }
            })
        }
    }

    private func actionRow(icon: String, title: String, detail: String, button: String, action: @escaping () -> Void) -> some View {
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
            Spacer(minLength: 8)
            Button(button, action: action)
                .font(.chickenUI(13, weight: .medium))
                .foregroundStyle(palette.text)
                .buttonStyle(.glass)
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
