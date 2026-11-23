import ChickenKit
import SwiftUI

struct TextReader: PlatformViewRepresentable {
    let model: ReaderModel
    let fileURL: URL
    let palette: ReaderPalette
    let fontSize: Double
    let lineHeight: Double
    let columnWidth: Double
    let typeface: ReaderTypeface
    let onTapCenter: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(model: model, palette: palette) }

    #if os(macOS)
    func makeView(context: Context) -> ColumnTextScrollView {
        let scrollView = ColumnTextScrollView()
        context.coordinator.attach(scrollView)
        context.coordinator.load(fileURL)
        return scrollView
    }

    func updateView(_ view: ColumnTextScrollView, context: Context) {
        if view.columnWidth != columnWidth {
            view.columnWidth = columnWidth
            view.needsLayout = true
        }
        context.coordinator.render(palette: palette, fontSize: fontSize, lineHeight: lineHeight, typeface: typeface)
    }

    static func dismantleView(_ view: ColumnTextScrollView, coordinator: Coordinator) {
        coordinator.teardown()
    }
    #else
    func makeView(context: Context) -> ColumnTextView {
        let textView = ColumnTextView()
        context.coordinator.attach(textView, onTapCenter: onTapCenter)
        context.coordinator.load(fileURL)
        return textView
    }

    func updateView(_ view: ColumnTextView, context: Context) {
        if view.columnWidth != columnWidth {
            view.columnWidth = columnWidth
            view.setNeedsLayout()
        }
        context.coordinator.onTapCenter = onTapCenter
        context.coordinator.render(palette: palette, fontSize: fontSize, lineHeight: lineHeight, typeface: typeface)
    }

    static func dismantleView(_ view: ColumnTextView, coordinator: Coordinator) {
        coordinator.teardown()
    }
    #endif

    final class Coordinator: NSObject, ReaderEngine {
        let model: ReaderModel
        var onTapCenter: () -> Void = {}
        private var document: TextDocument?
        private var renderKey = ""
        private var restored = false
        private var lastReported = Date.distantPast
        private var searchQuery = ""
        private var searchMatches: [NSRange] = []
        private var searchFingerprint = ""
        private var searchRange: NSRange?
        private var lastPalette: ReaderPalette
        private var loadTask: Task<Void, Never>?
        private var renderTask: Task<Void, Never>?
        #if os(macOS)
        private weak var scrollView: ColumnTextScrollView?
        private var textView: NSTextView? { scrollView?.documentView as? NSTextView }
        private var scrollObserver: NSObjectProtocol?
        #else
        private weak var textView: ColumnTextView?
        #endif

        init(model: ReaderModel, palette: ReaderPalette) {
            self.model = model
            self.lastPalette = palette
            super.init()
            model.engine = self
            model.chapters = [ReaderChapter(id: 0, title: model.book.displayTitle)]
        }

        #if os(macOS)
        func attach(_ scrollView: ColumnTextScrollView) {
            self.scrollView = scrollView
            scrollView.textView.delegate = self
            scrollView.contentView.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.didScroll() }
            }
        }
        #else
        func attach(_ textView: ColumnTextView, onTapCenter: @escaping () -> Void) {
            self.textView = textView
            self.onTapCenter = onTapCenter
            textView.delegate = self
            textView.onTapCenter = { [weak self] in self?.onTapCenter() }
        }
        #endif

        func teardown() {
            captureLocation()
            loadTask?.cancel()
            loadTask = nil
            renderTask?.cancel()
            renderTask = nil
            #if os(macOS)
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
                self.scrollObserver = nil
            }
            #endif
        }

        isolated deinit {
            loadTask?.cancel()
            renderTask?.cancel()
            #if os(macOS)
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
            }
            #endif
        }

        func load(_ url: URL) {
            loadTask?.cancel()
            loadTask = Task { [weak self] in
                let result = await TextDocumentLoader.load(url)
                guard let self, !Task.isCancelled else { return }
                switch result {
                case .success(let doc):
                    self.document = doc
                    self.model.engineDidBecomeReady()
                    self.renderKey = ""
                    self.render(
                        palette: self.lastPalette,
                        fontSize: self.model.fontSize,
                        lineHeight: self.model.lineHeight,
                        typeface: self.model.typeface
                    )
                case .failure(let error):
                    self.model.engineDidFail(fileURL: url, detail: error.message)
                }
            }
        }

        func render(palette: ReaderPalette, fontSize: Double, lineHeight: Double, typeface: ReaderTypeface) {
            lastPalette = palette
            guard let document, textView != nil else { return }
            let highlightSpecs = (model.book.highlights ?? []).map {
                TextDocumentLoader.HighlightSpec(id: $0.id, text: $0.text, color: $0.color)
            }
            let highlightsKey = highlightSpecs.map { "\($0.id)\($0.color.rawValue)" }.sorted().joined()
            let key = "\(palette.backgroundHex)|\(fontSize)|\(lineHeight)|\(typeface.rawValue)|\(document.fingerprint)|\(highlightsKey)"
            guard key != renderKey else { return }
            let isFirstRender = renderKey.isEmpty
            let anchor = currentProgress
            renderKey = key
            renderTask?.cancel()
            renderTask = Task { [weak self] in
                if !isFirstRender {
                    try? await Task.sleep(for: .milliseconds(35))
                }
                guard !Task.isCancelled else { return }
                let box = await TextDocumentLoader.renderAttributedString(
                    document,
                    palette: palette,
                    fontSize: fontSize,
                    lineHeight: lineHeight,
                    typeface: typeface,
                    highlights: highlightSpecs
                )
                guard let self, !Task.isCancelled, self.renderKey == key, let textView = self.textView else { return }
                #if os(macOS)
                textView.textStorage?.setAttributedString(box.value)
                #else
                textView.attributedText = box.value
                #endif
                if !self.restored {
                    self.restored = true
                    let target = TextLocation.decode(self.model.preferredStartLocation)?.progression ?? self.model.book.progress
                    self.scroll(to: target)
                } else {
                    self.scroll(to: anchor)
                }
            }
        }

        private var currentProgress: Double {
            #if os(macOS)
            guard let scrollView, let document = scrollView.documentView else { return 0 }
            let visible = scrollView.contentView.bounds
            let length = document.frame.height - visible.height
            return length > 0 ? min(1, max(0, visible.minY / length)) : 0
            #else
            guard let textView else { return 0 }
            let length = textView.contentSize.height - textView.bounds.height + textView.adjustedContentInset.bottom
            return length > 0 ? min(1, max(0, textView.contentOffset.y / length)) : 0
            #endif
        }

        private func scroll(to progress: Double) {
            #if os(macOS)
            guard let scrollView, let document = scrollView.documentView else { return }
            let length = max(0, document.frame.height - scrollView.contentView.bounds.height)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: length * progress))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            #else
            guard let textView else { return }
            textView.layoutIfNeeded()
            let length = max(0, textView.contentSize.height - textView.bounds.height)
            textView.setContentOffset(CGPoint(x: 0, y: length * progress), animated: false)
            #endif
            report(force: true)
        }

        fileprivate func didScroll() {
            report(force: false)
        }

        private func report(force: Bool) {
            guard force || Date().timeIntervalSince(lastReported) > 0.3 else { return }
            lastReported = Date()
            let progress = currentProgress
            model.chapterProgress = progress
            model.reportProgress(progress, location: TextLocation(progression: progress).encoded)
        }

        fileprivate func selectionChanged(_ text: String?) {
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed.count >= 3 {
                model.selection = ReaderSelection(text: trimmed, chapterIndex: 0, location: TextLocation(progression: currentProgress).encoded)
            } else if model.selection != nil {
                model.selection = nil
            }
        }

        func goToChapter(_ index: Int) {}

        func seek(to progress: Double) { scroll(to: progress) }

        func jump(to location: String?, chapterIndex: Int) {
            if let location = TextLocation.decode(location) { scroll(to: location.progression) }
        }

        func search(_ query: String, backwards: Bool) {
            guard let textView else { return }
            let fingerprint = document?.fingerprint ?? ""
            if query != searchQuery || fingerprint != searchFingerprint {
                searchQuery = query
                searchFingerprint = fingerprint
                searchRange = nil
                #if os(macOS)
                let string = textView.string as NSString
                #else
                let string = (textView.text ?? "") as NSString
                #endif
                searchMatches = Self.allMatches(of: query, in: string)
            }
            let matches = searchMatches
            guard !matches.isEmpty else {
                model.searchMatchSummary = "No matches"
                return
            }
            let currentIndex: Int
            if let searchRange, let existing = matches.firstIndex(of: searchRange) {
                currentIndex = backwards
                    ? (existing == 0 ? matches.count - 1 : existing - 1)
                    : (existing + 1) % matches.count
            } else {
                currentIndex = backwards ? matches.count - 1 : 0
            }
            let found = matches[currentIndex]
            searchRange = found
            model.searchMatchSummary = "\(currentIndex + 1) of \(matches.count)"
            #if os(macOS)
            textView.setSelectedRange(found)
            textView.scrollRangeToVisible(found)
            textView.showFindIndicator(for: found)
            #else
            textView.selectedRange = found
            textView.scrollRangeToVisible(found)
            #endif
        }

        private static func allMatches(of query: String, in string: NSString) -> [NSRange] {
            var results: [NSRange] = []
            var location = 0
            while location < string.length {
                let range = string.range(
                    of: query,
                    options: [.caseInsensitive],
                    range: NSRange(location: location, length: string.length - location)
                )
                guard range.location != NSNotFound else { break }
                results.append(range)
                location = range.location + max(range.length, 1)
            }
            return results
        }

        func clearSelection() {
            #if os(macOS)
            guard let textView else { return }
            let caret = textView.selectedRange().location
            textView.setSelectedRange(NSRange(location: caret, length: 0))
            #else
            guard let textView else { return }
            let caret = textView.selectedRange.location
            textView.selectedRange = NSRange(location: caret, length: 0)
            #endif
        }

        func refreshHighlights() {
            render(palette: lastPalette, fontSize: model.fontSize, lineHeight: model.lineHeight, typeface: model.typeface)
        }

        func captureLocation() {
            report(force: true)
        }

        private var displayedText: NSString {
            #if os(macOS)
            (textView?.string ?? "") as NSString
            #else
            (textView?.text ?? "") as NSString
            #endif
        }

        private var firstVisibleCharacter: Int {
            guard let textView else { return 0 }
            #if os(macOS)
            guard let scrollView else { return 0 }
            let point = NSPoint(x: textView.textContainerInset.width + 12, y: scrollView.contentView.bounds.minY + 12)
            return textView.characterIndexForInsertion(at: point)
            #else
            let point = CGPoint(x: textView.textContainerInset.left + 12, y: textView.contentOffset.y + textView.adjustedContentInset.top + 12)
            guard let position = textView.closestPosition(to: point) else { return 0 }
            return textView.offset(from: textView.beginningOfDocument, to: position)
            #endif
        }

        func readAloudPassages(after: String?) async -> [SpokenPassage] {
            let text = displayedText
            guard text.length > 0 else { return [] }
            var start: Int
            if let after, let range = Self.range(from: after) {
                start = NSMaxRange(range)
            } else {
                start = text.paragraphRange(for: NSRange(location: min(firstVisibleCharacter, text.length - 1), length: 0)).location
            }
            var passages: [SpokenPassage] = []
            while start < text.length && passages.count < 30 {
                let range = text.paragraphRange(for: NSRange(location: start, length: 0))
                let paragraph = text.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
                if !paragraph.isEmpty {
                    passages.append(SpokenPassage(id: "\(range.location):\(range.length)", text: paragraph))
                }
                start = NSMaxRange(range)
            }
            return passages
        }

        func revealPassage(_ id: String) {
            guard let textView, let range = Self.range(from: id), NSMaxRange(range) <= displayedText.length else { return }
            textView.scrollRangeToVisible(range)
        }

        func endReadingAloud() {}

        private static func range(from id: String) -> NSRange? {
            let parts = id.split(separator: ":").compactMap { Int($0) }
            return parts.count == 2 ? NSRange(location: parts[0], length: parts[1]) : nil
        }
    }
}

