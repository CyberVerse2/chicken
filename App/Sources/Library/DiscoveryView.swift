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
    @State private var showingAllOthers = false

    private var likely: [DiscoveredBook] { library.discoveredBooks.filter(\.isLikelyBook) }
    private var others: [DiscoveredBook] { library.discoveredBooks.filter { !$0.isLikelyBook } }

    var body: some View {
        NavigationStack {
            ChickenPage(
                title: "Find books",
                subtitle: "Chicken only looks in folders you choose."
            ) {
                foldersSection
                if !library.folders.isEmpty { scanStatus }
                if !likely.isEmpty { likelySection }
                if !others.isEmpty { othersSection }
            }
            .pageTitle("Find Books")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
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
        .frame(minWidth: 620, idealWidth: 720, minHeight: 560, idealHeight: 720)
        #endif
        .onAppear {
            if library.discoveredBooks.isEmpty { library.scanFolders() }
        }
    }

    // MARK: Folders

    private var foldersSection: some View {
        ChickenSection("Folders", count: library.folders.isEmpty ? nil : library.folders.count) {
            Button("Add Folder", systemImage: "plus") { choosingFolder = true }
                .font(.chickenUI(13, weight: .medium))
                .foregroundStyle(palette.text)
                .buttonStyle(.glass)
        } content: {
            if library.folders.isEmpty {
                ChickenRow(isLast: true) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 14) {
                            ForEach(["arrow.down.circle", "doc", "books.vertical"], id: \.self) { icon in
                                Image(systemName: icon)
                                    .font(.system(size: 20, weight: .light))
                                    .foregroundStyle(palette.muted)
                                    .frame(width: 44, height: 44)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.surfaceAlt))
                            }
                        }
                        PrimaryActionButton(title: "Choose a folder", systemImage: "folder") { choosingFolder = true }
                    }
                    .padding(.vertical, 6)
                }
            } else {
                ForEach(Array(library.folders.enumerated()), id: \.element.id) { index, folder in
                    ChickenRow(isLast: index == library.folders.count - 1) {
                        FolderRow(folder: folder)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var scanStatus: some View {
        switch library.scanState {
        case .idle:
            EmptyView()
        case .scanning(let checked, let found, let folder):
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Looking through \(folder.isEmpty ? "your folders" : folder)…")
                        .font(.chickenSerif(15, italic: true))
                        .foregroundStyle(palette.text)
                    Text("\(checked.formatted()) files checked · \(found) found")
                        .font(.chickenMono(11))
                        .foregroundStyle(palette.faint)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .capsule)
        case .finished(let found):
            HStack(spacing: 10) {
                Image(systemName: found == 0 ? "checkmark.circle" : "sparkles")
                    .foregroundStyle(palette.muted)
                Text(found == 0 ? "Everything in these folders is already in your library." : "Found \(found) new \(found == 1 ? "file" : "files").")
                    .font(.chickenSerif(15, italic: true))
                    .foregroundStyle(palette.muted)
            }
        }
    }

    // MARK: Results

    private var likelySection: some View {
        ChickenSection("Likely books", count: likely.count) {
            Button(library.importState.isImporting ? "Importing…" : "Import All") { library.importDiscovered(likely) }
                .font(.chickenUI(13, weight: .semibold))
                .inkProminentButton()
                .disabled(library.importState.isImporting)
        } content: {
            ForEach(Array(likely.enumerated()), id: \.element.id) { index, book in
                ChickenRow(isLast: index == likely.count - 1) {
                    DiscoveredRow(book: book)
                }
            }
        }
    }

    private var othersSection: some View {
        let shown = showingAllOthers ? others : Array(others.prefix(5))
        return ChickenSection("Needs a look", count: others.count) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, book in
                ChickenRow(isLast: index == shown.count - 1 && (showingAllOthers || others.count <= 5)) {
                    DiscoveredRow(book: book)
                }
            }
            if !showingAllOthers && others.count > 5 {
                ChickenRow(isLast: true) {
                    Button("Show \(others.count - 5) more") { withAnimation(.smooth) { showingAllOthers = true } }
                        .font(.chickenUI(13, weight: .semibold))
                        .foregroundStyle(palette.muted)
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct FolderRow: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette
    let folder: WatchedFolder
    @State private var reachable = true

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: reachable ? "folder.fill" : "folder.badge.questionmark")
                .font(.system(size: 18))
                .foregroundStyle(palette.muted)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.surfaceAlt))
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.chickenSerif(16, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text(reachable ? folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") : "Can't reach this folder. Remove it and add it again.")
                    .font(.chickenUI(11))
                    .foregroundStyle(palette.faint)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button("Remove \(folder.name)", systemImage: "xmark") { library.removeFolder(folder) }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .foregroundStyle(palette.muted)
        }
        .task { reachable = folder.isReachable }
    }
}

