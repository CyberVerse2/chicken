import Foundation

/// Minimal XML tree built on Foundation's `XMLParser`, which exists on every
/// Apple platform (unlike `XMLDocument`, which is macOS-only). Element and
/// attribute lookups match on local names, so `dc:title` and `title` are the
/// same to callers.
final class MarkupNode: @unchecked Sendable {
    enum Content {
        case text(String)
        case element(MarkupNode)
    }

    let name: String
    let attributes: [String: String]
    private(set) var contents: [Content] = []
    private(set) weak var parent: MarkupNode?

    init(name: String, attributes: [String: String], parent: MarkupNode?) {
        self.name = name
        self.attributes = attributes
        self.parent = parent
    }

    var localName: String { Self.localName(of: name) }

    var children: [MarkupNode] {
        contents.compactMap {
            if case .element(let node) = $0 { return node }
            return nil
        }
    }

    /// Concatenated text of this node and all descendants, in document order.
    var textContent: String {
        contents.map {
            switch $0 {
            case .text(let text): return text
            case .element(let node): return node.textContent
            }
        }.joined()
    }

    func attribute(_ name: String) -> String? {
        if let exact = attributes[name] { return exact }
        let wanted = name.lowercased()
        return attributes.first { Self.localName(of: $0.key).lowercased() == wanted }?.value
    }

    func child(_ name: String) -> MarkupNode? {
        children.first { $0.localName.caseInsensitiveCompare(name) == .orderedSame }
    }

    func children(_ name: String) -> [MarkupNode] {
        children.filter { $0.localName.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Depth-first search over all descendants.
    func descendants(_ name: String) -> [MarkupNode] {
        var result: [MarkupNode] = []
        for child in children {
            if child.localName.caseInsensitiveCompare(name) == .orderedSame { result.append(child) }
            result.append(contentsOf: child.descendants(name))
        }
        return result
    }

    func firstDescendant(_ name: String) -> MarkupNode? {
        for child in children {
            if child.localName.caseInsensitiveCompare(name) == .orderedSame { return child }
            if let found = child.firstDescendant(name) { return found }
        }
        return nil
    }

    fileprivate func append(_ content: Content) {
        contents.append(content)
    }

    static func localName(of qualifiedName: String) -> String {
        guard let colon = qualifiedName.lastIndex(of: ":") else { return qualifiedName }
        return String(qualifiedName[qualifiedName.index(after: colon)...])
    }

    // MARK: Parsing

    static func parse(_ data: Data) -> MarkupNode? {
        let builder = Builder()
        if let root = builder.parse(data) { return root }
        // XHTML from EPUBs often uses HTML named entities (&nbsp;, &mdash;)
        // that XML doesn't declare. Rewrite them numerically and try again.
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let repaired = HTMLText.numericEntities(in: text)
        guard repaired != text, let repairedData = repaired.data(using: .utf8) else { return nil }
        return Builder().parse(repairedData)
    }

    static func parse(_ string: String) -> MarkupNode? {
        guard let data = string.data(using: .utf8) else { return nil }
        return parse(data)
    }

    private final class Builder: NSObject, XMLParserDelegate {
        private var root: MarkupNode?
        private var stack: [MarkupNode] = []
        private var failed = false

        func parse(_ data: Data) -> MarkupNode? {
            let parser = XMLParser(data: data)
            parser.delegate = self
            parser.shouldProcessNamespaces = false
            parser.shouldResolveExternalEntities = false
            guard parser.parse(), !failed else { return nil }
            return root
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            let node = MarkupNode(name: elementName, attributes: attributeDict, parent: stack.last)
            if let parent = stack.last {
                parent.append(.element(node))
            } else if root == nil {
                root = node
            }
            stack.append(node)
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            _ = stack.popLast()
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.append(.text(string))
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            if let text = String(data: CDATABlock, encoding: .utf8) {
                stack.last?.append(.text(text))
            }
        }

        func parser(_ parser: XMLParser, parseErrorOccurred parseError: any Error) {
            failed = true
        }
    }
}

/// Helpers for the loosely-structured HTML found in EPUB metadata and TOCs.
public enum HTMLText {
    private static let namedEntities: [String: String] = [
        "nbsp": "&#160;", "ndash": "&#8211;", "mdash": "&#8212;", "hellip": "&#8230;",
        "lsquo": "&#8216;", "rsquo": "&#8217;", "ldquo": "&#8220;", "rdquo": "&#8221;",
        "copy": "&#169;", "reg": "&#174;", "trade": "&#8482;", "shy": "&#173;",
        "eacute": "&#233;", "egrave": "&#232;", "agrave": "&#224;", "aacute": "&#225;",
        "ouml": "&#246;", "uuml": "&#252;", "auml": "&#228;", "ccedil": "&#231;",
        "iacute": "&#237;", "oacute": "&#243;", "uacute": "&#250;", "ntilde": "&#241;",
        "laquo": "&#171;", "raquo": "&#187;", "middot": "&#183;", "bull": "&#8226;",
        "thinsp": "&#8201;", "ensp": "&#8194;", "emsp": "&#8195;", "times": "&#215;",
    ]

    private static let builtIn: Set<String> = ["amp", "lt", "gt", "quot", "apos"]

    /// Replaces HTML named entities that XML parsers reject with numeric
    /// references. Unknown names are dropped rather than failing the parse.
    static func numericEntities(in text: String) -> String {
        guard text.contains("&") else { return text }
        guard let regex = try? NSRegularExpression(pattern: "&([A-Za-z][A-Za-z0-9]*);") else { return text }
        let ns = text as NSString
        let result = NSMutableString(string: text)
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let name = ns.substring(with: match.range(at: 1))
            if builtIn.contains(name) { continue }
            result.replaceCharacters(in: match.range, with: namedEntities[name] ?? "")
        }
        return result as String
    }

    /// Strips tags, decodes common entities, and collapses whitespace.
    public static func plainText(from html: String) -> String {
        var text = html
            .replacingOccurrences(of: #"<!\[CDATA\[([\s\S]*?)\]\]>"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"<br\s*/?>|</p>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        text = decodeEntities(text)
        return text
            .components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    public static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = numericEntities(in: text)
        result = result
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
        guard let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9A-Fa-f]+);") else {
            return result.replacingOccurrences(of: "&amp;", with: "&")
        }
        let ns = result as NSString
        let mutable = NSMutableString(string: result)
        for match in regex.matches(in: result, range: NSRange(location: 0, length: ns.length)).reversed() {
            let isHex = ns.substring(with: match.range(at: 1)) == "x"
            let digits = ns.substring(with: match.range(at: 2))
            guard let value = UInt32(digits, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(value) else { continue }
            mutable.replaceCharacters(in: match.range, with: String(Character(scalar)))
        }
        return (mutable as String).replacingOccurrences(of: "&amp;", with: "&")
    }
}