#if os(macOS)
extension TextReader.Coordinator: NSTextViewDelegate {
    func textViewDidChangeSelection(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        let range = textView.selectedRange()
        selectionChanged(range.length > 0 ? (textView.string as NSString).substring(with: range) : nil)
    }
}

final class ColumnTextScrollView: NSScrollView {
    let textView: NSTextView
    var columnWidth: Double = 620

    override init(frame: NSRect) {
        let textView = NSTextView(frame: .zero)
        self.textView = textView
        super.init(frame: frame)
        hasVerticalScroller = true
        autohidesScrollers = true
        drawsBackground = false
        automaticallyAdjustsContentInsets = false
        contentInsets = NSEdgeInsets(top: 12, left: 0, bottom: 112, right: 0)
        documentView = textView
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.usesFindBar = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func tile() {
        super.tile()
        let width = contentView.bounds.width
        let inset = max(28, (width - columnWidth) / 2)
        if textView.textContainerInset.width != inset {
            textView.textContainerInset = NSSize(width: inset, height: 48)
        }
    }
}
#else
extension TextReader.Coordinator: UITextViewDelegate {
    func textViewDidChangeSelection(_ textView: UITextView) {
        let range = textView.selectedRange
        selectionChanged(range.length > 0 ? (textView.text as NSString).substring(with: range) : nil)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        didScroll()
    }
}

final class ColumnTextView: UITextView {
    var columnWidth: Double = 620
    var onTapCenter: () -> Void = {}