private struct DiscoveredRow: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass
    let book: DiscoveredBook

    var body: some View {
        HStack(spacing: 14) {
            FormatSlip(format: book.format, title: book.title)
                .frame(width: 38, height: 54)

            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .font(.chickenSerif(15, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .lineLimit(2)
                Text(metaLine)
                    .font(.chickenUI(11))
                    .foregroundStyle(palette.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    Button("Import") { library.importDiscovered([book]) }
                        .font(.chickenUI(13, weight: .medium))
                        .foregroundStyle(palette.text)
                        .buttonStyle(.glass)
                        .disabled(library.importState.isImporting)
                    if sizeClass != .compact {
                        Button("Dismiss", systemImage: "xmark") { withAnimation(.smooth) { library.dismissDiscovered(book) } }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.glass)
                            .buttonBorderShape(.circle)
                            .foregroundStyle(palette.muted)
                    }
                }
            }
        }
        .contextMenu {
            Button("Import", systemImage: "square.and.arrow.down") { library.importDiscovered([book]) }
            Button("Dismiss", systemImage: "xmark") { library.dismissDiscovered(book) }
        }
    }

    private var metaLine: String {
        var parts: [String] = []
        if let author = book.metadata.author { parts.append(author) }
        if let pages = book.metadata.pageCount { parts.append("\(pages) pages") }
        if book.fileSize > 0 { parts.append(ByteCountFormatter.string(fromByteCount: book.fileSize, countStyle: .file)) }
        if parts.isEmpty { parts.append(URL(fileURLWithPath: book.sourceFolder).lastPathComponent) }
        return parts.joined(separator: " · ")
    }
}

/// A tiny stand-in cover for files that aren't in the library yet.
private struct FormatSlip: View {
    let format: BookFormat
    let title: String

    var body: some View {
        let preset = CoverPreset.preset(forTitle: title)
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(preset.cloth)
            .overlay(alignment: .bottomLeading) {
                Text(format.label)
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(preset.ink)
                    .padding(5)
            }
            .overlay(alignment: .topLeading) {
                Rectangle().fill(preset.ink.opacity(0.5)).frame(width: 12, height: 1).padding(6)
            }
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
    }
}

// MARK: - Empty library

struct EmptyLibraryView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(spacing: 22) {
            FannedCovers()
                .frame(height: 170)
                .padding(.bottom, 4)

            Text("Bring your books home to roost")
                .font(.chickenDisplay(sizeClass == .compact ? 26 : 34))
                .tracking(-0.5)
                .foregroundStyle(palette.text)
                .multilineTextAlignment(.center)

            GlassEffectContainer(spacing: 12) {
                ViewThatFits {
                    HStack(spacing: 12) { buttons }
                    VStack(spacing: 12) { buttons }
                }
            }
        }
        .padding(.vertical, sizeClass == .compact ? 40 : 64)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
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

/// Three cloth covers fanned like a hand of cards.
private struct FannedCovers: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spread = false

    private static let samples: [(title: String, author: String, preset: Int)] = [
        ("Field Notes", "Your Name", 1),
        ("Collected Papers", "Many Hands", 0),
        ("The Long Book", "Someday", 2),
    ]

    var body: some View {
        ZStack {
            ForEach(0..<3) { index in
                let sample = Self.samples[index]
                ClothCover(title: sample.title, author: sample.author, preset: CoverPreset.all[sample.preset], style: .tile)
                    .background(CoverPreset.all[sample.preset].cloth)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .frame(width: 100, height: 150)
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
                    .rotationEffect(.degrees(spread ? Double(index - 1) * 11 : 0), anchor: .bottom)
                    .offset(x: spread ? CGFloat(index - 1) * 46 : 0, y: index == 1 ? -6 : 0)
                    .zIndex(index == 1 ? 1 : 0)
            }
        }
        .accessibilityHidden(true)
        .onAppear {
            if reduceMotion {
                spread = true
            } else {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.75).delay(0.15)) { spread = true }
            }
        }
    }
}
