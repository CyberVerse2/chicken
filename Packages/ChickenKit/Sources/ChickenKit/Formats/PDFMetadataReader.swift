import Foundation
import PDFKit

public enum PDFMetadataReader {
    public static func metadata(for url: URL) -> DocumentMetadata {
        guard let document = PDFDocument(url: url) else { return .empty }
        let attributes = document.documentAttributes
        return DocumentMetadata(
            title: DocumentMetadata.clean(attributes?[PDFDocumentAttribute.titleAttribute] as? String),
            author: DocumentMetadata.clean(attributes?[PDFDocumentAttribute.authorAttribute] as? String),
            pageCount: document.pageCount
        )
    }

    public static func canOpen(_ url: URL) -> Bool {
        PDFDocument(url: url) != nil
    }
}
