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
        var output = String()
        output.reserveCapacity(text.count)
        var cursor = text.startIndex
        while let amp = text[cursor...].firstIndex(of: "&") {
            output.append(contentsOf: text[cursor..<amp])
            let afterAmp = text.index(after: amp)
            if afterAmp < text.endIndex,
               let semi = text[afterAmp...].prefix(20).firstIndex(of: ";"),
               let firstChar = text[afterAmp...].first,
               firstChar.isASCII && firstChar.isLetter,
               text[afterAmp..<semi].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) {
                let name = String(text[afterAmp..<semi])
                if builtIn.contains(name) {
                    output.append(contentsOf: text[amp...semi])
                } else if let numeric = namedEntities[name] {
                    output.append(numeric)
                } else if !dropUnknown {
                    output.append(contentsOf: text[amp...semi])
                }
                cursor = text.index(after: semi)
            } else {
                output.append("&")
                cursor = afterAmp
            }
        }
        output.append(contentsOf: text[cursor...])
        return output
    }

    /// Strips tags, decodes common entities, and collapses whitespace.
    public static func plainText(from html: String) -> String {
        let utf8 = Array(html.utf8)
        let stripped: [UInt8]
        var hasAmpersand = false

        if utf8.contains(0x3C) {
            var out: [UInt8] = []
            out.reserveCapacity(utf8.count / 2)
            let count = utf8.count
            var i = 0
            while i < count {
                let b = utf8[i]
                if b == 0x26 { hasAmpersand = true }
                if b == 0x3C {
                    if i + 9 <= count,
                       utf8[i + 1] == 0x21, utf8[i + 2] == 0x5B, utf8[i + 3] == 0x43,
                       utf8[i + 4] == 0x44, utf8[i + 5] == 0x41, utf8[i + 6] == 0x54,
                       utf8[i + 7] == 0x41, utf8[i + 8] == 0x5B {
                        var j = i + 9
                        var foundEnd = false
                        while j + 2 < count {
                            if utf8[j] == 0x5D && utf8[j + 1] == 0x5D && utf8[j + 2] == 0x3E {
                                foundEnd = true
                                break
                            }
                            if utf8[j] == 0x26 { hasAmpersand = true }
                            out.append(utf8[j])
                            j += 1
                        }
                        if foundEnd {
                            i = j + 3
                            continue
                        }
                    }
                    var close = i + 1
                    while close < count && utf8[close] != 0x3E {
                        close += 1
                    }
                    if close < count {
                        let tagLen = close - (i + 1)
                        if tagLen >= 2 {
                            let b0 = utf8[i + 1]
                            let b1 = utf8[i + 2]
                            if (b0 == 0x62 || b0 == 0x42) && (b1 == 0x72 || b1 == 0x52) {
                                out.append(0x0A)
                            } else if b0 == 0x2F && tagLen >= 2 {
                                if b1 == 0x70 || b1 == 0x50 || b1 == 0x68 || b1 == 0x48 {
                                    out.append(0x0A)
                                } else if tagLen >= 4 {
                                    let b2 = utf8[i + 3]
                                    let b3 = utf8[i + 4]
                                    if ((b1 == 0x64 || b1 == 0x44) && (b2 == 0x69 || b2 == 0x49) && (b3 == 0x76 || b3 == 0x56)) ||
                                        ((b1 == 0x6C || b1 == 0x4C) && (b2 == 0x69 || b2 == 0x49)) {
                                        out.append(0x0A)
                                    }
                                } else if tagLen >= 3 {
                                    let b2 = utf8[i + 3]
                                    if (b1 == 0x6C || b1 == 0x4C) && (b2 == 0x69 || b2 == 0x49) {
                                        out.append(0x0A)
                                    }
                                }
                            }
                        }
                        i = close + 1
                        continue
                    }
                }
                out.append(b)
                i += 1
            }
            stripped = out
        } else {
            stripped = utf8
            hasAmpersand = utf8.contains(0x26)
        }

        let sourceBytes: [UInt8]
        if hasAmpersand {
            let decoded = decodeEntities(String(decoding: stripped, as: UTF8.self))
            sourceBytes = Array(decoded.utf8)
        } else {
            sourceBytes = stripped
        }

        var result: [UInt8] = []
        result.reserveCapacity(sourceBytes.count)
        var inSpace = true
        var lineHasContent = false
        var idx = 0
        let total = sourceBytes.count

        while idx < total {
            let b = sourceBytes[idx]
            if b == 0x0A {
                if !result.isEmpty && result.last == 0x20 {
                    result.removeLast()
                }
                if lineHasContent {
                    result.append(0x0A)
                }
                inSpace = true
                lineHasContent = false
                idx += 1
                continue
            }
            if b == 0x20 || b == 0x09 || b == 0x0D || b == 0x0B || b == 0x0C {
                if !inSpace && lineHasContent {
                    result.append(0x20)
                    inSpace = true
                }
                idx += 1
                continue
            }
            if b == 0xC2 && idx + 1 < total && sourceBytes[idx + 1] == 0xA0 {
                if !inSpace && lineHasContent {
                    result.append(0x20)
                    inSpace = true
                }
                idx += 2
                continue
            }
            if b == 0xE2 && idx + 2 < total && sourceBytes[idx + 1] == 0x80 &&
                ((sourceBytes[idx + 2] >= 0x80 && sourceBytes[idx + 2] <= 0x8B) || sourceBytes[idx + 2] == 0xAF) {
                if !inSpace && lineHasContent {
                    result.append(0x20)
                    inSpace = true
                }
                idx += 3
                continue
            }
            if b == 0xE3 && idx + 2 < total && sourceBytes[idx + 1] == 0x80 && sourceBytes[idx + 2] == 0x80 {
                if !inSpace && lineHasContent {
                    result.append(0x20)
                    inSpace = true
                }
                idx += 3
                continue
            }
            result.append(b)
            inSpace = false
            lineHasContent = true
            idx += 1
        }
        if !result.isEmpty && result.last == 0x20 {
            result.removeLast()
        }
        if !result.isEmpty && result.last == 0x0A {
            result.removeLast()
        }
        return String(decoding: result, as: UTF8.self)
    }

    public static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var output = String()
        output.reserveCapacity(text.count)
        var cursor = text.startIndex
        while let amp = text[cursor...].firstIndex(of: "&") {
            output.append(contentsOf: text[cursor..<amp])
            let afterAmp = text.index(after: amp)
            if afterAmp < text.endIndex, let semi = text[afterAmp...].prefix(20).firstIndex(of: ";") {
                let entity = text[afterAmp..<semi]
                if let resolved = resolveEntity(entity) {
                    output.append(resolved)
                    cursor = text.index(after: semi)
                    continue
                }
            }
            output.append("&")
            cursor = afterAmp
        }
        output.append(contentsOf: text[cursor...])
        return output
    }

    private static func resolveEntity(_ entity: Substring) -> String? {
        if entity.hasPrefix("#") {
            let digits = entity.dropFirst()
            let isHex = digits.first == "x" || digits.first == "X"
            let rawDigits = isHex ? digits.dropFirst() : digits
            guard !rawDigits.isEmpty,
                  let value = UInt32(rawDigits, radix: isHex ? 16 : 10),
                  let scalar = Unicode.Scalar(value)
            else { return nil }
            return String(Character(scalar))
        }
        switch entity {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos": return "'"
        default:
            guard let numeric = namedEntities[String(entity)] else { return nil }
            let inner = numeric.dropFirst(2).dropLast()
            guard let value = UInt32(inner), let scalar = Unicode.Scalar(value) else { return nil }
            return String(Character(scalar))
        }
    }
}
