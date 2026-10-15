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
                    .fill(isActive ? palette.text : .clear)
                    .frame(width: 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(chapter.level > 0 ? "Section \(chapter.id + 1)" : "Chapter \(chapter.id + 1)")
                        .font(.chickenUI(10, weight: .medium))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(palette.faint)
                    Text(chapter.title)
                        .font(.chickenSerif(14, weight: isActive ? .medium : .regular))
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
    @Environment(\.palette) private var palette
    let model: ReaderModel

    private var highlights: [Highlight] { model.book.sortedHighlights }
    private var bookmarks: [Bookmark] { model.book.sortedBookmarks }

    var body: some View {
        List {
            if highlights.isEmpty && bookmarks.isEmpty {
                Text("Select text to highlight it, or bookmark a page to come back to it.")
                    .font(.chickenUI(13))
                    .foregroundStyle(palette.faint)
                    .listRowBackground(Color.clear)
            }

            if !bookmarks.isEmpty {
                Section("Bookmarks") {
                    ForEach(bookmarks) { bookmark in
                        Button { model.jump(toBookmark: bookmark) } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "bookmark.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(palette.muted)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(bookmark.title)
                                        .font(.chickenSerif(13, weight: .medium))
                                        .foregroundStyle(palette.text)
                                        .lineLimit(2)
                                    Text("Ch. \(bookmark.chapterIndex + 1) · \(bookmark.createdAt.shortRelativeDescription)")
                                        .font(.chickenUI(10))
                                        .foregroundStyle(palette.faint)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Remove Bookmark", systemImage: "trash", role: .destructive) { model.library.removeBookmark(bookmark) }
                        }
                        .swipeActions {
                            Button("Remove", role: .destructive) { model.library.removeBookmark(bookmark) }
                        }
                    }
                }
            }

            if !highlights.isEmpty {
                Section("Highlights · \(highlights.count)") {
                    ForEach(highlights) { highlight in
                        HighlightRow(model: model, highlight: highlight)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .animation(.smooth(duration: 0.25), value: highlights.map(\.id))
        .animation(.smooth(duration: 0.25), value: bookmarks.map(\.id))
    }
}

private struct HighlightRow: View {
    @Environment(\.palette) private var palette
    let model: ReaderModel
    let highlight: Highlight
    @State private var editingNote = false
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { model.jump(toHighlight: highlight) } label: {
                HStack(alignment: .top, spacing: 11) {
                    RoundedRectangle(cornerRadius: 1).fill(highlight.color.bar).frame(width: 3)
                    Text(highlight.text)
                        .font(.chickenSerif(13))
                        .foregroundStyle(palette.text)
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)

            if editingNote {
                TextField("Add a note", text: $draft, axis: .vertical)
                    .font(.chickenSerif(12, italic: true))
                    .textFieldStyle(.plain)
                    .padding(.leading, 14)
                    .onSubmit(saveNote)
                HStack {
                    Spacer()
                    Button("Cancel") { editingNote = false }
                    Button("Save", action: saveNote).fontWeight(.semibold)
                }
                .font(.chickenUI(12))
                .buttonStyle(.plain)
                .foregroundStyle(palette.muted)
            } else if !highlight.note.isEmpty {
                Text(highlight.note)
                    .font(.chickenSerif(12, italic: true))
                    .foregroundStyle(palette.muted)
                    .padding(.leading, 14)
            }

            Text("Ch. \(highlight.chapterIndex + 1) · \(highlight.createdAt.shortRelativeDescription)")
                .font(.chickenUI(10))
                .foregroundStyle(palette.faint)
                .padding(.leading, 14)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button(highlight.note.isEmpty ? "Add Note" : "Edit Note", systemImage: "note.text") { beginEditing() }
            Menu("Color") {
                ForEach(HighlightColor.allCases) { color in
                    Button(color.label) {
                        highlight.color = color
                        model.library.save()
                        model.engine?.refreshHighlights()
                    }
                }
            }
            Button("Copy", systemImage: "doc.on.doc") { Clipboard.copy(highlight.text) }
            Divider()
            Button("Remove Highlight", systemImage: "trash", role: .destructive) { model.removeHighlight(highlight) }
        }
        .swipeActions {
            Button("Remove", role: .destructive) { model.removeHighlight(highlight) }
            Button("Note") { beginEditing() }
        }
    }

    private func beginEditing() {
        draft = highlight.note
        editingNote = true
    }

    private func saveNote() {
        model.library.updateNote(draft.trimmingCharacters(in: .whitespacesAndNewlines), on: highlight)
        editingNote = false
    }
}
