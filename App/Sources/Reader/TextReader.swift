import ChickenKit
import SwiftUI

/// Reader for plain text, Markdown, and RTF: a native text view with its own
/// scrolling, a centered reading column, a drop cap, and highlights.
struct TextReader: PlatformViewRepresentable {
    let model: ReaderModel
    let fileURL: URL
    let palette: ReaderPalette
    let fontSize: Double
    let lineHeight: Double
    let columnWidth: Double
    let typeface: ReaderTypeface
    let onTapCenter: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    #if os(macOS)
    func makeView(context: Context) -> ColumnTextScrollView {
        let scrollView = ColumnTextScrollView()
        context.coordinator.attach(scrollView)
        context.coordinator.load(fileURL)
        return scrollView
    }

    func updateView(_ view: ColumnTextScrollView, context: Context) {
        view.columnWidth = columnWidth
        view.needsLayout = true
        context.coordinator.render(palette: palette, fontSize: fontSize, lineHeight: lineHeight)
    }
    #else
    func makeView(context: Context) -> ColumnTextView {
        let textView = ColumnTextView()
        context.coordinator.attach(textView, onTapCenter: onTapCenter)
        context.coordinator.load(fileURL)
        return textView
    }

    func updateView(_ view: ColumnTextView, context: Context) {
        view.columnWidth = columnWidth
        view.setNeedsLayout()
        context.coordinator.onTapCenter = onTapCenter
        context.coordinator.render(palette: palette, fontSize: fontSize, lineHeight: lineHeight)
    }
    #endif

    #if os(macOS)
    static func dismantleView(_ view: ColumnTextScrollView, coordinator: Coordinator) {
        coordinator.captureLocation()
    }
    #else
    static func dismantleView(_ view: ColumnTextView, coordinator: Coordinator) {
        coordinator.captureLocation()
    }
    #endif

    @MainActor
    final class Coordinator: NSObject, ReaderEngine {
        let model: ReaderModel
        var onTapCenter: () -> Void = {}
        private var content = ""
        private var renderKey = ""
        private var restored = false
        private var lastReported = Date.distantPast
        private var searchRange: NSRange?
        #if os(macOS)
        private weak var scrollView: ColumnTextScrollView?
        private var textView: NSTextView? { scrollView?.documentView as? NSTextView }
        #else
        private weak var textView: ColumnTextView?
        #endif

        init(model: ReaderModel) {
            self.model = model
            super.init()
            model.engine = self
            model.chapters = [ReaderChapter(id: 0, title: model.book.displayTitle)]
        }

        #if os(macOS)
        func attach(_ scrollView: ColumnTextScrollView) {
            self.scrollView = scrollView
            scrollView.textView.delegate = self
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(didScroll), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        }
        #else
        func attach(_ textView: ColumnTextView, onTapCenter: @escaping () -> Void) {
            self.textView = textView
            self.onTapCenter = onTapCenter
            textView.delegate = self
            textView.onTapCenter = { [weak self] in self?.onTapCenter() }
        }
        #endif

        func load(_ url: URL) {
            Task { [weak self] in
                let result = await Task.detached(priority: .userInitiated) { TextDocumentLoader.load(url) }.value
                guard let self else { return }
                switch result {
                case .success(let text):
                    self.content = text
                    self.model.error = nil
                    self.renderKey = ""
                    self.render(palette: self.lastPalette, fontSize: self.model.fontSize, lineHeight: self.model.lineHeight)
                case .failure(let error):
                    self.model.error = error.message
                }
            }
        }

        private var lastPalette = ReadingTheme.paper.palette

        func render(palette: ReaderPalette, fontSize: Double, lineHeight: Double) {
            lastPalette = palette
            guard !content.isEmpty, let textView else { return }
            let highlights = (model.book.highlights ?? []).map { "\($0.id)\($0.colorRaw)" }.sorted().joined()
            let typeface = model.typeface
            let key = "\(palette.backgroundHex)|\(fontSize)|\(lineHeight)|\(typeface.rawValue)|\(content.count)|\(highlights)"
            guard key != renderKey else { return }
            let anchor = currentProgress
            renderKey = key
            let attributed = TextDocumentLoader.attributedString(
                content,
                palette: palette,
                fontSize: fontSize,
                lineHeight: lineHeight,
                typeface: typeface,
                highlights: model.book.highlights ?? []
            )
            #if os(macOS)
            textView.textStorage?.setAttributedString(attributed)
            #else
            textView.attributedText = attributed
            #endif
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if !self.restored {
                    self.restored = true
                    self.scroll(to: TextLocation.decode(self.model.book.lastLocation)?.progression ?? self.model.book.progress)
                } else {
                    self.scroll(to: anchor)
                }
            }
        }

        // MARK: Scrolling

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

