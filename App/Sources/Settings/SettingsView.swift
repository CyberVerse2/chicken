import ChickenKit
import SwiftUI

struct SettingsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router: AppRouter?
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var preferences = library.preferences

        Form {
            Section("Appearance") {
                Picker("Theme", selection: $preferences.theme) {
                    ForEach(ReadingTheme.allCases) { theme in
                        Label(theme.label, systemImage: theme.systemImage).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Stepper(value: $preferences.dailyGoalMinutes, in: AppPreferences.dailyGoalRange, step: 5) {
                    LabeledContent("Daily reading", value: "\(preferences.dailyGoalMinutes) min")
                }
                Stepper(value: $preferences.annualBookGoal, in: AppPreferences.annualGoalRange) {
                    LabeledContent("Books this year", value: preferences.annualBookGoal == 1 ? "1 book" : "\(preferences.annualBookGoal) books")
                }
            } header: {
                Text("Goals")
            } footer: {
                Text("Reading time counts only while a book is open and in front of you.")
            }

            Section {
                Button("Find Books in Folders…", systemImage: "folder.badge.gearshape") {
                    #if os(macOS)
                    router?.showingDiscovery = true
                    #else
                    dismiss()
                    Task { router?.showingDiscovery = true }
                    #endif
                }
                LabeledContent("Shared folders", value: "\(library.folders.count)")
                Button(coverButtonTitle, systemImage: "photo.on.rectangle.angled") { library.refreshAllCovers() }
                    .disabled(library.coverRefreshState.isRefreshing)
            } header: {
                Text("Library")
            } footer: {
                Text("Refreshing re-extracts covers from your PDFs and EPUBs. Files without a usable cover get a typographic one.")
            }

            Section {
                LabeledContent("Books stored", value: library.librarySizeDescription())
                LabeledContent("Account", value: "None needed")
            } header: {
                Text("Privacy")
            } footer: {
                Text("Your books, progress, highlights, and reading time stay on this device. Chicken has no account and sends nothing anywhere.")
            }

            Section {
                LabeledContent("Version", value: Bundle.main.appVersion)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle("Settings")
        #if !os(macOS)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        #endif
    }

    private var coverButtonTitle: String {
        switch library.coverRefreshState {
        case .idle: return "Refresh Covers"
        case .refreshing(let completed, let total): return "Refreshing \(completed) of \(total)…"
        case .finished(let refreshed): return "Refreshed \(refreshed) Covers"
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
