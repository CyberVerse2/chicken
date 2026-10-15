import ChickenKit
import SwiftUI
import UniformTypeIdentifiers

/// "Ask before looking": the user chooses folders, Chicken lists what it
/// finds, and nothing is imported without review.
struct DiscoveryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var choosingFolder = false

    private var likely: [DiscoveredBook] { library.discoveredBooks.filter(\.isLikelyBook) }
    private var others: [DiscoveredBook] { library.discoveredBooks.filter { !$0.isLikelyBook } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if library.folders.isEmpty {
                        Text("Choose folders where you keep books, such as Downloads, Documents, or a Books folder. Chicken only looks inside folders you add, and only copies the books you pick.")
                            .font(.chickenUI(13))
                            .foregroundStyle(palette.muted)
                    }
                    ForEach(library.folders) { folder in
                        FolderRow(folder: folder)
                    }
                    .onDelete { offsets in
                        offsets.map { library.folders[$0] }.forEach(library.removeFolder)
                    }
                    Button("Add Folder…", systemImage: "folder.badge.plus") { choosingFolder = true }
                } header: {
                    Text("Folders")
                } footer: {
                    scanStatus
                }

                if !likely.isEmpty {
                    Section {
                        ForEach(likely) { DiscoveredRow(book: $0) }
                    } header: {
                        HStack {
                            Text("Likely books · \(likely.count)")
                            Spacer()
                            Button("Import All") { library.importDiscovered(likely) }
                                .disabled(library.importState.isImporting)
                                .textCase(nil)
                        }
                    }
                }

                if !others.isEmpty {
                    Section("Lower confidence · \(others.count)") {
                        ForEach(others) { DiscoveredRow(book: $0) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .navigationTitle("Find Books")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Scan Again", systemImage: "arrow.clockwise") { library.scanFolders() }
                        .disabled(library.folders.isEmpty || library.scanState.isScanning)
                }
            }
            .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { library.addFolder(url) }
            }
            .overlay(alignment: .bottom) { ActivityToast() }
        }
        #if os(macOS)
        .frame(minWidth: 640, idealWidth: 720, minHeight: 520, idealHeight: 620)
        #endif
        .onAppear {
            if library.discoveredBooks.isEmpty { library.scanFolders() }
        }
    }

    @ViewBuilder
    private var scanStatus: some View {
        switch library.scanState {
        case .idle:
            EmptyView()
        case .scanning(let checked, let found, let folder):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checked \(checked.formatted()) files · \(found) found\(folder.isEmpty ? "" : " · \(folder)")")
                    .monospacedDigit()
            }
        case .finished(let found):
            Text(found == 0 ? "No new books found." : "Found \(found) files. Importing copies them into Chicken; originals stay where they are.")
        }
    }
}

private struct FolderRow: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette
    let folder: WatchedFolder

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: folder.isReachable ? "folder" : "folder.badge.questionmark")
                .foregroundStyle(palette.muted)
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name).font(.chickenUI(13, weight: .medium))
                Text(folder.isReachable ? folder.path : "Can't reach this folder. Remove it and add it again.")
                    .font(.chickenUI(11))
                    .foregroundStyle(palette.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            #if os(macOS)
            Button("Remove", systemImage: "minus.circle") { library.removeFolder(folder) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            #endif
        }
    }
}

private struct DiscoveredRow: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette
    let book: DiscoveredBook

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: book.format.systemImage)
                .font(.system(size: 15))
                .foregroundStyle(palette.muted)
                .frame(width: 34, height: 46)
                .background(RoundedRectangle(cornerRadius: 6).fill(palette.surfaceAlt))

            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .font(.chickenSerif(14, weight: .medium))
                    .lineLimit(1)
                Text(metaLine)
                    .font(.chickenUI(11))
                    .foregroundStyle(palette.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button("Import") { library.importDiscovered([book]) }
                .buttonStyle(.glass)
                .disabled(library.importState.isImporting)
        }
        .swipeActions {
            Button("Dismiss", role: .destructive) { library.dismissDiscovered(book) }
        }
        .contextMenu {
            Button("Dismiss", systemImage: "xmark") { library.dismissDiscovered(book) }
        }
    }

    private var metaLine: String {
        var parts: [String] = [book.format.label]
        if let author = book.metadata.author { parts.append(author) }
        if let pages = book.metadata.pageCount { parts.append("\(pages) pages") }
        if book.fileSize > 0 { parts.append(ByteCountFormatter.string(fromByteCount: book.fileSize, countStyle: .file)) }
        parts.append(book.classification)
        return parts.joined(separator: " · ")
    }
}

struct EmptyLibraryView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "books.vertical")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(palette.muted)

            Text("Your library is empty")
                .font(.chickenSerif(28, weight: .medium))
                .foregroundStyle(palette.text)

            Text("Point Chicken at the folders where you keep PDFs and EPUBs, or import files directly. Chicken keeps its own copy, stored only on this device.")
                .font(.chickenUI(14))
                .foregroundStyle(palette.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)

            GlassEffectContainer(spacing: 12) {
                ViewThatFits {
                    HStack(spacing: 12) { buttons }
                    VStack(spacing: 12) { buttons }
                }
            }
            .padding(.top, 6)
        }
        .padding(.vertical, 64)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(palette.surface)
                .stroke(palette.border, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var buttons: some View {
        PrimaryActionButton(title: "Find books in folders", systemImage: "folder") { router.showingDiscovery = true }
        SecondaryActionButton(title: "Import files", systemImage: "plus") { router.showingImporter = true }
    }
}
