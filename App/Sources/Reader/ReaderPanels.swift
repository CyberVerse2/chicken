import ChickenKit
import SwiftUI

// MARK: - Contents

struct ChaptersList: View {
    @Environment(\.palette) private var palette
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
                withAnimation(.easeInOut(duration: 0.18)) { proxy.scrollTo(index, anchor: .center) }
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
        Button(action: action) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(isActive ? palette.ribbon : .clear)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(chapter.title)
                        .font(.chickenSerif(14.5, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? palette.text : palette.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let subtitle = chapter.subtitle {
                        Text(subtitle)
                            .font(.chickenUI(10))
                            .foregroundStyle(palette.faint)
                    }
                }
                .padding(.leading, 18 + CGFloat(min(chapter.level, 3)) * 14)
                .padding(.trailing, 16)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - Highlights and bookmarks

struct AnnotationsList: View {
    enum Tab: String, CaseIterable, Identifiable {
        case highlights = "Highlights"
        case bookmarks = "Bookmarks"
        var id: String { rawValue }
    }

    @Environment(\.palette) private var palette
    let model: ReaderModel
    @State private var tab: Tab = .highlights

    private var highlights: [Highlight] { model.book.sortedHighlights }
    private var bookmarks: [Bookmark] { model.book.sortedBookmarks }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Show", selection: $tab) {
                Text("Highlights · \(highlights.count)").tag(Tab.highlights)
                Text("Bookmarks · \(bookmarks.count)").tag(Tab.bookmarks)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(16)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    switch tab {
                    case .highlights:
                        if highlights.isEmpty {
                            hint(icon: "highlighter", title: "No highlights yet", text: "Select a passage to highlight it.")
                        }
                        ForEach(highlights) { highlight in
                            HighlightCard(model: model, highlight: highlight)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    case .bookmarks:
                        if bookmarks.isEmpty {
                            hint(icon: "bookmark", title: "No bookmarks yet", text: "Bookmark a page to come back to it.")
                        }
                        ForEach(bookmarks) { bookmark in
                            BookmarkCard(model: model, bookmark: bookmark)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .animation(.smooth(duration: 0.25), value: highlights.map(\.id))
                .animation(.smooth(duration: 0.25), value: bookmarks.map(\.id))
            }
        }
        .background(palette.background)
    }

    private func hint(icon: String, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(palette.muted)
            Text(title)
                .font(.chickenDisplay(17))
                .foregroundStyle(palette.text)
            Text(text)
                .font(.chickenSerif(14, italic: true))
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.surface))
    }
}

private struct HighlightCard: View {
    @Environment(\.palette) private var palette
    let model: ReaderModel
    let highlight: Highlight
    @State private var editingNote = false
    @State private var draft = ""
    @FocusState private var noteFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { model.jump(toHighlight: highlight) } label: {
                Text(marked)
                    .font(.chickenSerif(15.5))
                    .foregroundStyle(palette.text)
                    .lineSpacing(5)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if editingNote {
                TextField("Add a note", text: $draft, axis: .vertical)
                    .font(.chickenSerif(14, italic: true))
                    .textFieldStyle(.plain)
                    .focused($noteFocused)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.surfaceAlt))
                    .onSubmit(saveNote)
                HStack {
                    Spacer()
                    Button("Cancel") { editingNote = false }
                        .buttonStyle(.plain)
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
                    Picker("Color", selection: colorBinding) {
                        ForEach(HighlightColor.allCases) { Label($0.label, systemImage: "circle.fill").tint($0.bar).tag($0) }
                    }
                    Button("Copy", systemImage: "doc.on.doc") { Clipboard.copy(highlight.text) }
                    Divider()
                    Button("Remove Highlight", systemImage: "trash", role: .destructive) { model.removeHighlight(highlight) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.muted)
                        .frame(width: 28, height: 22)
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

    private var marked: AttributedString {
        var text = AttributedString(highlight.text)
        text.backgroundColor = highlight.color.fill
        return text
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
        draft = highlight.note
        withAnimation(.smooth) { editingNote = true }
        noteFocused = true
    }

    private func saveNote() {
        model.library.updateNote(draft.trimmingCharacters(in: .whitespacesAndNewlines), on: highlight)
        withAnimation(.smooth) { editingNote = false }
    }
}

private struct BookmarkCard: View {
    @Environment(\.palette) private var palette
    let model: ReaderModel
    let bookmark: Bookmark

    var body: some View {
        HStack(spacing: 14) {
            Button { model.jump(toBookmark: bookmark) } label: {
                HStack(spacing: 14) {
                    Ribbon()
                        .frame(width: 12, height: 30)
                        .padding(.horizontal, 6)
                        .accessibilityHidden(true)
                    Text(bookmark.title)
                        .font(.chickenSerif(15, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button("Remove bookmark", systemImage: "xmark") { model.library.removeBookmark(bookmark) }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(palette.faint)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(palette.surface)
                .stroke(palette.border, lineWidth: 0.5)
        )
    }
}