    init() {
        super.init(frame: .zero, textContainer: nil)
        isEditable = false
        isSelectable = true
        backgroundColor = .clear
        textContainer.lineFragmentPadding = 0
        alwaysBounceVertical = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = max(20, (bounds.width - columnWidth) / 2)
        if textContainerInset.left != inset {
            textContainerInset = UIEdgeInsets(top: 40, left: inset, bottom: 120, right: inset)
        }
    }

    @objc private func handleTap() {
        if selectedRange.length == 0 { onTapCenter() }
    }
}
#endif

enum TextDocument: Sendable {
    case rtf(Data)
    case markdown(String)
    case plain(String)

    var fingerprint: String {
        switch self {
        case .rtf(let data): "rtf-\(data.count)"
        case .markdown(let text): "md-\(text.count)"
        case .plain(let text): "txt-\(text.count)"
        }
    }
}

enum TextDocumentLoader {
    struct LoadError: Error, Sendable {
        let message: String
    }

    nonisolated struct HighlightSpec: Sendable, Hashable {
        let id: UUID
        let text: String
        let color: HighlightColor
    }

    nonisolated struct UncheckedAttributedString: @unchecked Sendable {
        let value: NSAttributedString
    }

    @concurrent
    static func renderAttributedString(
        _ document: TextDocument,
        palette: ReaderPalette,
        fontSize: Double,
        lineHeight: Double,
        typeface: ReaderTypeface,
        highlights: [HighlightSpec]
    ) async -> UncheckedAttributedString {
        UncheckedAttributedString(value: attributedString(
            document,
            palette: palette,
            fontSize: fontSize,
            lineHeight: lineHeight,
            typeface: typeface,
            highlights: highlights
        ))
    }

