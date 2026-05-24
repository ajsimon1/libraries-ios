import Foundation

struct ISBNBookResult {
    var title: String
    var author: String
    var publishYear: String
    var pageCount: Int
    var coverURL: String?
}

struct ISBNLookupService {
    static func lookup(isbn: String) async throws -> ISBNBookResult {
        // Strip everything that isn't a digit or trailing 'X' (valid ISBN-10 check digit).
        // Handles paste artifacts: en/em dashes, non-breaking spaces, "ISBN:" prefix, smart quotes, etc.
        let cleanISBN = isbn
            .uppercased()
            .filter { $0.isNumber || $0 == "X" }
        #if DEBUG
        print("ISBN_LOOKUP: raw='\(isbn)' clean='\(cleanISBN)' length=\(cleanISBN.count)")
        #endif

        guard cleanISBN.count == 10 || cleanISBN.count == 13 else {
            throw LookupError.invalidISBN
        }

        // Open Library API
        guard let url = URL(string: "https://openlibrary.org/isbn/\(cleanISBN).json") else {
            throw LookupError.invalidISBN
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw LookupError.notFound
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LookupError.parseError
        }

        let title = json["title"] as? String ?? ""
        let pageCount = json["number_of_pages"] as? Int ?? 0
        let publishDate = json["publish_date"] as? String ?? ""

        // Extract cover ID for cover image URL
        var coverURL: String?
        if let covers = json["covers"] as? [Int], let coverId = covers.first {
            coverURL = "https://covers.openlibrary.org/b/id/\(coverId)-L.jpg"
        }

        // Authors come as references, need a second lookup
        var authorName = ""
        if let authors = json["authors"] as? [[String: Any]],
           let authorRef = authors.first?["key"] as? String {
            authorName = try await fetchAuthorName(key: authorRef)
        }

        return ISBNBookResult(
            title: title,
            author: authorName,
            publishYear: publishDate,
            pageCount: pageCount,
            coverURL: coverURL
        )
    }

    private static func fetchAuthorName(key: String) async throws -> String {
        guard let url = URL(string: "https://openlibrary.org\(key).json") else { return "" }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        return json["name"] as? String ?? ""
    }

    static func fetchCoverImage(urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        return try? await URLSession.shared.data(from: url).0
    }

    enum LookupError: LocalizedError {
        case invalidISBN, notFound, parseError

        var errorDescription: String? {
            switch self {
            case .invalidISBN: return "Invalid ISBN format"
            case .notFound: return "Book not found for this ISBN"
            case .parseError: return "Could not read book data"
            }
        }
    }
}
