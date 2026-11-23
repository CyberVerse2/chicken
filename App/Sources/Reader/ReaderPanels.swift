import ChickenKit
import SwiftUI

struct ChaptersList: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: ReaderModel
    var onSelect: () -> Void = {}

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if model.chapters.isEmpty {
                    Text(model.error == nil ? "Loading contents…" : "No contents available.")
                        .font(.chickenUI(12))
                        .foregroundStyle(palette.faint)
                        .listRowBackground(Color.clear)
                }
                ForEach(model.chapters) { chapter in
                    ChapterRow(chapter: chapter, isActive: chapter.id == model.chapterIndex) {
                        model.selectChapter(chapter.id)
                        onSelect()
                    }
                    .id(chapter.id)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .onAppear { proxy.scrollTo(model.chapterIndex, anchor: .center) }
            .onChange(of: model.chapters.count) { proxy.scrollTo(model.chapterIndex, anchor: .center) }
            .onChange(of: model.chapterIndex) { _, index in
                withAnimation(reduceMotion ? nil : ChickenMotion.micro) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
    }
}

private struct ChapterRow: View {
    @Environment(\.palette) private var palette
    let chapter: ReaderChapter
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(isActive ? palette.ribbon : .clear)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(chapter.title)
                        .font(.chickenUI(14, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? palette.text : palette.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let subtitle = chapter.subtitle {
                        Text(subtitle)
                            .font(.chickenMono(10.5))
                            .foregroundStyle(palette.faint)
                    }
                }
                .padding(.leading, 16 + CGFloat(min(chapter.level, 3)) * 14)
                .padding(.trailing, 16)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(TactilePressStyle(scale: 0.99))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

struct AnnotationsList: View {
    enum Tab: String, CaseIterable, Identifiable {
        case highlights = "Highlights"
        case bookmarks = "Bookmarks"
        var id: String { rawValue }
    }

    enum Scope: String, CaseIterable, Identifiable {
        case all = "All"
        case thisChapter = "This Chapter"
        var id: String { rawValue }
    }

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: ReaderModel
    var onShareQuote: (Highlight) -> Void = { _ in }
    @State private var tab: Tab = .highlights
    @State private var scope: Scope = .all
    @Namespace private var scopeNamespace

    private var allHighlights: [Highlight] { model.book.sortedHighlights }
    private var highlights: [Highlight] {
        switch scope {
        case .all: allHighlights
        case .thisChapter: allHighlights.filter { $0.chapterIndex == model.chapterIndex }
        }
    }
    private var bookmarks: [Bookmark] { model.book.sortedBookmarks }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Picker("Show", selection: $tab) {
                    Text("Highlights · \(allHighlights.count)").tag(Tab.highlights)
                    Text("Bookmarks · \(bookmarks.count)").tag(Tab.bookmarks)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if tab == .highlights && model.chapters.count > 1 && !allHighlights.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Scope.allCases) { option in
                            let selected = scope == option
                            Button {
                                Haptics.selection()
                                withAnimation(reduceMotion ? nil : ChickenMotion.snappy) { scope = option }
                            } label: {
                                Text(option == .thisChapter ? "This chapter" : "Whole book")
                                    .font(.chickenUI(12, weight: selected ? .semibold : .regular))
                                    .foregroundStyle(selected ? palette.text : palette.muted)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 5)
                                    .background {
                                        if selected {
                                            Capsule()
                                                .fill(palette.surface)
                                                .stroke(palette.borderStrong, lineWidth: 0.5)
                                                .matchedGeometryEffect(id: "annotationScope", in: scopeNamespace)
                                        }
                                    }
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(TactilePressStyle(scale: 0.95))
                        }
                        Spacer()
                    }
                }
            }
            .padding(16)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    switch tab {
                    case .highlights:
                        if highlights.isEmpty {
                            hint(
                                icon: "highlighter",
                                title: scope == .thisChapter ? "No notes in this chapter" : "No highlights yet",
                                text: scope == .thisChapter
                                    ? "Margin notes for \(model.chapterTitle) will appear here as you mark passages."
                                    : "Select a passage to highlight it."
                            )
                        }
                        ForEach(highlights) { highlight in
                            HighlightCard(model: model, highlight: highlight, onShareQuote: { onShareQuote(highlight) })
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    case .bookmarks:
                        if bookmarks.isEmpty {
                            hint(icon: "bookmark", title: "No bookmarks yet", text: "Pull down from the top-right corner or tap Bookmark to mark your place.")
                        }
                        ForEach(bookmarks) { bookmark in
                            BookmarkCard(model: model, bookmark: bookmark)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .animation(reduceMotion ? nil : ChickenMotion.standard, value: highlights.map(\.id))
                .animation(reduceMotion ? nil : ChickenMotion.standard, value: bookmarks.map(\.id))
            }
        }
        .background(palette.background)
    }

    private func hint(icon: String, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(palette.muted)
            Text(title)
                .font(.chickenDisplay(16))
                .foregroundStyle(palette.text)
            Text(text)
                .font(.chickenUI(13.5))
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(palette.surface)
                .stroke(palette.border, lineWidth: 0.5)
        )
    }
}