    @concurrent
    static func load(_ url: URL) async -> Result<TextDocument, LoadError> {
        let maxBytes = 12_000_000
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return .failure(LoadError(message: "This book's file is missing from Chicken's library folder."))
        }
        guard size <= maxBytes else {
            return .failure(LoadError(message: "This text file is too large to display (\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))."))
        }
        guard let data = try? Data(contentsOf: url) else {
            return .failure(LoadError(message: "Chicken could not read this file."))
        }
        let ext = url.pathExtension.lowercased()
        if ext == "rtf" {
            return data.isEmpty ? .failure(LoadError(message: "This file is empty.")) : .success(.rtf(data))
        }
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        guard !text.isEmpty else { return .failure(LoadError(message: "This file is empty.")) }
        if ext == "md" || ext == "markdown" {
            return .success(.markdown(text))
        }
        return .success(.plain(text))
    }

    nonisolated static func attributedString(
        _ document: TextDocument,
        palette: ReaderPalette,
        fontSize: Double,
        lineHeight: Double,
        typeface: ReaderTypeface = .default,
        highlights: [HighlightSpec]
    ) -> NSAttributedString {
        let result: NSMutableAttributedString
        switch document {
        case .rtf(let data):
            result = renderRTF(data, palette: palette, fontSize: fontSize, lineHeight: lineHeight)
        case .markdown(let text):
            result = renderMarkdown(text, palette: palette, fontSize: fontSize, lineHeight: lineHeight, typeface: typeface)
        case .plain(let text):
            result = renderPlain(text, palette: palette, fontSize: fontSize, lineHeight: lineHeight, typeface: typeface)
        }
        applyHighlights(highlights, to: result)
        return result
    }

