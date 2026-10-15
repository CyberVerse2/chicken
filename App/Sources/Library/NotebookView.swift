import ChickenKit
import SwiftData
import SwiftUI

/// Every passage you've marked, gathered by book and shown the way you
/// marked it: highlighter across the words, your note in the margin.
struct NotebookView: View {
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \Highlight.createdAt, order: .reverse) private var highlights: [Highlight]
    @State private var color: HighlightColor?

    private var gutter: CGFloat { sizeClass == .compact ? 20 : 44 }

    private var filtered: [Highlight] {
        guard let color else { return highlights }
        return highlights.filter { $0.color == color }
    }

    /// Books ordered by their most recent highlight.
    private var groups: [(book: Book, highlights: [Highlight])] {
        var order: [UUID] = []
        var byBook: [UUID: (Book, [Highlight])] = [:]
        for highlight in filtered {
            guard let book = highlight.book else { continue }
            if byBook[book.id] == nil {
                order.append(book.id)
                byBook[book.id] = (book, [])
            }
            byBook[book.id]?.1.append(highlight)
        }
        return order.compactMap { byBook[$0] }.map { (book: $0.0, highlights: $0.1) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "Notebook")
                .padding(.horizontal, gutter)
                .padding(.bottom, 28)

                if highlights.isEmpty {
                    emptyState.padding(.horizontal, gutter)
                } else {
                    colorFilter.padding(.bottom, 12)
                    ForEach(groups, id: \.book.id) { group in
                        NotebookBookSection(book: group.book, highlights: group.highlights)
                            .padding(.horizontal, gutter)
                            .padding(.top, 30)
                    }
                }
            }
            .padding(.top, sizeClass == .compact ? 8 : 28)
            .padding(.bottom, 80)
            .frame(maxWidth: 820, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.hard, for: .top)
        .background(palette.background.ignoresSafeArea())
        .pageTitle("Notebook")
        .toolbar { LibraryToolbar() }
    }

    private var colorFilter: some View {
        ScrollView(.horizontal) {
            HStack(spacing: sizeClass == .compact ? 20 : 26) {
                colorTab(nil, label: "All", count: highlights.count)
                ForEach(HighlightColor.allCases) { option in
                    let count = highlights.filter { $0.color == option }.count
                    if count > 0 { colorTab(option, label: option.label, count: count) }
                }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, gutter, for: .scrollContent)
        .scrollClipDisabled()
        .background(alignment: .bottom) {
            Rectangle().fill(palette.border).frame(height: 0.5)
        }
    }

    private func colorTab(_ option: HighlightColor?, label: String, count: Int) -> some View {
        let selected = color == option
        return Button {
            withAnimation(.smooth(duration: 0.3)) { color = option }
        } label: {
            HStack(alignment: .center, spacing: 6) {
                if let option {
                    Capsule().fill(option.bar).frame(width: 12, height: 6)
                }
                Text(label)
                    .font(.chickenUI(14, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? palette.text : palette.muted)
                Text("\(count)")
                    .font(.chickenMono(11, weight: .medium))
                    .foregroundStyle(selected ? palette.ribbon : palette.faint)
            }
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) {
                if selected {
                    Capsule().fill(palette.ribbon).frame(height: 2).offset(y: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(Self.sampleHighlight(palette: palette))
                .font(.chickenSerif(22))
                .foregroundStyle(palette.text)
                .lineSpacing(6)
            Text("Select a passage while reading to keep it here.")
                .font(.chickenSerif(15, italic: true))
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12)
    }

    private static func sampleHighlight(palette: ReaderPalette) -> AttributedString {
        var text = AttributedString("Select a passage you love, ")
        var marked = AttributedString("and keep it.")
        marked.backgroundColor = HighlightColor.amber.fill
        text.append(marked)
        return text
    }
}

private struct NotebookBookSection: View {
    @Environment(\.palette) private var palette
    @Environment(\.openBook) private var openBook
    let book: Book
    let highlights: [Highlight]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Button { openBook(book.id) } label: {
                HStack(alignment: .center, spacing: 14) {
                    BookCover(book: book, style: .mini)
                        .frame(width: 34, height: 51)
                        .shadow(color: palette.shadow, radius: 2, x: 1, y: 1)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(book.title)
                            .font(.chickenDisplay(19))
                            .foregroundStyle(palette.text)
                            .lineLimit(2)
                        Text(book.displayAuthor)
                            .font(.chickenSerif(14, italic: true))
                            .foregroundStyle(palette.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.faint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 26) {
                ForEach(highlights) { highlight in
                    NotebookHighlightRow(book: book, highlight: highlight)
                }
            }
            .padding(.leading, 48)

            Rectangle().fill(palette.border).frame(height: 0.5).padding(.top, 6)
        }
    }
}

private struct NotebookHighlightRow: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette
    @Environment(\.openBook) private var openBook
    let book: Book
    let highlight: Highlight

    var body: some View {
        Button(action: openAtHighlight) {
            VStack(alignment: .leading, spacing: 10) {
                Text(marked)
                    .font(.chickenSerif(18))
                    .foregroundStyle(palette.text)
                    .lineSpacing(7)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if !highlight.note.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Rectangle().fill(highlight.color.bar).frame(width: 10, height: 1)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 5 }
                        Text(highlight.note)
                            .font(.chickenSerif(15, italic: true))
                            .foregroundStyle(palette.muted)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open at This Passage", systemImage: "book") { openAtHighlight() }
            Button("Copy", systemImage: "doc.on.doc") { Clipboard.copy(highlight.text) }
            Divider()
            Button("Remove Highlight", systemImage: "trash", role: .destructive) { library.removeHighlight(highlight) }
        }
    }

    /// The passage with the highlighter laid across it, as it is on the page.
    private var marked: AttributedString {
        var text = AttributedString(highlight.text)
        text.backgroundColor = highlight.color.fill
        return text
    }

    /// Positions the book at the passage, then opens it.
    private func openAtHighlight() {
        if let location = highlight.location { book.lastLocation = location }
        library.save()
        openBook(book.id)
    }
}
