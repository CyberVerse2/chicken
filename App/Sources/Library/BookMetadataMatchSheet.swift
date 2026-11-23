import ChickenKit
import SwiftUI

struct BookMetadataMatchSheet: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let book: Book

    @State private var titleQuery: String
    @State private var authorQuery: String
    @State private var isbnQuery: String
    @State private var replaceCover: Bool
    @State private var isSearching = false
    @State private var applyingMatchID: String?
    @State private var matches: [BookCatalogMatch] = []
    @State private var warnings: [String] = []
    @State private var hasSearched = false

    init(book: Book) {
        self.book = book
        _titleQuery = State(initialValue: book.displayTitle)
        _authorQuery = State(initialValue: book.author ?? "")
        _isbnQuery = State(initialValue: book.isbn ?? "")
        _replaceCover = State(initialValue: book.coverImageName == nil)
    }

    var body: some View {
        ChickenPage(
            title: "Match Metadata",
            subtitle: "Search Hardcover and Open Library to fill or update book details."
        ) {
            ChickenSection("Query") {
                ChickenRow {
                    fieldRow(label: "Title", placeholder: "Book title", text: $titleQuery)
                }
                ChickenRow {
                    fieldRow(label: "Author", placeholder: "Author name", text: $authorQuery)
                }
                ChickenRow {
                    fieldRow(label: "ISBN", placeholder: "ISBN-10 or ISBN-13", text: $isbnQuery)
                }
                ChickenRow {
                    Toggle("Replace existing cover", isOn: $replaceCover)
                        .font(.chickenUI(14, weight: .medium))
                        .foregroundStyle(palette.text)
                        .tint(palette.ribbon)
                }
                ChickenRow(isLast: true) {
                    HStack {
                        Spacer()
                        Button {
                            Task { await runSearch() }
                        } label: {
                            HStack(spacing: 6) {
                                if isSearching {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "magnifyingglass")
                                }
                                Text(isSearching ? "Searching…" : "Search")
                            }
                            .font(.chickenUI(13.5, weight: .semibold))
                        }
                        .inkProminentButton()
                        .disabled(isSearching || titleQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isbnQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }

            if !warnings.isEmpty {
                ChickenSection("Notes") {
                    ForEach(Array(warnings.enumerated()), id: \.offset) { index, warning in
                        ChickenRow(isLast: index == warnings.count - 1) {
                            Text(warning)
                                .font(.chickenUI(13))
                                .foregroundStyle(palette.muted)
                        }
                    }
                }
            }

            if isSearching && matches.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Searching catalogs…")
                        .font(.chickenUI(14))
                        .foregroundStyle(palette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
            } else if !matches.isEmpty {
                ChickenSection("Matches", count: matches.count) {
                    ForEach(Array(matches.enumerated()), id: \.element.id) { index, match in
                        ChickenRow(isLast: index == matches.count - 1) {
                            matchRow(match)
                        }
                    }
                }
            } else if hasSearched {
                ContentUnavailableView(
                    "No Matches",
                    systemImage: "books.vertical",
                    description: Text("Try shortening the title or clearing the author field.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
        }
        .pageTitle("Match Metadata")
        .toolbar { SheetDoneButton { dismiss() } }
        .task {
            await runSearch()
        }
    }

    private func fieldRow(label: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.chickenUI(13.5, weight: .medium))
                .foregroundStyle(palette.muted)
                .frame(width: 56, alignment: .leading)
            TextField(placeholder, text: text)
                .font(.chickenUI(14.5))
                .foregroundStyle(palette.text)
                .textFieldStyle(.plain)
        }
    }

    private func matchRow(_ match: BookCatalogMatch) -> some View {
        Button {
            Task { await apply(match) }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                coverThumbnail(match.coverURL)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(match.title)
                            .font(.chickenUI(15, weight: .semibold))
                            .foregroundStyle(palette.text)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 4)
                        Text(match.source.label)
                            .font(.chickenUI(10.5, weight: .semibold))
                            .foregroundStyle(palette.ribbon)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(palette.ribbon.opacity(0.12), in: Capsule())
                    }

                    if let author = match.authorLine {
                        Text(author)
                            .font(.chickenSerif(13.5, italic: true))
                            .foregroundStyle(palette.muted)
                            .lineLimit(1)
                    }

                    let metadataParts = [
                        match.releaseYear.map(String.init),
                        match.pageCount.map { "\($0) pp." },
                        match.publisher,
                    ].compactMap { $0 }
                    if !metadataParts.isEmpty {
                        Text(metadataParts.joined(separator: " · "))
                            .font(.chickenUI(12))
                            .foregroundStyle(palette.faint)
                            .lineLimit(1)
                    }

                    if let summary = match.summary {
                        Text(summary)
                            .font(.chickenUI(12.5))
                            .foregroundStyle(palette.muted)
                            .lineLimit(2)
                            .padding(.top, 2)
                    }
                }
                if applyingMatchID == match.id {
                    ProgressView().controlSize(.small)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(applyingMatchID != nil)
    }

    private func coverThumbnail(_ url: URL?) -> some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        coverPlaceholder
                    }
                }
            } else {
                coverPlaceholder
            }
        }
        .frame(width: 46, height: 68)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(palette.border, lineWidth: 0.5))
    }

    private var coverPlaceholder: some View {
        ZStack {
            palette.surfaceAlt
            Image(systemName: "book.closed")
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(palette.faint)
        }
    }

    private func runSearch() async {
        isSearching = true
        warnings = []
        defer {
            isSearching = false
            hasSearched = true
        }
        let query = BookCatalogQuery(title: titleQuery, author: authorQuery, isbn: isbnQuery)
        let token = CatalogTokenStore.loadHardcoverToken()
        let result = await BookCatalogClient.shared.search(query, hardcoverToken: token)
        matches = result.matches
        warnings = result.warnings
    }

    private func apply(_ match: BookCatalogMatch) async {
        applyingMatchID = match.id
        defer { applyingMatchID = nil }
        await library.applyCatalogMatch(match, to: book, replaceCover: replaceCover, replaceExistingFields: true)
        Haptics.impact(.light)
        dismiss()
    }
}
