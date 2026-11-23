import Foundation
import PDFKit

public enum PDFMetadataReader {
    public static func metadata(for url: URL) -> DocumentMetadata {
        guard let document = PDFDocument(url: url) else { return .empty }
        return metadata(for: document)
    }

    static func metadata(for document: PDFDocument) -> DocumentMetadata {
        let attributes = document.documentAttributes
        var isbn: String?
        if let subject = attributes?[PDFDocumentAttribute.subjectAttribute] as? String {
            isbn = ISBNExtractor.extract(from: subject)
        }
        if isbn == nil, let keywords = attributes?[PDFDocumentAttribute.keywordsAttribute] as? [String] {
            for kw in keywords {
                if let found = ISBNExtractor.extract(from: kw) {
                    isbn = found
                    break
                }
            }
        }
        if isbn == nil {
            var collected = ""
            let pageLimit = min(5, document.pageCount)
            for idx in 0..<pageLimit {
                if let pageText = document.page(at: idx)?.string, !pageText.isEmpty {
                    collected.append(pageText)
                    collected.append("\n")
                    if collected.count >= 12_000 {
                        collected = String(collected.prefix(12_000))
                        break
                    }
                }
            }
            isbn = ISBNExtractor.extract(from: collected)
        }
        return DocumentMetadata(
            title: DocumentMetadata.clean(attributes?[PDFDocumentAttribute.titleAttribute] as? String),
            author: DocumentMetadata.clean(attributes?[PDFDocumentAttribute.authorAttribute] as? String),
            pageCount: document.pageCount,
            isbn: isbn
        )
    }

    public static func canOpen(_ url: URL) -> Bool {
        PDFDocument(url: url) != nil
    }
}