private struct HighlightCard: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: ReaderModel
    let highlight: Highlight
    let onShareQuote: () -> Void
    @State private var draft: String?
    @FocusState private var noteFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { model.jump(toHighlight: highlight) } label: {
                HStack(alignment: .top, spacing: 10) {
                    Capsule()
                        .fill(highlight.color.bar)
                        .frame(width: 3)
                    Text(highlight.text)
                        .font(.chickenSerif(15.5))
                        .foregroundStyle(palette.text)
                        .lineSpacing(5)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(TactilePressStyle(scale: 0.99))

            if draft != nil {
                TextField("Add a note", text: draftBinding, axis: .vertical)
                    .font(.chickenSerif(14, italic: true))
                    .textFieldStyle(.plain)
                    .focused($noteFocused)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.surfaceAlt))
                    .onSubmit(saveNote)
                HStack {
                    Spacer()
                    Button("Cancel") {
                        withAnimation(reduceMotion ? nil : ChickenMotion.micro) { draft = nil }
                    }
                    .buttonStyle(TactilePressStyle(scale: 0.95))
                    .foregroundStyle(palette.muted)
                    Button("Save", action: saveNote)
                        .buttonStyle(.glass)
                        .foregroundStyle(palette.text)
                }
                .font(.chickenUI(13, weight: .medium))
            } else if !highlight.note.isEmpty {
                Text(highlight.note)
                    .font(.chickenSerif(14, italic: true))
                    .foregroundStyle(palette.muted)
                    .onTapGesture(perform: beginEditing)
            }

            HStack {
                Text("\(chapterTitle) · \(highlight.createdAt.shortRelativeDescription)")
                    .font(.chickenUI(11))
                    .foregroundStyle(palette.faint)
                    .lineLimit(1)
                Spacer()
                Menu {
                    Button(highlight.note.isEmpty ? "Add Note" : "Edit Note", systemImage: "square.and.pencil", action: beginEditing)
                    Button("Share Quote Card…", systemImage: "square.and.arrow.up", action: onShareQuote)
                    Picker("Color", selection: colorBinding) {
                        ForEach(HighlightColor.allCases) { Label($0.label, systemImage: "circle.fill").tint($0.bar).tag($0) }
                    }
                    Button("Copy", systemImage: "doc.on.doc") { Clipboard.copy(highlight.text) }
                    Divider()
                    Button("Remove Highlight", systemImage: "trash", role: .destructive) {
                        Haptics.impact(.light)
                        model.removeHighlight(highlight)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.muted)
                        .frame(width: 44, height: 32)
                        .contentShape(Rectangle())
                }
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .accessibilityLabel("Highlight actions")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(palette.surface)
                .stroke(palette.border, lineWidth: 0.5)
        )
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") { Clipboard.copy(highlight.text) }
            Button("Remove Highlight", systemImage: "trash", role: .destructive) { model.removeHighlight(highlight) }
        }
    }

    private var draftBinding: Binding<String> {
        Binding(get: { draft ?? "" }, set: { draft = $0 })
    }

    private var chapterTitle: String {
        model.chapters.indices.contains(highlight.chapterIndex) ? model.chapters[highlight.chapterIndex].title : "Chapter \(highlight.chapterIndex + 1)"
    }

    private var colorBinding: Binding<HighlightColor> {
        Binding(get: { highlight.color }, set: { color in
            highlight.color = color
            model.library.save()
            model.engine?.refreshHighlights()
        })
    }

    private func beginEditing() {
        withAnimation(reduceMotion ? nil : ChickenMotion.micro) { draft = highlight.note }
        noteFocused = true
    }

    private func saveNote() {
        let value = (draft ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        model.library.updateNote(value, on: highlight)
        withAnimation(reduceMotion ? nil : ChickenMotion.micro) { draft = nil }
    }
}

private struct BookmarkCard: View {
    @Environment(\.palette) private var palette
    let model: ReaderModel
    let bookmark: Bookmark

    var body: some View {
        HStack(spacing: 12) {
            Button { model.jump(toBookmark: bookmark) } label: {
                HStack(spacing: 12) {
                    Ribbon()
                        .frame(width: 11, height: 28)
                        .padding(.horizontal, 4)
                        .accessibilityHidden(true)
                    Text(bookmark.title)
                        .font(.chickenUI(14.5, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(TactilePressStyle(scale: 0.99))
            Button {
                Haptics.impact(.light)
                model.library.removeBookmark(bookmark)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.faint)
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .buttonStyle(TactilePressStyle(scale: 0.92))
            .accessibilityLabel("Remove bookmark")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(palette.surface)
                .stroke(palette.border, lineWidth: 0.5)
        )
    }
}
