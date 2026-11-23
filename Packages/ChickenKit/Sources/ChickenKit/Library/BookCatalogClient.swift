import Foundation

public enum BookCatalogSource: String, Codable, Sendable, Hashable, CaseIterable {
    case hardcover
    case openLibrary

    public var label: String {
        switch self {
        case .hardcover: "Hardcover"
        case .openLibrary: "Open Library"
        }
    }
}

public struct BookCatalogQuery: Sendable, Hashable {
    public var title: String
    public var author: String?
    public var isbn: String?

    public init(title: String, author: String? = nil, isbn: String? = nil) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.author = DocumentMetadata.clean(author)
        self.isbn = isbn.flatMap { ISBNExtractor.normalize($0) ?? ISBNExtractor.extract(from: $0) }
    }
}

public struct BookCatalogMatch: Identifiable, Hashable, Sendable {
    public let id: String
    public let source: BookCatalogSource
    public let title: String
    public let authors: [String]
    public let publisher: String?
    public let language: String?
    public let pageCount: Int?
    public let summary: String?
    public let isbn: String?
    public let releaseYear: Int?
    public let coverURL: URL?
    public let workKey: String?
    public let seriesName: String?
    public let seriesPosition: Double?
    public let genres: [String]
    public let moods: [String]
    public let rating: Double?
    public let ratingsCount: Int?
    public let catalogSlug: String?
    public let hardcoverBookID: Int?
    public let catalogURL: URL?

    public init(
        id: String,
        source: BookCatalogSource,
        title: String,
        authors: [String] = [],
        publisher: String? = nil,
        language: String? = nil,
        pageCount: Int? = nil,
        summary: String? = nil,
        isbn: String? = nil,
        releaseYear: Int? = nil,
        coverURL: URL? = nil,
        workKey: String? = nil,
        seriesName: String? = nil,
        seriesPosition: Double? = nil,
        genres: [String] = [],
        moods: [String] = [],
        rating: Double? = nil,
        ratingsCount: Int? = nil,
        catalogSlug: String? = nil,
        hardcoverBookID: Int? = nil,
        catalogURL: URL? = nil
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.authors = authors
        self.publisher = publisher
        self.language = language
        self.pageCount = pageCount
        self.summary = summary
        self.isbn = isbn
        self.releaseYear = releaseYear
        self.coverURL = coverURL
        self.workKey = workKey
        self.seriesName = seriesName
        self.seriesPosition = seriesPosition
        self.genres = genres
        self.moods = moods
        self.rating = rating
        self.ratingsCount = ratingsCount
        self.catalogSlug = catalogSlug
        self.hardcoverBookID = hardcoverBookID
        self.catalogURL = catalogURL
    }

    public var authorLine: String? {
        let cleaned = authors.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return nil }
        return cleaned.joined(separator: ", ")
    }

    public var seriesBadgeText: String? {
        guard let series = seriesName?.trimmingCharacters(in: .whitespacesAndNewlines), !series.isEmpty else {
            return nil
        }
        guard let pos = seriesPosition, pos > 0 else { return series }
        let formatted = pos.rounded() == pos ? String(Int(pos)) : String(format: "%.1f", pos)
        return "\(series) · Book \(formatted)"
    }

    var richnessScore: Int {
        var score = 0
        if summary != nil { score += 3 }
        if coverURL != nil { score += 2 }
        if !authors.isEmpty { score += 1 }
        if publisher != nil { score += 1 }
        if pageCount != nil { score += 1 }
        if isbn != nil { score += 1 }
        if language != nil { score += 1 }
        if seriesName != nil { score += 1 }
        if !genres.isEmpty { score += 1 }
        if rating != nil { score += 1 }
        return score
    }
}

public enum BookCatalogError: Error, LocalizedError, Sendable, Equatable {
    case invalidHardcoverToken
    case rateLimited
    case networkFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidHardcoverToken:
            "Hardcover rejected the API token. Check Settings > Book Metadata."
        case .rateLimited:
            "Catalog API rate limit reached. Try again in a moment."
        case .networkFailed(let message):
            "Catalog lookup failed: \(message)"
        }
    }
}

public struct BookCatalogSearchResult: Sendable {
    public let matches: [BookCatalogMatch]
    public let warnings: [String]

    public init(matches: [BookCatalogMatch], warnings: [String] = []) {
        self.matches = matches
        self.warnings = warnings
    }
}

public final class BookCatalogClient: Sendable {
    public static let shared = BookCatalogClient()