    private nonisolated static func renderRTF(
        _ data: Data,
        palette: ReaderPalette,
        fontSize: Double,
        lineHeight: Double
    ) -> NSMutableAttributedString {
        guard let parsed = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) else {
            return NSMutableAttributedString(string: String(decoding: data, as: UTF8.self))
        }
        let mutable = NSMutableAttributedString(attributedString: parsed)
        let fullRange = NSRange(location: 0, length: mutable.length)
        let textColor = PlatformColor.hex(palette.textHex)
        let scale = CGFloat(fontSize / 16.0)

        mutable.beginEditing()
        mutable.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            guard let font = value as? PlatformFont else { return }
            let scaledSize = max(11, (font.pointSize * scale).rounded())
            #if os(macOS)
            if let resized = PlatformFont(descriptor: font.fontDescriptor, size: scaledSize) {
                mutable.addAttribute(.font, value: resized, range: range)
            }
            #else
            mutable.addAttribute(.font, value: PlatformFont(descriptor: font.fontDescriptor, size: scaledSize), range: range)
            #endif
        }
        mutable.enumerateAttribute(.paragraphStyle, in: fullRange) { value, range, _ in
            let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            style.lineHeightMultiple = CGFloat(lineHeight)
            mutable.addAttribute(.paragraphStyle, value: style, range: range)
        }
        mutable.addAttribute(.foregroundColor, value: textColor, range: fullRange)
        mutable.removeAttribute(.backgroundColor, range: fullRange)
        mutable.endEditing()
        return mutable
    }

    private nonisolated static func renderMarkdown(
        _ content: String,
        palette: ReaderPalette,
        fontSize: Double,
        lineHeight: Double,
        typeface: ReaderTypeface
    ) -> NSMutableAttributedString {
        let size = CGFloat(fontSize)
        let bodyFont = typeface.platformFont(size: size)
        let monoFont = PlatformFont.monospacedSystemFont(ofSize: max(12, size * 0.88), weight: .regular)
        let textColor = PlatformColor.hex(palette.textHex)
        let mutedColor = PlatformColor.hex(palette.mutedHex)
        let ribbonColor = PlatformColor.hex(palette.ribbonHex)
        let codeBG = PlatformColor.hex(palette.surfaceAltHex)

        let bodyParagraph = NSMutableParagraphStyle()
        bodyParagraph.lineHeightMultiple = CGFloat(lineHeight)
        bodyParagraph.paragraphSpacing = (size * 0.85).rounded()
        bodyParagraph.hyphenationFactor = 0.5

        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        let output = NSMutableAttributedString()

        var index = 0
        var inCodeBlock = false
        var codeLines: [String] = []
        var paragraphBuffer: [String] = []

        func flushParagraph() {
            guard !paragraphBuffer.isEmpty else { return }
            let raw = paragraphBuffer.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            paragraphBuffer.removeAll()
            guard !raw.isEmpty else { return }
            appendInlineMarkdown(
                raw,
                baseFont: bodyFont,
                color: textColor,
                linkColor: ribbonColor,
                codeBG: codeBG,
                paragraphStyle: bodyParagraph,
                to: output
            )
            output.append(NSAttributedString(string: "\n", attributes: [.font: bodyFont, .paragraphStyle: bodyParagraph]))
        }

        func flushCodeBlock() {
            guard !codeLines.isEmpty else { return }
            let style = NSMutableParagraphStyle()
            style.lineHeightMultiple = 1.4
            style.headIndent = 14
            style.firstLineHeadIndent = 14
            style.paragraphSpacing = (size * 0.9).rounded()
            let joined = codeLines.joined(separator: "\n") + "\n"
            codeLines.removeAll()
            output.append(NSAttributedString(string: joined, attributes: [
                .font: monoFont,
                .foregroundColor: textColor,
                .backgroundColor: codeBG,
                .paragraphStyle: style,
            ]))
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushParagraph()
                if inCodeBlock {
                    flushCodeBlock()
                    inCodeBlock = false
                } else {
                    inCodeBlock = true
                }
                index += 1
                continue
            }

            if inCodeBlock {
                codeLines.append(line)
                index += 1
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if let heading = parseHeading(trimmed) {
                flushParagraph()
                let scale: CGFloat = heading.level == 1 ? 1.65 : (heading.level == 2 ? 1.35 : 1.15)
                let headingFont = PlatformFont.systemFont(ofSize: (size * scale).rounded(), weight: .semibold)
                let style = NSMutableParagraphStyle()
                style.lineHeightMultiple = 1.25
                style.paragraphSpacingBefore = output.length == 0 ? 0 : (size * 1.1).rounded()
                style.paragraphSpacing = (size * 0.5).rounded()
                appendInlineMarkdown(
                    heading.text,
                    baseFont: headingFont,
                    color: textColor,
                    linkColor: ribbonColor,
                    codeBG: codeBG,
                    paragraphStyle: style,
                    to: output
                )
                output.append(NSAttributedString(string: "\n", attributes: [.font: headingFont, .paragraphStyle: style]))
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                let quoteText = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                let quoteStyle = NSMutableParagraphStyle()
                quoteStyle.lineHeightMultiple = CGFloat(lineHeight)
                quoteStyle.firstLineHeadIndent = 18
                quoteStyle.headIndent = 18
                quoteStyle.paragraphSpacing = (size * 0.8).rounded()
                let quoteFont = italicFont(from: bodyFont)
                appendInlineMarkdown(
                    quoteText,
                    baseFont: quoteFont,
                    color: mutedColor,
                    linkColor: ribbonColor,
                    codeBG: codeBG,
                    paragraphStyle: quoteStyle,
                    to: output
                )
                output.append(NSAttributedString(string: "\n", attributes: [.font: quoteFont, .paragraphStyle: quoteStyle]))
                index += 1
                continue
            }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                flushParagraph()
                let itemText = String(trimmed.dropFirst(2))
                let listStyle = NSMutableParagraphStyle()
                listStyle.lineHeightMultiple = CGFloat(lineHeight)
                listStyle.firstLineHeadIndent = 12
                listStyle.headIndent = 24
                listStyle.paragraphSpacing = (size * 0.45).rounded()
                output.append(NSAttributedString(string: "•  ", attributes: [
                    .font: bodyFont,
                    .foregroundColor: ribbonColor,
                    .paragraphStyle: listStyle,
                ]))
                appendInlineMarkdown(
                    itemText,
                    baseFont: bodyFont,
                    color: textColor,
                    linkColor: ribbonColor,
                    codeBG: codeBG,
                    paragraphStyle: listStyle,
                    to: output
                )
                output.append(NSAttributedString(string: "\n", attributes: [.font: bodyFont, .paragraphStyle: listStyle]))
                index += 1
                continue
            }

            paragraphBuffer.append(trimmed)
            index += 1
        }

        flushParagraph()
        if inCodeBlock { flushCodeBlock() }
        return output
    }

    private nonisolated static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        var hashes = 0
        for ch in line {
            if ch == "#" { hashes += 1 } else { break }
        }
        guard (1...6).contains(hashes) else { return nil }
        let rest = line.dropFirst(hashes)
        guard rest.first == " " else { return nil }
        return (hashes, rest.trimmingCharacters(in: .whitespaces))
    }

    private nonisolated static func appendInlineMarkdown(
        _ raw: String,
        baseFont: PlatformFont,
        color: PlatformColor,
        linkColor: PlatformColor,
        codeBG: PlatformColor,
        paragraphStyle: NSParagraphStyle,
        to output: NSMutableAttributedString
    ) {
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle,
        ]
        guard let parsed = try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            output.append(NSAttributedString(string: raw, attributes: baseAttributes))
            return
        }
        let chunk = NSMutableAttributedString()
        for run in parsed.runs {
            let text = String(parsed[run.range].characters)
            var attrs = baseAttributes
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.code) {
                    attrs[.font] = PlatformFont.monospacedSystemFont(ofSize: max(12, baseFont.pointSize * 0.88), weight: .regular)
                    attrs[.backgroundColor] = codeBG
                } else if intent.contains(.stronglyEmphasized) && intent.contains(.emphasized) {
                    attrs[.font] = boldItalicFont(from: baseFont)
                } else if intent.contains(.stronglyEmphasized) {
                    attrs[.font] = boldFont(from: baseFont)
                } else if intent.contains(.emphasized) {
                    attrs[.font] = italicFont(from: baseFont)
                }
                if intent.contains(.strikethrough) {
                    attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }
            }
            if let link = run.link {
                attrs[.link] = link
                attrs[.foregroundColor] = linkColor
            }
            chunk.append(NSAttributedString(string: text, attributes: attrs))
        }
        output.append(chunk)
    }

    private nonisolated static func renderPlain(
        _ content: String,
        palette: ReaderPalette,
        fontSize: Double,
        lineHeight: Double,
        typeface: ReaderTypeface
    ) -> NSMutableAttributedString {
        let size = CGFloat(fontSize)
        let body = typeface.platformFont(size: size)
        let textColor = PlatformColor.hex(palette.textHex)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = CGFloat(lineHeight)
        paragraph.paragraphSpacing = (size * 0.95).rounded()
        paragraph.hyphenationFactor = 0.6

        let attributes: [NSAttributedString.Key: Any] = [
            .font: body,
            .foregroundColor: textColor,
            .paragraphStyle: paragraph,
        ]

        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        let separator = normalized.contains("\n\n") ? "\n\n" : "\n"
        let paragraphs = normalized
            .components(separatedBy: separator)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let result = NSMutableAttributedString()
        for (index, text) in paragraphs.enumerated() {
            result.append(NSAttributedString(string: text, attributes: attributes))
            if index < paragraphs.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: attributes))
            }
        }
        return result
    }

    private nonisolated static func applyHighlights(_ highlights: [HighlightSpec], to result: NSMutableAttributedString) {
        let string = result.string as NSString
        for highlight in highlights {
            let range = string.range(of: highlight.text, options: [.caseInsensitive])
            if range.location != NSNotFound {
                result.addAttribute(.backgroundColor, value: PlatformColor(highlight.color.fill), range: range)
            }
        }
    }

    private nonisolated static func boldFont(from font: PlatformFont) -> PlatformFont {
        #if os(macOS)
        let descriptor = font.fontDescriptor.withSymbolicTraits(.bold)
        return PlatformFont(descriptor: descriptor, size: font.pointSize) ?? PlatformFont.boldSystemFont(ofSize: font.pointSize)
        #else
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(.traitBold) else {
            return PlatformFont.boldSystemFont(ofSize: font.pointSize)
        }
        return PlatformFont(descriptor: descriptor, size: font.pointSize)
        #endif
    }

    private nonisolated static func italicFont(from font: PlatformFont) -> PlatformFont {
        #if os(macOS)
        let descriptor = font.fontDescriptor.withSymbolicTraits(.italic)
        return PlatformFont(descriptor: descriptor, size: font.pointSize) ?? font
        #else
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(.traitItalic) else { return font }
        return PlatformFont(descriptor: descriptor, size: font.pointSize)
        #endif
    }

    private nonisolated static func boldItalicFont(from font: PlatformFont) -> PlatformFont {
        #if os(macOS)
        let descriptor = font.fontDescriptor.withSymbolicTraits([.bold, .italic])
        return PlatformFont(descriptor: descriptor, size: font.pointSize) ?? boldFont(from: font)
        #else
        guard let descriptor = font.fontDescriptor.withSymbolicTraits([.traitBold, .traitItalic]) else {
            return boldFont(from: font)
        }
        return PlatformFont(descriptor: descriptor, size: font.pointSize)
        #endif
    }
}
