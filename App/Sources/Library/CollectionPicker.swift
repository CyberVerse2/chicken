import SwiftData
import SwiftUI

/// Adds books to collections: each collection with a check when all the
/// books are in it, and a field for a new one.
struct CollectionPicker: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Query private var collections: [BookCollection]
    let bookIDs: [UUID]
    @State private var newName = ""
    @FocusState private var naming: Bool

    private var books: [Book] { bookIDs.compactMap(library.book(id:)) }

    private var sorted: [BookCollection] {
        collections.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            ChickenPage(title: "Add to Collection", subtitle: books.count == 1 ? books.first?.displayTitle : "\(books.count) books") {
                ChickenSection("Collections") {
                    ForEach(sorted) { collection in
                        ChickenRow {
                            row(collection)
                        }
                    }
                    ChickenRow(isLast: true) {
                        HStack(spacing: 12) {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(palette.muted)
                                .frame(width: 24)
                            TextField("New collection", text: $newName)
                                .font(.chickenSerif(16))
                                .textFieldStyle(.plain)
                                .focused($naming)
                                .onSubmit(create)
                                .submitLabel(.done)
                            if !newName.trimmingCharacters(in: .whitespaces).isEmpty {
                                Button("Add", action: create)
                                    .font(.chickenUI(13, weight: .medium))
                                    .foregroundStyle(palette.text)
                                    .buttonStyle(.glass)
                            }
                        }
                    }
                }
            }
            .toolbar { SheetDoneButton { dismiss() } }
        }
        .onAppear { if collections.isEmpty { naming = true } }
        #if os(macOS)
        .frame(width: 440, height: 480)
        #endif
    }

    private func row(_ collection: BookCollection) -> some View {
        let containsAll = !books.isEmpty && books.allSatisfy { library.contains($0, in: collection) }
        return Button {
            if containsAll { library.remove(books, from: collection) } else { library.add(books, to: collection) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: containsAll ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(containsAll ? palette.ribbon : palette.faint)
                    .frame(width: 24)
                Text(collection.name)
                    .font(.chickenSerif(16, weight: .semibold))
                    .foregroundStyle(palette.text)
                Spacer(minLength: 8)
                Text("\(collection.books?.count ?? 0)")
                    .font(.chickenMono(11, weight: .medium))
                    .foregroundStyle(palette.faint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(containsAll ? .isSelected : [])
    }

    private func create() {
        guard library.createCollection(named: newName, with: books) != nil else { return }
        newName = ""
    }
}

/// "Add to Collection…" for a book's menus.
struct CollectionMenuItem: View {
    @Environment(AppRouter.self) private var router
    let book: Book

    var body: some View {
        Button("Add to Collection…", systemImage: "rectangle.stack.badge.plus") {
            router.collectingBooks = CollectingBooks(bookIDs: [book.id])
        }
    }
}

extension View {
    /// Presents the collection picker when something asks for it. Applied
    /// wherever a presentation may sit on top, since a sheet can't present
    /// over another one from underneath.
    func collectionPicker() -> some View {
        modifier(CollectionPickerPresenter())
    }
}

private struct CollectionPickerPresenter: ViewModifier {
    @Environment(AppRouter.self) private var router
    @Environment(LibraryStore.self) private var library

    func body(content: Content) -> some View {
        @Bindable var router = router
        content.sheet(item: $router.collectingBooks) { request in
            CollectionPicker(bookIDs: request.bookIDs)
                .environment(library)
                .readingTheme(library.preferences.theme)
        }
    }
}
