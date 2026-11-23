import ChickenKit
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
#endif

struct ChangeCoverSheet: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let book: Book

    @State private var queryText: String
    @State private var authorText: String
    @State private var isSearching = false
    @State private var isApplying = false
    @State private var matches: [BookCatalogMatch] = []
    @State private var errorMessage: String?
    @State private var choosingFile = false
    #if os(iOS)
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingPhotoPicker = false
    #endif

    init(book: Book) {
        self.book = book
        _queryText = State(initialValue: book.displayTitle)
        _authorText = State(initialValue: book.author ?? "")
    }

    private var editionCovers: [BookCatalogMatch] {
        var seen: Set<String> = []
        return matches.filter { match in
            guard let url = match.coverURL?.absoluteString, !url.isEmpty else { return false }
            return seen.insert(url).inserted
        }
    }

    var body: some View {
        ChickenPage(
            title: "Change Cover",
            subtitle: book.displayTitle
        ) {
            previewSection
            editionsSection
        }
        .pageTitle("Change Cover")
        .toolbar { SheetDoneButton { dismiss() } }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result {
                Task { await importImageFile(at: url) }
            }
        }
        #if os(iOS)
        .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhoto, matching: .images)
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await applyImageData(data)
                }
                selectedPhoto = nil
            }
        }
        #endif
        .task {
            await searchCovers()
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 580, minHeight: 560, idealHeight: 680)
        #endif
    }

    private var previewSection: some View {
        VStack(spacing: 16) {
            BookCover(book: book, style: .hero)
                .aspectRatio(book.resolvedAspectRatio, contentMode: .fit)
                .frame(height: 196)
                .shadow(color: palette.shadow, radius: 18, x: 0, y: 10)
                .dropDestination(for: URL.self) { urls, _ in
                    guard let first = urls.first(where: \.isFileURL) else { return false }
                    Task { await importImageFile(at: first) }
                    return true
                }

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        choosingFile = true
                    } label: {
                        Label("Choose File…", systemImage: "folder")
                            .font(.chickenUI(13, weight: .semibold))
                            .foregroundStyle(palette.text)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .chickenGlass(in: Capsule(), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .disabled(isApplying)

                    #if os(iOS)
                    Button {
                        showingPhotoPicker = true
                    } label: {
                        Label("Photos", systemImage: "photo")
                            .font(.chickenUI(13, weight: .semibold))
                            .foregroundStyle(palette.text)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .chickenGlass(in: Capsule(), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .disabled(isApplying)
                    #endif

                    if book.hasCoverArtwork {
                        Button {
                            Task {
                                isApplying = true
                                await library.resetCoverToCloth(for: book)
                                isApplying = false
                                Haptics.impact(.light)
                            }
                        } label: {
                            Label("Cloth Binding", systemImage: "book.closed")
                                .font(.chickenUI(13, weight: .medium))
                                .foregroundStyle(palette.muted)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .chickenGlass(in: Capsule(), interactive: true)
                        }
                        .buttonStyle(.plain)
                        .disabled(isApplying)
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.chickenUI(12.5))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var editionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ChickenSection("Search Editions") {
                ChickenRow {
                    HStack(spacing: 10) {
                        TextField("Title", text: $queryText)
                            .font(.chickenUI(14.5))
                            .textFieldStyle(.plain)
                            .foregroundStyle(palette.text)
                        TextField("Author", text: $authorText)
                            .font(.chickenUI(14))
                            .textFieldStyle(.plain)
                            .foregroundStyle(palette.muted)
                        Button {
                            Task { await searchCovers() }
                        } label: {
                            if isSearching {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Search")
                                    .font(.chickenUI(13, weight: .semibold))
                            }
                        }
                        .inkProminentButton()
                        .disabled(isSearching || queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }

            if isSearching && editionCovers.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Looking for edition covers…")
                        .font(.chickenUI(13.5))
                        .foregroundStyle(palette.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else if !editionCovers.isEmpty {
                SectionLabel(text: "Edition Covers", count: editionCovers.count)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 96, maximum: 130), spacing: 16, alignment: .bottom)],
                    spacing: 18
                ) {
                    ForEach(editionCovers) { match in
                        editionTile(match)
                    }
                }
            } else if !isSearching {
                Text("No catalog covers found for this query. Try editing the title or drop an image onto the preview above.")
                    .font(.chickenUI(13))
                    .foregroundStyle(palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            }
        }
    }

    private func editionTile(_ match: BookCatalogMatch) -> some View {
        Button {
            guard let url = match.coverURL else { return }
            Task {
                isApplying = true
                errorMessage = nil
                let ok = await library.applyCatalogCover(from: url, for: book)
                isApplying = false
                if ok {
                    Haptics.impact(.light)
                    dismiss()
                } else {
                    errorMessage = "That cover couldn't be loaded or was too wide."
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                AsyncImage(url: match.coverURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .failure:
                        placeholder
                    default:
                        placeholder
                    }
                }
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(palette.border, lineWidth: 0.5))
                .shadow(color: palette.shadow, radius: 6, y: 3)

                HStack(spacing: 4) {
                    Text(match.source.label)
                        .font(.chickenMono(10, weight: .semibold))
                        .foregroundStyle(palette.ribbon)
                    if let year = match.releaseYear {
                        Text("· \(String(year))")
                            .font(.chickenMono(10))
                            .foregroundStyle(palette.muted)
                    }
                }
                .lineLimit(1)
            }
        }
        .buttonStyle(TactilePressStyle())
        .disabled(isApplying)
    }

    private var placeholder: some View {
        ZStack {
            palette.surfaceAlt
            Image(systemName: "book.closed")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(palette.faint)
        }
    }

    private func searchCovers() async {
        isSearching = true
        defer { isSearching = false }
        let query = BookCatalogQuery(title: queryText, author: authorText)
        let token = CatalogTokenStore.loadHardcoverToken()
        let result = await BookCatalogClient.shared.search(query, hardcoverToken: token)
        matches = result.matches
    }

    private func importImageFile(at url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            errorMessage = "Couldn't read that image file."
            return
        }
        await applyImageData(data)
    }

    private func applyImageData(_ data: Data) async {
        isApplying = true
        errorMessage = nil
        let ok = await library.setCustomCover(data: data, for: book)
        isApplying = false
        if ok {
            Haptics.impact(.light)
            dismiss()
        } else {
            errorMessage = "Choose a portrait or square image at least 60×60 pixels."
        }
    }
}
