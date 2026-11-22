import SwiftData
import SwiftUI

struct CollectBooksAction {
    let handler: ([UUID]) -> Void
    func callAsFunction(_ ids: [UUID]) {
        handler(ids)
    }
}

extension EnvironmentValues {
    @Entry var collectBooks: CollectBooksAction?
}

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
                                .font(.chickenUI(15))
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
            Haptics.selection()
            if containsAll { library.remove(books, from: collection) } else { library.add(books, to: collection) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: containsAll ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(containsAll ? palette.ribbon : palette.faint)
                    .frame(width: 24)
                Text(collection.name)
                    .font(.chickenUI(15, weight: .medium))
                    .foregroundStyle(palette.text)
                Spacer(minLength: 8)
                Text("\(collection.books?.count ?? 0)")
                    .font(.chickenMono(11, weight: .medium))
                    .foregroundStyle(palette.faint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(TactilePressStyle(scale: 0.99))
        .accessibilityAddTraits(containsAll ? .isSelected : [])
    }

    private func create() {
        guard library.createCollection(named: newName, with: books) != nil else { return }
        newName = ""
    }
}

struct CollectionMenuItem: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.collectBooks) private var collectBooks
    let book: Book

    var body: some View {
        Button("Add to Collection…", systemImage: "rectangle.stack.badge.plus") {
            if let collectBooks {
                collectBooks([book.id])
            } else {
                router.presentSheet(.collectionPicker(CollectingBooks(bookIDs: [book.id])))
            }
        }
    }
}
