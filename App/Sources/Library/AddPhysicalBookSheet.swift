import ChickenKit
import SwiftUI

struct AddPhysicalBookSheet: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var startWithScanner: Bool = false
    var initialQuery: String = ""
    var onAdded: ((Book) -> Void)? = nil

    private enum Mode: String, CaseIterable, Identifiable {
        case search
        case manual
        var id: String { rawValue }
        var label: String {
            switch self {
            case .search: "Catalog & ISBN"
            case .manual: "Manual Entry"
            }
        }
    }

    @State private var mode: Mode = .search
    @State private var query: String
    @State private var initialStatus: PhysicalBookStatus = .reading
    @State private var startingPageText = ""

    @State private var isSearching = false
    @State private var addingMatchID: String?
    @State private var matches: [BookCatalogMatch] = []
    @State private var warnings: [String] = []
    @State private var hasSearched = false

    @State private var manualTitle = ""
    @State private var manualAuthor = ""
    @State private var manualISBN = ""
    @State private var manualPagesText = ""
    @State private var manualYearText = ""
    @State private var manualPublisher = ""

    #if os(iOS)
    @State private var showingScanner = false
    #endif

    init(
        startWithScanner: Bool = false,
        initialQuery: String = "",
        onAdded: ((Book) -> Void)? = nil
    ) {
        self.startWithScanner = startWithScanner
        self.initialQuery = initialQuery
        self.onAdded = onAdded
        _query = State(initialValue: initialQuery)
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedStartingPage: Int? {
        guard initialStatus == .reading else { return nil }
        return Int(startingPageText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        NavigationStack {
            ChickenPage(
                title: "Add Physical Book",
                subtitle: "Track print and hardcover editions alongside your digital library."
            ) {
                Picker("Entry Mode", selection: $mode) {
                    ForEach(Mode.allCases) { item in
                        Text(item.label).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                ChickenSection("Reading Shelf") {
                    ChickenRow {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Status")
                                .font(.chickenUI(12, weight: .semibold))
                                .foregroundStyle(palette.muted)
                            Picker("Status", selection: $initialStatus) {
                                ForEach(PhysicalBookStatus.allCases) { status in
                                    Text(status.label).tag(status)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    if initialStatus == .reading {
                        ChickenRow(isLast: true) {
                            HStack(spacing: 12) {
                                Text("Page")
                                    .font(.chickenUI(13.5, weight: .medium))
                                    .foregroundStyle(palette.muted)
                                    .frame(width: 72, alignment: .leading)
                                TextField("Current page (optional)", text: $startingPageText)
                                    .font(.chickenUI(14.5))
                                    .foregroundStyle(palette.text)
                                    .textFieldStyle(.plain)
                                    #if os(iOS)
                                    .keyboardType(.numberPad)
                                    #endif
                            }
                        }
                    }
                }

                switch mode {
                case .search:
                    searchSections
                case .manual:
                    manualSections
                }
            }
            .pageTitle("Add Physical Book")
            .toolbar { SheetDoneButton { dismiss() } }
            #if os(iOS)
            .sheet(isPresented: $showingScanner) {
                ISBNBarcodeScanner { scanned in
                    query = scanned
                    manualISBN = scanned
                    if mode == .search {
                        Task { await runSearch() }
                    }
                }
                .readingTheme(library.preferences.theme)
            }
            #endif
            .task {
                #if os(iOS)
                if startWithScanner {
                    showingScanner = true
                    return
                }
                #endif
                if !trimmedQuery.isEmpty {
                    await runSearch()
                }
            }
        }
    }

    @ViewBuilder
    private var searchSections: some View {
        ChickenSection("Find Edition") {
            ChickenRow(isLast: true) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(palette.muted)
                        TextField("ISBN, title, or author", text: $query)
                            .font(.chickenUI(15))
                            .foregroundStyle(palette.text)
                            .textFieldStyle(.plain)
                            .onSubmit { Task { await runSearch() } }
                        if !query.isEmpty {
                            Button {
                                query = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(palette.muted)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack(spacing: 10) {
                        #if os(iOS)
                        Button {
                            showingScanner = true
                        } label: {
                            Label("Scan ISBN", systemImage: "barcode.viewfinder")
                                .font(.chickenUI(13.5, weight: .semibold))
                                .foregroundStyle(palette.text)
                        }
                        .buttonStyle(.glass)
                        #endif

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
                        .disabled(isSearching || trimmedQuery.isEmpty)
                    }
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
                Text("Searching Hardcover and Open Library…")
                    .font(.chickenUI(14))
                    .foregroundStyle(palette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
        } else if !matches.isEmpty {
            ChickenSection("Catalog Matches", count: matches.count) {
                ForEach(Array(matches.enumerated()), id: \.element.id) { index, match in
                    ChickenRow(isLast: index == matches.count - 1) {
                        matchRow(match)
                    }
                }
            }
        } else if hasSearched {
            ChickenSection("No Matches") {
                ChickenRow(isLast: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("No catalog matches were found for “\(trimmedQuery)”.")
                            .font(.chickenUI(14))
                            .foregroundStyle(palette.muted)
                        Button("Enter Details Manually") {
                            prefillManualFromQuery()
                            mode = .manual
                        }
                        .font(.chickenUI(13.5, weight: .semibold))
                        .foregroundStyle(palette.ribbon)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var manualSections: some View {
        ChickenSection("Book Details") {
            ChickenRow {
                manualField(label: "Title", placeholder: "Required", text: $manualTitle)
            }
            ChickenRow {
                manualField(label: "Author", placeholder: "Optional", text: $manualAuthor)
            }
            ChickenRow {
                HStack(spacing: 8) {
                    manualField(label: "ISBN", placeholder: "ISBN-10 or ISBN-13", text: $manualISBN)
                    #if os(iOS)
                    Button {
                        showingScanner = true
                    } label: {
                        Image(systemName: "barcode.viewfinder")
                            .foregroundStyle(palette.ribbon)
                    }
                    .buttonStyle(.plain)
                    #endif
                }
            }
            ChickenRow {
                HStack(spacing: 12) {
                    Text("Pages")
                        .font(.chickenUI(13.5, weight: .medium))
                        .foregroundStyle(palette.muted)
                        .frame(width: 72, alignment: .leading)
                    TextField("Total page count", text: $manualPagesText)
                        .font(.chickenUI(14.5))
                        .foregroundStyle(palette.text)
                        .textFieldStyle(.plain)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }
            }
            ChickenRow {
                HStack(spacing: 12) {
                    Text("Year")
                        .font(.chickenUI(13.5, weight: .medium))
                        .foregroundStyle(palette.muted)
                        .frame(width: 72, alignment: .leading)
                    TextField("Release year", text: $manualYearText)
                        .font(.chickenUI(14.5))
                        .foregroundStyle(palette.text)
                        .textFieldStyle(.plain)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }
            }
            ChickenRow(isLast: true) {
                manualField(label: "Publisher", placeholder: "Optional", text: $manualPublisher)
            }
        }

        HStack {
            Spacer()
            Button {
                addManualBook()
            } label: {
                Label("Add to Library", systemImage: "book.closed.fill")
                    .font(.chickenUI(14, weight: .semibold))
            }
            .inkProminentButton()
            .disabled(manualTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func manualField(label: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.chickenUI(13.5, weight: .medium))
                .foregroundStyle(palette.muted)
                .frame(width: 72, alignment: .leading)
            TextField(placeholder, text: text)
                .font(.chickenUI(14.5))
                .foregroundStyle(palette.text)
                .textFieldStyle(.plain)
        }
    }

    private func matchRow(_ match: BookCatalogMatch) -> some View {
        HStack(alignment: .top, spacing: 14) {
            coverThumbnail(match.coverURL)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 6) {
                    Text(match.title)
                        .font(.chickenUI(15, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Text(match.source.label)
                        .font(.chickenUI(10.5, weight: .semibold))
                        .foregroundStyle(palette.ribbon)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(palette.ribbon.opacity(0.12), in: Capsule())
                }

                if let seriesBadge = match.seriesBadgeText {
                    Text(seriesBadge)
                        .font(.chickenUI(11.5, weight: .medium))
                        .foregroundStyle(palette.ribbon)
                        .lineLimit(1)
                }

                if let author = match.authorLine {
                    Text(author)
                        .font(.chickenSerif(13.5, italic: true))
                        .foregroundStyle(palette.muted)
                        .lineLimit(1)
                }

                let details = [
                    match.releaseYear.map(String.init),
                    match.pageCount.map { "\($0) pp." },
                    match.isbn,
                    match.rating.map { String(format: "★ %.1f", $0) },
                ].compactMap { $0 }
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .font(.chickenUI(12))
                        .foregroundStyle(palette.faint)
                        .lineLimit(1)
                }

                if !match.genres.isEmpty {
                    Text(match.genres.prefix(3).joined(separator: " · "))
                        .font(.chickenUI(11))
                        .foregroundStyle(palette.muted)
                        .lineLimit(1)
                }

                HStack {
                    Spacer()
                    Button {
                        Task { await addMatch(match) }
                    } label: {
                        HStack(spacing: 6) {
                            if addingMatchID == match.id {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "plus")
                            }
                            Text(addingMatchID == match.id ? "Adding…" : "Add Print")
                        }
                        .font(.chickenUI(12.5, weight: .semibold))
                    }
                    .inkProminentButton()
                    .disabled(addingMatchID != nil)
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func coverThumbnail(_ url: URL?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(palette.muted.opacity(0.12))
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Image(systemName: "book.closed")
                            .foregroundStyle(palette.muted)
                    }
                }
            } else {
                Image(systemName: "book.closed")
                    .foregroundStyle(palette.muted)
            }
        }
        .frame(width: 50, height: 74)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(palette.border, lineWidth: 0.5))
    }

    private func prefillManualFromQuery() {
        if let isbn = ISBNExtractor.normalize(trimmedQuery) {
            if manualISBN.isEmpty { manualISBN = isbn }
        } else if manualTitle.isEmpty {
            manualTitle = trimmedQuery
        }
    }

    private func runSearch() async {
        let q = trimmedQuery
        guard !q.isEmpty, !isSearching else { return }
        isSearching = true
        hasSearched = false
        warnings = []

        let normalizedISBN = ISBNExtractor.normalize(q)
        let catalogQuery = BookCatalogQuery(
            title: q,
            author: nil,
            isbn: normalizedISBN
        )
        let token = CatalogTokenStore.loadHardcoverToken()
        let result = await BookCatalogClient.shared.search(catalogQuery, hardcoverToken: token)

        matches = result.matches
        warnings = result.warnings
        hasSearched = true
        isSearching = false
    }

    private func addMatch(_ match: BookCatalogMatch) async {
        guard addingMatchID == nil else { return }
        addingMatchID = match.id
        let book = await library.addPhysicalBook(
            from: match,
            initialStatus: initialStatus,
            currentPage: parsedStartingPage
        )
        addingMatchID = nil
        dismiss()
        onAdded?(book)
    }

    private func addManualBook() {
        let book = library.addManualPhysicalBook(
            title: manualTitle,
            author: manualAuthor,
            isbn: manualISBN,
            pageCount: Int(manualPagesText.trimmingCharacters(in: .whitespacesAndNewlines)),
            releaseYear: Int(manualYearText.trimmingCharacters(in: .whitespacesAndNewlines)),
            publisher: manualPublisher,
            initialStatus: initialStatus,
            currentPage: parsedStartingPage
        )
        dismiss()
        onAdded?(book)
    }
}