    private static let hardcoverEndpoint = URL(string: "https://api.hardcover.app/v1/graphql")!
    private static let userAgent = "Chicken/1.0 (https://github.com/CyberVerse2/chicken)"

    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 25
            config.httpAdditionalHeaders = ["User-Agent": Self.userAgent]
            self.session = URLSession(configuration: config)
        }
    }

    public func testHardcoverToken(_ rawToken: String) async throws -> String {
        let token = Self.cleanToken(rawToken)
        guard !token.isEmpty else { throw BookCatalogError.invalidHardcoverToken }
        let data = try await postHardcover(query: "query Me { me { username } }", variables: [:], token: token)
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let payload = root["data"] as? [String: Any]
        else {
            throw BookCatalogError.invalidHardcoverToken
        }
        if let meList = payload["me"] as? [[String: Any]], let username = meList.first?["username"] as? String {
            return username
        }
        if let me = payload["me"] as? [String: Any], let username = me["username"] as? String {
            return username
        }
        throw BookCatalogError.invalidHardcoverToken
    }

    public func syncHardcoverStatus(bookID: Int, statusID: Int, token rawToken: String) async -> Bool {
        let token = Self.cleanToken(rawToken)
        guard !token.isEmpty, bookID > 0 else { return false }
        let mutation = """
        mutation SyncStatus($bookId: Int!, $statusId: Int!) {
          insert_user_book(object: { book_id: $bookId, status_id: $statusId }) {
            id
          }
        }
        """
        guard let data = try? await postHardcover(
            query: mutation,
            variables: ["bookId": bookID, "statusId": statusID],
            token: token
        ),
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        root["errors"] == nil
        else {
            return false
        }
        return true
    }

    public func search(_ query: BookCatalogQuery, hardcoverToken: String?) async -> BookCatalogSearchResult {
        let cleanToken = hardcoverToken.map(Self.cleanToken) ?? ""
        async let openLibraryOutcome = searchOpenLibraryCatching(query)
        let hardcoverOutcome: Result<[BookCatalogMatch], BookCatalogError>?
        if cleanToken.isEmpty {
            hardcoverOutcome = nil
        } else {
            hardcoverOutcome = await searchHardcoverCatching(query, token: cleanToken)
        }
        let olResult = await openLibraryOutcome

        var combined: [BookCatalogMatch] = []
        var warnings: [String] = []

        if let hcResult = hardcoverOutcome {
            switch hcResult {
            case .success(let items):
                combined.append(contentsOf: items)
            case .failure(let error):
                warnings.append(error.localizedDescription)
            }
        }

        switch olResult {
        case .success(let items):
            combined.append(contentsOf: items)
        case .failure(let error):
            warnings.append(error.localizedDescription)
        }

        let ranked = Self.deduplicate(combined).sorted { lhs, rhs in
            let lScore = Self.matchConfidence(query: query, match: lhs) + Self.popularityBonus(lhs)
            let rScore = Self.matchConfidence(query: query, match: rhs) + Self.popularityBonus(rhs)
            if lScore != rScore { return lScore > rScore }
            return lhs.richnessScore > rhs.richnessScore
        }
        return BookCatalogSearchResult(matches: ranked, warnings: warnings)
    }

    public func bestMatch(for query: BookCatalogQuery, hardcoverToken: String?) async -> BookCatalogMatch? {
        let cleanToken = hardcoverToken.map(Self.cleanToken) ?? ""
        if !cleanToken.isEmpty, let items = try? await searchHardcover(query, token: cleanToken),
           let winner = Self.pickBest(from: items, query: query) {
            return await hydrateDetails(for: winner, hardcoverToken: cleanToken)
        }
        if let items = try? await searchOpenLibrary(query),
           let winner = Self.pickBest(from: items, query: query) {
            return await hydrateDetails(for: winner, hardcoverToken: nil)
        }
        return nil
    }

    public func hydrateDetails(for match: BookCatalogMatch, hardcoverToken: String? = nil) async -> BookCatalogMatch {
        if match.source == .hardcover {
            let token = hardcoverToken.map(Self.cleanToken) ?? ""
            guard !token.isEmpty,
                  let hcID = match.hardcoverBookID,
                  (match.seriesName == nil || match.genres.isEmpty || match.publisher == nil || match.catalogURL == nil || match.summary == nil)
            else {
                return match
            }
            let gql = """
            query HydrateBook($id: Int!) {
              books(where: { id: { _eq: $id } }, limit: 1) {
                id
                slug
                title
                description
                pages
                release_year
                rating
                ratings_count
                cached_tags
                image { url }
                contributions { author { name } }
                book_series {
                  position
                  series { name }
                }
                editions(limit: 3) {
                  isbn_13
                  isbn_10
                  pages
                  publisher { name }
                  language { code2 }
                  image { url }
                }
              }
            }
            """
            guard let data = try? await postHardcover(query: gql, variables: ["id": hcID], token: token),
                  let hydrated = Self.parseHardcoverBooksJSON(data).first
            else {
                return match
            }
            return BookCatalogMatch(
                id: match.id,
                source: match.source,
                title: match.title,
                authors: match.authors.isEmpty ? hydrated.authors : match.authors,
                publisher: match.publisher ?? hydrated.publisher,
                language: match.language ?? hydrated.language,
                pageCount: match.pageCount ?? hydrated.pageCount,
                summary: match.summary ?? hydrated.summary,
                isbn: match.isbn ?? hydrated.isbn,
                releaseYear: match.releaseYear ?? hydrated.releaseYear,
                coverURL: match.coverURL ?? hydrated.coverURL,
                workKey: match.workKey ?? hydrated.workKey,
                seriesName: match.seriesName ?? hydrated.seriesName,
                seriesPosition: match.seriesPosition ?? hydrated.seriesPosition,
                genres: match.genres.isEmpty ? hydrated.genres : match.genres,
                moods: match.moods.isEmpty ? hydrated.moods : match.moods,
                rating: match.rating ?? hydrated.rating,
                ratingsCount: match.ratingsCount ?? hydrated.ratingsCount,
                catalogSlug: match.catalogSlug ?? hydrated.catalogSlug,
                hardcoverBookID: match.hardcoverBookID ?? hydrated.hardcoverBookID,
                catalogURL: match.catalogURL ?? hydrated.catalogURL
            )
        }

        guard match.source == .openLibrary,
              (match.summary == nil || match.genres.isEmpty),
              let workKey = match.workKey
        else {
            return match
        }
        let normalizedKey = workKey.hasPrefix("/") ? workKey : "/\(workKey)"
        guard let url = URL(string: "https://openlibrary.org\(normalizedKey).json") else {
            return match
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        guard
            let (data, response) = try? await session.data(for: request),
            let http = response as? HTTPURLResponse,
            http.statusCode == 200
        else {
            return match
        }
        let details = Self.parseOpenLibraryWorkDetails(data)
        return BookCatalogMatch(
            id: match.id,
            source: match.source,
            title: match.title,
            authors: match.authors,
            publisher: match.publisher,
            language: match.language,
            pageCount: match.pageCount,
            summary: match.summary ?? details.description,
            isbn: match.isbn,
            releaseYear: match.releaseYear,
            coverURL: match.coverURL,
            workKey: match.workKey,
            seriesName: match.seriesName,
            seriesPosition: match.seriesPosition,
            genres: match.genres.isEmpty ? details.genres : match.genres,
            moods: match.moods,
            rating: match.rating,
            ratingsCount: match.ratingsCount,
            catalogSlug: match.catalogSlug,
            hardcoverBookID: match.hardcoverBookID,
            catalogURL: match.catalogURL
        )
    }

    public func downloadCoverData(from url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        guard
            let (data, response) = try? await session.data(for: request),
            let http = response as? HTTPURLResponse,
            http.statusCode == 200,
            data.count >= 2048
        else {
            return nil
        }
        return data
    }

    private func searchHardcoverCatching(_ query: BookCatalogQuery, token: String) async -> Result<[BookCatalogMatch], BookCatalogError> {
        do {
            return .success(try await searchHardcover(query, token: token))
        } catch let error as BookCatalogError {
            return .failure(error)
        } catch {
            return .failure(.networkFailed(error.localizedDescription))
        }
    }

    private func searchOpenLibraryCatching(_ query: BookCatalogQuery) async -> Result<[BookCatalogMatch], BookCatalogError> {
        do {
            return .success(try await searchOpenLibrary(query))
        } catch let error as BookCatalogError {
            return .failure(error)
        } catch {
            return .failure(.networkFailed(error.localizedDescription))
        }
    }

    private func searchHardcover(_ query: BookCatalogQuery, token: String) async throws -> [BookCatalogMatch] {
        if let isbn = query.isbn {
            let gql = """
            query EditionByISBN($isbn: String!) {
              editions(where: { _or: [{ isbn_13: { _eq: $isbn } }, { isbn_10: { _eq: $isbn } }] }, limit: 5) {
                id
                title
                isbn_13
                isbn_10
                pages
                release_date
                publisher { name }
                language { code2 }
                image { url }
                book {
                  id
                  slug
                  title
                  description
                  pages
                  release_year
                  rating
                  ratings_count
                  cached_tags
                  image { url }
                  contributions { author { name } }
                  book_series {
                    position
                    series { name }
                  }
                }
              }
            }
            """
            let data = try await postHardcover(query: gql, variables: ["isbn": isbn], token: token)
            let matches = Self.parseHardcoverEditionsJSON(data)
            if !matches.isEmpty { return matches }
        }

        let combinedQuery = [query.title, query.author].compactMap { $0 }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !combinedQuery.isEmpty else { return [] }

        let searchGQL = """
        query SearchBooks($q: String!) {
          search(query: $q, query_type: "Book", per_page: 8, page: 1) {
            results
          }
        }
        """
        if let searchData = try? await postHardcover(query: searchGQL, variables: ["q": combinedQuery], token: token) {
            let matches = Self.parseHardcoverSearchJSON(searchData)
            if !matches.isEmpty { return matches }
        }

        guard !query.title.isEmpty else { return [] }
        let booksGQL = """
        query FallbackBooks($pattern: String!) {
          books(where: { title: { _ilike: $pattern } }, limit: 8) {
            id
            slug
            title
            description
            pages
            release_year
            rating
            ratings_count
            cached_tags
            image { url }
            contributions { author { name } }
            book_series {
              position
              series { name }
            }
            editions(limit: 3) {
              isbn_13
              isbn_10
              pages
              publisher { name }
              language { code2 }
              image { url }
            }
          }
        }
        """
        let fallbackData = try await postHardcover(query: booksGQL, variables: ["pattern": "%\(query.title)%"], token: token)
        return Self.parseHardcoverBooksJSON(fallbackData)
    }

    private func postHardcover(query: String, variables: [String: Any], token: String) async throws -> Data {
        var request = URLRequest(url: Self.hardcoverEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw BookCatalogError.invalidHardcoverToken
            }
            if http.statusCode == 429 {
                throw BookCatalogError.rateLimited
            }
            if !(200..<300).contains(http.statusCode) {
                throw BookCatalogError.networkFailed("HTTP \(http.statusCode)")
            }
        }
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errors = root["errors"] as? [[String: Any]],
           let first = errors.first {
            let msg = (first["message"] as? String ?? "").lowercased()
            if msg.contains("jwt") || msg.contains("unauthorized") || msg.contains("authentication") || msg.contains("invalid token") {
                throw BookCatalogError.invalidHardcoverToken
            }
        }
        return data
    }

    private func searchOpenLibrary(_ query: BookCatalogQuery) async throws -> [BookCatalogMatch] {
        let fields = "key,title,author_name,publisher,language,number_of_pages_median,isbn,cover_i,first_publish_year,subject,ratings_average,ratings_count"
        if let isbn = query.isbn {
            var comps = URLComponents(string: "https://openlibrary.org/search.json")!
            comps.queryItems = [
                URLQueryItem(name: "isbn", value: isbn),
                URLQueryItem(name: "fields", value: fields),
                URLQueryItem(name: "limit", value: "5"),
            ]
            if let url = comps.url {
                let matches = try await fetchOpenLibrarySearch(url: url)
                if !matches.isEmpty { return matches }
            }
        }

        if !query.title.isEmpty {
            var comps = URLComponents(string: "https://openlibrary.org/search.json")!
            var items = [
                URLQueryItem(name: "title", value: query.title),
                URLQueryItem(name: "fields", value: fields),
                URLQueryItem(name: "limit", value: "8"),
            ]
            if let author = query.author {
                items.append(URLQueryItem(name: "author", value: author))
            }
            comps.queryItems = items
            if let url = comps.url {
                let matches = try await fetchOpenLibrarySearch(url: url)
                if !matches.isEmpty { return matches }
            }
        }

        let fallbackQ = [query.title, query.author].compactMap { $0 }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fallbackQ.isEmpty else { return [] }
        var comps = URLComponents(string: "https://openlibrary.org/search.json")!
        comps.queryItems = [
            URLQueryItem(name: "q", value: fallbackQ),
            URLQueryItem(name: "fields", value: fields),
            URLQueryItem(name: "limit", value: "8"),
        ]
        guard let url = comps.url else { return [] }
        return try await fetchOpenLibrarySearch(url: url)
    }

    private func fetchOpenLibrarySearch(url: URL) async throws -> [BookCatalogMatch] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 429 { throw BookCatalogError.rateLimited }
            if !(200..<300).contains(http.statusCode) {
                throw BookCatalogError.networkFailed("HTTP \(http.statusCode)")
            }
        }
        return Self.parseOpenLibrarySearchJSON(data)
    }

    public static func parseHardcoverEditionsJSON(_ data: Data) -> [BookCatalogMatch] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataObj = root["data"] as? [String: Any],
            let editions = dataObj["editions"] as? [[String: Any]]
        else { return [] }

        return editions.compactMap { ed -> BookCatalogMatch? in
            let bookObj = ed["book"] as? [String: Any] ?? [:]
            guard let rawTitle = cleanString(ed["title"]) ?? cleanString(bookObj["title"]) else { return nil }
            let bookID = intValue(bookObj["id"])
            let id = stringID(bookObj["id"]) ?? stringID(ed["id"]) ?? UUID().uuidString
            let slug = cleanString(bookObj["slug"])
            let authors = extractAuthors(from: bookObj["contributions"])
            let publisher = cleanString((ed["publisher"] as? [String: Any])?["name"])
            let language = normalizeLanguage(cleanString((ed["language"] as? [String: Any])?["code2"]))
            let pageCount = intValue(ed["pages"]) ?? intValue(bookObj["pages"])
            let summary = cleanDescription(bookObj["description"] as? String)
            let isbn = cleanString(ed["isbn_13"]) ?? cleanString(ed["isbn_10"])
            let releaseYear = intValue(bookObj["release_year"]) ?? yearPrefix(cleanString(ed["release_date"]))
            let coverURL = extractImageURL(ed["image"]) ?? extractImageURL(bookObj["image"])
            let series = extractHardcoverSeries(from: bookObj["book_series"])
            let tags = extractHardcoverTags(from: bookObj["cached_tags"])
            let rating = clampRating(doubleValue(bookObj["rating"]))
            let ratingsCount = intValue(bookObj["ratings_count"])
            let catalogURL = slug.flatMap { URL(string: "https://hardcover.app/books/\($0)") }
            return BookCatalogMatch(
                id: "hc:\(id)",
                source: .hardcover,
                title: rawTitle,
                authors: authors,
                publisher: publisher,
                language: language,
                pageCount: pageCount,
                summary: summary,
                isbn: isbn,
                releaseYear: releaseYear,
                coverURL: coverURL,
                seriesName: series.name,
                seriesPosition: series.position,
                genres: tags.genres,
                moods: tags.moods,
                rating: rating,
                ratingsCount: ratingsCount,
                catalogSlug: slug,
                hardcoverBookID: bookID,
                catalogURL: catalogURL
            )
        }
    }

    public static func parseHardcoverSearchJSON(_ data: Data) -> [BookCatalogMatch] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataObj = root["data"] as? [String: Any],
            let searchObj = dataObj["search"] as? [String: Any]
        else { return [] }

        let resultsObj: [String: Any]
        if let dict = searchObj["results"] as? [String: Any] {
            resultsObj = dict
        } else if let raw = searchObj["results"] as? String,
                  let rawData = raw.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any] {
            resultsObj = dict
        } else {
            return []
        }

        guard let hits = resultsObj["hits"] as? [[String: Any]] else { return [] }
        return hits.compactMap { hit -> BookCatalogMatch? in
            guard let doc = hit["document"] as? [String: Any],
                  let title = cleanString(doc["title"])
            else { return nil }
            let bookID = intValue(doc["id"])
            let id = stringID(doc["id"]) ?? UUID().uuidString
            let slug = cleanString(doc["slug"])
            let authors = (doc["author_names"] as? [Any])?.compactMap(cleanString)
                ?? extractAuthors(from: doc["contributions"])
            let pageCount = intValue(doc["pages"])
            let summary = cleanDescription(doc["description"] as? String)
            let releaseYear = intValue(doc["release_year"])
            let isbn = (doc["isbns"] as? [Any])?.compactMap(cleanString).first { $0.count == 13 }
                ?? (doc["isbns"] as? [Any])?.compactMap(cleanString).first
                ?? cleanString(doc["isbn_13"])
            let coverURL = extractImageURL(doc["image"])
            let featuredSeries = doc["featured_series"] as? [String: Any]
            let seriesName = cleanString((featuredSeries?["series"] as? [String: Any])?["name"])
                ?? (doc["series_names"] as? [Any])?.compactMap(cleanString).first
            let seriesPosition = doubleValue(featuredSeries?["position"])
            let genres = cleanGenres(from: (doc["genres"] as? [Any])?.compactMap(cleanString) ?? [], limit: 4)
            let moods = cleanGenres(from: (doc["moods"] as? [Any])?.compactMap(cleanString) ?? [], limit: 3)
            let rating = clampRating(doubleValue(doc["rating"]))
            let ratingsCount = intValue(doc["ratings_count"])
            let catalogURL = slug.flatMap { URL(string: "https://hardcover.app/books/\($0)") }
            return BookCatalogMatch(
                id: "hc:\(id)",
                source: .hardcover,
                title: title,
                authors: authors,
                publisher: nil,
                language: nil,
                pageCount: pageCount,
                summary: summary,
                isbn: isbn,
                releaseYear: releaseYear,
                coverURL: coverURL,
                seriesName: seriesName,
                seriesPosition: seriesPosition,
                genres: genres,
                moods: moods,
                rating: rating,
                ratingsCount: ratingsCount,
                catalogSlug: slug,
                hardcoverBookID: bookID,
                catalogURL: catalogURL
            )
        }
    }

    public static func parseHardcoverBooksJSON(_ data: Data) -> [BookCatalogMatch] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataObj = root["data"] as? [String: Any],
            let books = dataObj["books"] as? [[String: Any]]
        else { return [] }

        return books.compactMap { book -> BookCatalogMatch? in
            guard let title = cleanString(book["title"]) else { return nil }
            let bookID = intValue(book["id"])
            let id = stringID(book["id"]) ?? UUID().uuidString
            let slug = cleanString(book["slug"])
            let authors = extractAuthors(from: book["contributions"])
            let editions = book["editions"] as? [[String: Any]] ?? []
            let firstEdition = editions.first { $0["isbn_13"] != nil || $0["image"] != nil } ?? editions.first
            let publisher = firstEdition.flatMap { cleanString(($0["publisher"] as? [String: Any])?["name"]) }
            let language = firstEdition.flatMap { normalizeLanguage(cleanString(($0["language"] as? [String: Any])?["code2"])) }
            let pageCount = intValue(book["pages"]) ?? firstEdition.flatMap { intValue($0["pages"]) }
            let summary = cleanDescription(book["description"] as? String)
            let isbn = firstEdition.flatMap { cleanString($0["isbn_13"]) ?? cleanString($0["isbn_10"]) }
            let releaseYear = intValue(book["release_year"])
            let coverURL = extractImageURL(book["image"]) ?? firstEdition.flatMap { extractImageURL($0["image"]) }
            let series = extractHardcoverSeries(from: book["book_series"])
            let tags = extractHardcoverTags(from: book["cached_tags"])
            let rating = clampRating(doubleValue(book["rating"]))
            let ratingsCount = intValue(book["ratings_count"])
            let catalogURL = slug.flatMap { URL(string: "https://hardcover.app/books/\($0)") }
            return BookCatalogMatch(
                id: "hc:\(id)",
                source: .hardcover,
                title: title,
                authors: authors,
                publisher: publisher,
                language: language,
                pageCount: pageCount,
                summary: summary,
                isbn: isbn,
                releaseYear: releaseYear,
                coverURL: coverURL,
                seriesName: series.name,
                seriesPosition: series.position,
                genres: tags.genres,
                moods: tags.moods,
                rating: rating,
                ratingsCount: ratingsCount,
                catalogSlug: slug,
                hardcoverBookID: bookID,
                catalogURL: catalogURL
            )
        }
    }

    public static func parseOpenLibrarySearchJSON(_ data: Data) -> [BookCatalogMatch] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let docs = root["docs"] as? [[String: Any]]
        else { return [] }

        return docs.compactMap { doc -> BookCatalogMatch? in
            guard let title = cleanString(doc["title"]) else { return nil }
            let workKey = cleanString(doc["key"])
            let id = workKey ?? UUID().uuidString
            let authors = (doc["author_name"] as? [Any])?.compactMap(cleanString) ?? []
            let publisher = (doc["publisher"] as? [Any])?.compactMap(cleanString).first
            let rawLang = (doc["language"] as? [Any])?.compactMap(cleanString).first
            let language = normalizeLanguage(rawLang)
            let pageCount = intValue(doc["number_of_pages_median"])
            let isbns = (doc["isbn"] as? [Any])?.compactMap { cleanString($0).flatMap(ISBNExtractor.normalize) } ?? []
            let isbn = isbns.first { $0.count == 13 } ?? isbns.first
            let releaseYear = intValue(doc["first_publish_year"])
            let genres = cleanGenres(from: (doc["subject"] as? [Any])?.compactMap(cleanString) ?? [], limit: 4)
            let rating = clampRating(doubleValue(doc["ratings_average"]))
            let ratingsCount = intValue(doc["ratings_count"])
            let catalogURL = workKey.flatMap {
                let normalized = $0.hasPrefix("/") ? $0 : "/\($0)"
                return URL(string: "https://openlibrary.org\(normalized)")
            }
            let coverURL: URL?
            if let coverID = intValue(doc["cover_i"]), coverID > 0 {
                coverURL = URL(string: "https://covers.openlibrary.org/b/id/\(coverID)-L.jpg?default=false")
            } else if let isbn {
                coverURL = URL(string: "https://covers.openlibrary.org/b/isbn/\(isbn)-L.jpg?default=false")
            } else {
                coverURL = nil
            }
            return BookCatalogMatch(
                id: "ol:\(id)",
                source: .openLibrary,
                title: title,
                authors: authors,
                publisher: publisher,
                language: language,
                pageCount: pageCount,
                summary: nil,
                isbn: isbn,
                releaseYear: releaseYear,
                coverURL: coverURL,
                workKey: workKey,
                genres: genres,
                rating: rating,
                ratingsCount: ratingsCount,
                catalogURL: catalogURL
            )
        }
    }

    public static func parseOpenLibraryWorkDescription(_ data: Data) -> String? {
        parseOpenLibraryWorkDetails(data).description
    }

    public static func parseOpenLibraryWorkDetails(_ data: Data) -> (description: String?, genres: [String]) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, [])
        }
        let description: String?
        if let str = root["description"] as? String {
            description = cleanDescription(str)
        } else if let dict = root["description"] as? [String: Any], let value = dict["value"] as? String {
            description = cleanDescription(value)
        } else {
            description = nil
        }
        let rawSubjects = (root["subjects"] as? [Any])?.compactMap(cleanString) ?? []
        return (description, cleanGenres(from: rawSubjects, limit: 4))
    }

    public static func cleanGenres(from rawSubjects: [String], limit: Int = 4) -> [String] {
        let noisyFragments = [
            "accessible book",
            "protected daisy",
            "in library",
            "overdrive",
            "lending library",
            "large type",
            "open library staff picks",
            "reading level",
            "nyt:",
            "new york times",
            "award",
            "bestseller",
            "internet archive",
        ]
        var seen: Set<String> = []
        var result: [String] = []
        for raw in rawSubjects {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= 26, !trimmed.contains("--"), !trimmed.contains("("), !trimmed.contains("/") else { continue }
            if trimmed.rangeOfCharacter(from: .decimalDigits) != nil { continue }
            let lower = trimmed.lowercased()
            if noisyFragments.contains(where: { lower.contains($0) }) { continue }
            if lower == "fiction" && result.contains(where: { $0.lowercased().contains("fiction") }) { continue }
            if seen.insert(lower).inserted {
                result.append(trimmed.capitalized)
                if result.count >= limit { break }
            }
        }
        return result
    }

    public static func matchConfidence(query: BookCatalogQuery, match: BookCatalogMatch) -> Double {
        if let qISBN = query.isbn, let mISBN = match.isbn {
            if qISBN == mISBN { return 1.0 }
            if qISBN.count >= 10 && mISBN.count >= 10 {
                let qCore = String(qISBN.suffix(10).prefix(9))
                let mCore = String(mISBN.suffix(10).prefix(9))
                if qCore == mCore { return 0.98 }
            }
        }
        let qTitle = normalizedWords(stripSubtitle(query.title))
        let mTitle = normalizedWords(stripSubtitle(match.title))
        guard !qTitle.isEmpty, !mTitle.isEmpty else { return 0 }

        let titleScore: Double
        if qTitle == mTitle {
            titleScore = 1.0
        } else {
            let intersection = qTitle.intersection(mTitle).count
            let union = qTitle.union(mTitle).count
            titleScore = union > 0 ? Double(intersection) / Double(union) : 0
        }
        guard titleScore > 0 else { return 0 }

        var finalScore: Double
        if let qAuthor = query.author, !match.authors.isEmpty {
            let qAuthWords = normalizedWords(qAuthor)
            let mAuthWords = normalizedWords(match.authors.joined(separator: " "))
            let authMatch = !qAuthWords.isDisjoint(with: mAuthWords)
            if authMatch {
                finalScore = min(1.0, titleScore * 0.8 + 0.2)
            } else {
                finalScore = titleScore * 0.65
            }
        } else {
            finalScore = titleScore * 0.82
        }

        let mLower = match.title.lowercased()
        let qLower = query.title.lowercased()
        if !qLower.contains("summary") && !qLower.contains("study guide") {
            if mLower.hasPrefix("summary ") || mLower.hasPrefix("summary:") || mLower.contains("summary and analysis") || mLower.contains("study guide") {
                finalScore *= 0.35
            }
        }
        return finalScore
    }

    private static func popularityBonus(_ match: BookCatalogMatch) -> Double {
        let countBonus = min(0.18, log10(Double(max(1, match.ratingsCount ?? 0))) / 25.0)
        return countBonus + (match.source == .hardcover ? 0.04 : 0.0)
    }

    private static func pickBest(from items: [BookCatalogMatch], query: BookCatalogQuery) -> BookCatalogMatch? {
        var best: (match: BookCatalogMatch, confidence: Double, rank: Double)?
        for item in items {
            let confidence = matchConfidence(query: query, match: item)
            let rank = confidence + popularityBonus(item)
            if let existing = best {
                if confidence >= 0.72 && existing.confidence < 0.72 {
                    best = (item, confidence, rank)
                } else if abs(confidence - existing.confidence) <= 0.04 {
                    if rank > existing.rank || (abs(rank - existing.rank) <= 0.01 && item.richnessScore > existing.match.richnessScore) {
                        best = (item, confidence, rank)
                    }
                } else if confidence > existing.confidence {
                    best = (item, confidence, rank)
                }
            } else {
                best = (item, confidence, rank)
            }
        }
        guard let best, best.confidence >= 0.72 else { return nil }
        return best.match
    }

    private static func deduplicate(_ items: [BookCatalogMatch]) -> [BookCatalogMatch] {
        var byKey: [String: BookCatalogMatch] = [:]
        var order: [String] = []
        for item in items {
            let titleKey = normalizedWords(stripSubtitle(item.title)).sorted().joined(separator: " ")
            let authorKey = normalizedWords(item.authors.first ?? "").sorted().joined(separator: " ")
            let key = "\(titleKey)|\(authorKey)"
            if let existing = byKey[key] {
                if item.richnessScore > existing.richnessScore {
                    byKey[key] = item
                }
            } else {
                byKey[key] = item
                order.append(key)
            }
        }
        return order.compactMap { byKey[$0] }
    }

    private static func extractHardcoverSeries(from value: Any?) -> (name: String?, position: Double?) {
        guard let entries = value as? [[String: Any]] else { return (nil, nil) }
        for entry in entries {
            if let series = entry["series"] as? [String: Any], let name = cleanString(series["name"]) {
                return (name, doubleValue(entry["position"]))
            }
        }
        return (nil, nil)
    }

    private static func extractHardcoverTags(from value: Any?) -> (genres: [String], moods: [String]) {
        guard let dict = value as? [String: Any] else { return ([], []) }
        func tagNames(_ key: String, limit: Int) -> [String] {
            let rawList: [String]
            if let objs = dict[key] as? [[String: Any]] {
                rawList = objs.compactMap { cleanString($0["tag"]) ?? cleanString($0["name"]) }
            } else if let strs = dict[key] as? [Any] {
                rawList = strs.compactMap(cleanString)
            } else {
                rawList = []
            }
            return cleanGenres(from: rawList, limit: limit)
        }
        return (tagNames("Genre", limit: 4), tagNames("Mood", limit: 3))
    }

    private static func cleanToken(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("bearer ") {
            trimmed = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private static func cleanString(_ value: Any?) -> String? {
        guard let str = value as? String else { return nil }
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func stringID(_ value: Any?) -> String? {
        if let str = cleanString(value) { return str }
        if let num = value as? Int { return String(num) }
        if let num = value as? NSNumber { return num.stringValue }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let n = value as? Int, n > 0 { return n }
        if let d = value as? Double, d > 0 { return Int(d) }
        if let s = value as? String, let n = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)), n > 0 { return n }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let n = value as? Int { return Double(n) }
        if let num = value as? NSNumber { return num.doubleValue }
        if let s = value as? String { return Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    private static func clampRating(_ value: Double?) -> Double? {
        guard let value, value >= 0.1, value <= 5.0 else { return nil }
        return value
    }

    private static func yearPrefix(_ raw: String?) -> Int? {
        guard let raw, raw.count >= 4 else { return nil }
        return Int(raw.prefix(4))
    }

    private static func extractAuthors(from value: Any?) -> [String] {
        guard let arr = value as? [[String: Any]] else { return [] }
        return arr.compactMap { item in
            cleanString((item["author"] as? [String: Any])?["name"]) ?? cleanString(item["name"])
        }
    }

    private static func extractImageURL(_ value: Any?) -> URL? {
        if let str = cleanString(value) {
            return URL(string: str)
        }
        if let dict = value as? [String: Any], let str = cleanString(dict["url"]) {
            return URL(string: str)
        }
        return nil
    }

    private static func cleanDescription(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let stripped = raw.contains("<") ? HTMLText.plainText(from: raw) : raw
        let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func normalizeLanguage(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty else {
            return nil
        }
        switch raw {
        case "eng": return "en"
        case "fre", "fra": return "fr"
        case "ger", "deu": return "de"
        case "spa": return "es"
        case "ita": return "it"
        case "jpn": return "ja"
        case "por": return "pt"
        case "rus": return "ru"
        case "chi", "zho": return "zh"
        case "nld", "dut": return "nl"
        default: return raw
        }
    }

    private static func stripSubtitle(_ raw: String) -> String {
        if let colon = raw.firstIndex(of: ":") {
            let head = String(raw[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
            if head.count >= 3 { return head }
        }
        return raw
    }

    private static func normalizedWords(_ raw: String) -> Set<String> {
        let folded = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let parts = folded.split { !$0.isLetter && !$0.isNumber }
        return Set(parts.map(String.init))
    }
}