        @objc fileprivate func didScroll() {
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

        // MARK: ReaderEngine

        func goToChapter(_ index: Int) {}

        func seek(to progress: Double) { scroll(to: progress) }

        func jump(to location: String?, chapterIndex: Int) {
            if let location = TextLocation.decode(location) { scroll(to: location.progression) }
        }

        func turnPage(_ direction: Int) {
            #if os(macOS)
            direction > 0 ? scrollView?.pageDown(nil) : scrollView?.pageUp(nil)
            #else
            guard let textView else { return }
            let target = textView.contentOffset.y + textView.bounds.height * 0.88 * CGFloat(direction)
            let maxY = max(0, textView.contentSize.height - textView.bounds.height)
            textView.setContentOffset(CGPoint(x: 0, y: min(maxY, max(0, target))), animated: true)
            #endif
        }

        func search(_ query: String, backwards: Bool) {
            guard let textView else { return }
            #if os(macOS)
            let string = textView.string as NSString
            #else
            let string = (textView.text ?? "") as NSString
            #endif
            let start: Int
            if let searchRange {
                start = backwards ? searchRange.location : searchRange.location + searchRange.length
            } else {
                start = 0
            }
            let range = backwards
                ? NSRange(location: 0, length: start)
                : NSRange(location: start, length: string.length - start)
            var found = string.range(of: query, options: backwards ? [.caseInsensitive, .backwards] : [.caseInsensitive], range: range)
            if found.location == NSNotFound {
                found = string.range(of: query, options: backwards ? [.caseInsensitive, .backwards] : [.caseInsensitive])
            }
            guard found.location != NSNotFound else { return }
            searchRange = found
            #if os(macOS)
            textView.setSelectedRange(found)
            textView.scrollRangeToVisible(found)
            textView.showFindIndicator(for: found)
            #else
            textView.selectedRange = found
            textView.scrollRangeToVisible(found)
            #endif
        }

        func clearSelection() {
            #if os(macOS)
            textView?.setSelectedRange(NSRange(location: 0, length: 0))
            #else
            textView?.selectedRange = NSRange(location: 0, length: 0)
            #endif
        }

        func refreshHighlights() {
            render(palette: lastPalette, fontSize: model.fontSize, lineHeight: model.lineHeight)
        }

        func captureLocation() {
            report(force: true)
        }

        // MARK: Reading aloud

        private var displayedText: NSString {
            #if os(macOS)
            (textView?.string ?? "") as NSString
            #else
            (textView?.text ?? "") as NSString
            #endif
        }

        /// The first character showing at the top of the view.
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

        /// Paragraphs, from the one on screen. A passage's id is its range.
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

/// Scroll view whose text column stays centered at the chosen width.
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
            textView.textContainerInset = NSSize(width: inset, height: 56)
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

/// Text view whose text column stays centered at the chosen width.
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
            textContainerInset = UIEdgeInsets(top: 40, left: inset, bottom: 96, right: inset)
        }
    }

    @objc private func handleTap() {
        if selectedRange.length == 0 { onTapCenter() }
    }
}
#endif

/// Loading and typesetting for text documents.
enum TextDocumentLoader {
    struct LoadError: Error {
        let message: String
    }

    nonisolated static func load(_ url: URL) -> Result<String, LoadError> {
        let maxBytes = 12_000_000
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return .failure(LoadError(message: "This book's file is missing from Chicken's library folder."))
        }
        guard size <= maxBytes else {
            return .failure(LoadError(message: "This text file is too large to display (\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))."))
        }
        if url.pathExtension.lowercased() == "rtf",
           let attributed = try? NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
            return .success(attributed.string)
        }
        guard let data = try? Data(contentsOf: url) else {
            return .failure(LoadError(message: "Chicken could not read this file."))
        }
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        return text.isEmpty ? .failure(LoadError(message: "This file is empty.")) : .success(text)
    }

    static func attributedString(
        _ content: String,
        palette: ReaderPalette,
        fontSize: Double,
        lineHeight: Double,
        typeface: ReaderTypeface = .default,
        highlights: [Highlight]
    ) -> NSAttributedString {
        let size = CGFloat(fontSize)
        let body = typeface.platformFont(size: size)
        let dropCapSize = (size * 3.2).rounded()
        let dropCap = PlatformFont(name: "Superclarendon-Regular", size: dropCapSize) ?? serifFont(size: dropCapSize, weight: .medium)
        let textColor = PlatformColor.hex(palette.textHex)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = CGFloat(lineHeight)
        paragraph.paragraphSpacing = (size * 1.1).rounded()
        paragraph.hyphenationFactor = 0.6

        let attributes: [NSAttributedString.Key: Any] = [
            .font: body,
            .foregroundColor: textColor,
            .paragraphStyle: paragraph,
        ]

        let paragraphs = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let result = NSMutableAttributedString()
        for (index, text) in paragraphs.enumerated() {
            if index == 0, let first = text.first {
                result.append(NSAttributedString(string: String(first), attributes: attributes.merging([
                    .font: dropCap,
                    .baselineOffset: -(dropCapSize - size * 1.1).rounded(),
                ]) { _, new in new }))
                result.append(NSAttributedString(string: String(text.dropFirst()), attributes: attributes))
            } else {
                result.append(NSAttributedString(string: text, attributes: attributes))
            }
            if index < paragraphs.count - 1 {
                result.append(NSAttributedString(string: "\n\n", attributes: attributes))
            }
        }

        let string = result.string as NSString
        for highlight in highlights {
            let range = string.range(of: highlight.text)
            if range.location != NSNotFound {
                result.addAttribute(.backgroundColor, value: PlatformColor(highlight.color.fill), range: range)
            }
        }
        return result
    }

    private static func serifFont(size: CGFloat, weight: PlatformFont.Weight = .regular) -> PlatformFont {
        let system = PlatformFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = system.fontDescriptor.withDesign(.serif) else { return system }
        #if os(macOS)
        return PlatformFont(descriptor: descriptor, size: size) ?? system
        #else
        return PlatformFont(descriptor: descriptor, size: size)
        #endif
    }
}
