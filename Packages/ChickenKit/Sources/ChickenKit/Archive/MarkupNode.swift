import Foundation

struct MarkupNode: Sendable {
    enum Content: Sendable {
        case text(String)
        case element(MarkupNode)
    }

    let name: String
    let attributes: [String: String]
    let contents: [Content]

    var localName: String { Self.localName(of: name) }

    var children: [MarkupNode] {
        contents.compactMap {
            if case .element(let node) = $0 { return node }
            return nil
        }
    }

    /// Concatenated text of this node and all descendants, in document order.
    var textContent: String {
        var output = ""
        collectText(into: &output)
        return output
    }

    private func collectText(into output: inout String) {
        for item in contents {
            switch item {
            case .text(let text): output += text
            case .element(let node): node.collectText(into: &output)
            }
        }
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
        collectDescendants(named: name, into: &result)
        return result
    }

    private func collectDescendants(named name: String, into result: inout [MarkupNode]) {
        for item in contents {
            guard case .element(let child) = item else { continue }
            if child.localName.caseInsensitiveCompare(name) == .orderedSame {
                result.append(child)
            }
            child.collectDescendants(named: name, into: &result)
        }
    }

    func firstDescendant(_ name: String) -> MarkupNode? {
        for item in contents {
            guard case .element(let child) = item else { continue }
            if child.localName.caseInsensitiveCompare(name) == .orderedSame { return child }
            if let found = child.firstDescendant(name) { return found }
        }
        return nil
    }

    static func localName(of qualifiedName: String) -> String {
        guard let colon = qualifiedName.lastIndex(of: ":") else { return qualifiedName }
        return String(qualifiedName[qualifiedName.index(after: colon)...])
    }

    static func parse(_ data: Data) -> MarkupNode? {
        if let root = Builder().parse(data) { return root }
        // XHTML from EPUBs often uses HTML named entities (&nbsp;, &mdash;)
        // that XML doesn't declare. Rewrite them numerically and try again.
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let repaired = HTMLText.numericEntities(in: text, dropUnknown: true)
        guard repaired != text, let repairedData = repaired.data(using: .utf8) else { return nil }
        return Builder().parse(repairedData)
    }

    private final class Builder: NSObject, XMLParserDelegate {
        private struct Frame {
            let name: String
            let attributes: [String: String]
            var contents: [MarkupNode.Content] = []
        }

        private var root: MarkupNode?
        private var stack: [Frame] = []
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
            stack.append(Frame(name: elementName, attributes: attributeDict))
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            guard let frame = stack.popLast() else { return }
            let node = MarkupNode(name: frame.name, attributes: frame.attributes, contents: frame.contents)
            if stack.isEmpty {
                root = node
            } else {
                stack[stack.count - 1].contents.append(.element(node))
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard !stack.isEmpty else { return }
            stack[stack.count - 1].contents.append(.text(string))
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            guard !stack.isEmpty, let text = String(data: CDATABlock, encoding: .utf8) else { return }
            stack[stack.count - 1].contents.append(.text(text))
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
        "Eacute": "&#201;", "Egrave": "&#200;", "Agrave": "&#192;", "Ouml": "&#214;",
        "Uuml": "&#220;", "Auml": "&#196;", "Ccedil": "&#199;", "Ntilde": "&#209;",
        "ecirc": "&#234;", "acirc": "&#226;", "icirc": "&#238;", "ocirc": "&#244;", "ucirc": "&#251;",
        "oelig": "&#339;", "OElig": "&#338;", "aelig": "&#230;", "AElig": "&#198;", "szlig": "&#223;",
        "laquo": "&#171;", "raquo": "&#187;", "middot": "&#183;", "bull": "&#8226;",
        "thinsp": "&#8201;", "ensp": "&#8194;", "emsp": "&#8195;", "times": "&#215;",
        "euro": "&#8364;", "pound": "&#163;", "yen": "&#165;", "cent": "&#162;",
        "deg": "&#176;", "sect": "&#167;", "para": "&#182;", "dagger": "&#8224;", "Dagger": "&#8225;",
        "frac12": "&#189;", "frac14": "&#188;", "frac34": "&#190;", "plusmn": "&#177;",
        "minus": "&#8722;", "divide": "&#247;", "prime": "&#8242;", "Prime": "&#8243;",
        "larr": "&#8592;", "rarr": "&#8594;", "uarr": "&#8593;", "darr": "&#8595;",
    ]

    private static let builtIn: Set<String> = ["amp", "lt", "gt", "quot", "apos"]

    static func numericEntities(in text: String, dropUnknown: Bool = false) -> String {
        guard text.contains("&") else { return text }
        return text.replacing(/&([A-Za-z][A-Za-z0-9]*);/) { match in
            let name = String(match.output.1)
            if builtIn.contains(name) { return String(match.output.0) }
            if let numeric = namedEntities[name] { return numeric }
            return dropUnknown ? "" : String(match.output.0)
        }
    }

    /// Strips tags, decodes common entities, and collapses whitespace.
    public static func plainText(from html: String) -> String {
        var text = html
            .replacing(/<!\[CDATA\[([\s\S]*?)\]\]>/) { String($0.output.1) }
            .replacing(/(?i)<br\s*\/?>|<\/p>/, with: "\n")
            .replacing(/<[^>]+>/, with: "")
        text = decodeEntities(text)
        return text
            .components(separatedBy: "\n")
            .map { $0.replacing(/\s+/, with: " ").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    public static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = numericEntities(in: text, dropUnknown: false)
        result = result
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
        result = result.replacing(/&#([xX]?)([0-9A-Fa-f]+);/) { match in
            let isHex = !match.output.1.isEmpty
            let digits = String(match.output.2)
            guard let value = UInt32(digits, radix: isHex ? 16 : 10),
                  let scalar = Unicode.Scalar(value)
            else { return String(match.output.0) }
            return String(Character(scalar))
        }
        return result.replacingOccurrences(of: "&amp;", with: "&")
    }
}
