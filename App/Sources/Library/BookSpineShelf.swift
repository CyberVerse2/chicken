import ChickenKit
import SwiftUI

struct BookSpineShelf: View {
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass
    let books: [Book]
    var selection: Binding<Set<UUID>>?

    @State private var containerWidth: CGFloat = 350

    var body: some View {
        let rows = Self.pack(books: books, maxWidth: max(containerWidth, 260), compact: sizeClass == .compact)
        LazyVStack(alignment: .leading, spacing: 26) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .bottom, spacing: 5) {
                        ForEach(row) { item in
                            BookSpineView(
                                book: item.book,
                                width: item.width,
                                height: item.height,
                                selection: selection
                            )
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 4)

                    Rectangle()
                        .fill(palette.borderStrong)
                        .frame(height: 1)
                    LinearGradient(
                        colors: [palette.shadow.opacity(0.6), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 10)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            if width > 0 { containerWidth = width }
        }
        .coverCollection("spines", books: books.map(\.id))
    }

    private struct SpineMetrics: Identifiable {
        let book: Book
        let width: CGFloat
        let height: CGFloat
        var id: UUID { book.id }
    }

    private static func pack(books: [Book], maxWidth: CGFloat, compact: Bool) -> [[SpineMetrics]] {
        let gap: CGFloat = 5
        let metrics: [SpineMetrics] = books.map { book in
            let hash = book.id.uuidString.stableChickenHash
            let pageFactor: CGFloat
            if let pages = book.pageCount, pages > 0 {
                pageFactor = min(1, max(0, CGFloat(pages - 80) / 620.0))
            } else {
                pageFactor = CGFloat(hash % 100) / 100.0
            }
            let minW: CGFloat = compact ? 34 : 40
            let maxW: CGFloat = compact ? 54 : 64
            let width = (minW + (maxW - minW) * pageFactor).rounded()

            let heightVariation = CGFloat((hash >> 8) % 34)
            let baseHeight: CGFloat = compact ? 186 : 212
            let height = baseHeight + heightVariation
            return SpineMetrics(book: book, width: width, height: height)
        }

        var rows: [[SpineMetrics]] = []
        var current: [SpineMetrics] = []
        var usedWidth: CGFloat = 8

        for item in metrics {
            let needed = current.isEmpty ? item.width : item.width + gap
            if !current.isEmpty && usedWidth + needed > maxWidth {
                rows.append(current)
                current = [item]
                usedWidth = 8 + item.width
            } else {
                current.append(item)
                usedWidth += needed
            }
        }
        if !current.isEmpty { rows.append(current) }

        if rows.count >= 2 {
            let lastIndex = rows.count - 1
            let prevIndex = lastIndex - 1
            while rows[prevIndex].count - rows[lastIndex].count > 1 {
                let candidate = rows[prevIndex].last!
                let nextRowWidth = rows[lastIndex].reduce(CGFloat(8)) { $0 + $1.width }
                    + CGFloat(max(0, rows[lastIndex].count)) * gap
                    + candidate.width
                if nextRowWidth <= maxWidth {
                    rows[prevIndex].removeLast()
                    rows[lastIndex].insert(candidate, at: 0)
                } else {
                    break
                }
            }
        }

        return rows
    }
}

private struct BookSpineView: View {
    @Environment(\.palette) private var palette
    @Environment(\.coverContext) private var coverContext
    @Environment(\.bookSequence) private var bookSequence
    @Environment(\.selectBook) private var selectBook
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let book: Book
    let width: CGFloat
    let height: CGFloat
    var selection: Binding<Set<UUID>>?
    @State private var hovering = false

    private var preset: CoverPreset { CoverPreset.preset(for: book.coverTintIndex) }
    private var isSelected: Bool { selection?.wrappedValue.contains(book.id) ?? false }
    private var inProgress: Bool { book.progress > 0 && !book.isFinished }

    private func tapped() {
        Haptics.selection()
        guard let selection else {
            selectBook(book.id, in: bookSequence, from: CoverSource(context: coverContext, bookID: book.id))
            return
        }
        if isSelected { selection.wrappedValue.remove(book.id) } else { selection.wrappedValue.insert(book.id) }
    }

    var body: some View {
        Button(action: tapped) {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(preset.cloth)

                LinearGradient(
                    colors: [.white.opacity(0.18), .clear, .black.opacity(0.26)],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                VStack(spacing: 0) {
                    Rectangle()
                        .fill(.white.opacity(0.22))
                        .frame(height: 1.5)

                    VStack(spacing: 3) {
                        Rectangle().fill(preset.accent.opacity(0.55)).frame(height: 1)
                        Rectangle().fill(preset.ink.opacity(0.2)).frame(height: 0.5)
                    }
                    .padding(.horizontal, 5)
                    .padding(.top, 9)

                    Spacer(minLength: 6)

                    Text(book.displayTitle)
                        .font(book.coverTintIndex % 2 == 0
                              ? .chickenSerif(width >= 46 ? 13 : 11.5, weight: .semibold)
                              : .chickenUI(width >= 46 ? 12.5 : 11, weight: .semibold))
                        .foregroundStyle(preset.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: height - 56, alignment: .leading)
                        .rotationEffect(.degrees(90))
                        .frame(width: width - 8, height: height - 56)

                    Spacer(minLength: 6)

                    if inProgress {
                        VStack(spacing: 2) {
                            Rectangle().fill(preset.ink.opacity(0.14)).frame(height: 0.5)
                            ZStack(alignment: .leading) {
                                Rectangle().fill(preset.ink.opacity(0.16))
                                Rectangle()
                                    .fill(palette.ribbon)
                                    .frame(width: max(5, width * min(1, book.progress)))
                            }
                            .frame(width: width, height: 4)
                            Rectangle().fill(preset.ink.opacity(0.14)).frame(height: 0.5)
                        }
                        .padding(.bottom, 10)
                    } else if book.isFinished {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(preset.ink.opacity(0.75))
                            .padding(.bottom, 10)
                    } else {
                        EggShape()
                            .stroke(preset.ink.opacity(0.35), lineWidth: 0.75)
                            .frame(width: 6, height: 8)
                            .padding(.bottom, 10)
                    }
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(isSelected ? palette.ribbon : .black.opacity(0.15), lineWidth: isSelected ? 2 : 0.5)
            )
            .contentShape(Rectangle())
            .shadow(color: palette.shadow, radius: hovering ? 10 : 3, x: 1, y: hovering ? 6 : 2)
            #if os(macOS)
            .offset(y: hovering && !reduceMotion ? -8 : 0)
            #endif
            .overlay(alignment: .top) {
                if selection != nil {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isSelected ? palette.ribbon : palette.muted)
                        .background(palette.surface.opacity(0.92), in: .circle)
                        .offset(y: -8)
                }
            }
        }
        .buttonStyle(TactilePressStyle())
        #if os(macOS)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : ChickenMotion.micro, value: hovering)
        #endif
        .bookContextMenu(book)
        .accessibilityLabel("\(book.displayTitle) by \(book.displayAuthor)")
        .accessibilityValue(book.isFinished ? "Finished" : (inProgress ? "\(Int((book.progress * 100).rounded())) percent read" : "Unread"))
    }
}
