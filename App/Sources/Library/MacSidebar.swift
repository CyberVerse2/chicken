#if os(macOS)
import SwiftUI

/// The Mac's sidebar: the house lockup, the four places, the books you're
/// reading (each with its cover and how far in), and today's reading.
struct MacSidebar: View {
    @Environment(\.palette) private var palette
    @Binding var selection: AppTab
    let reading: [Book]

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("Home", systemImage: "book.pages").tag(AppTab.home)
                Label("Library", systemImage: "books.vertical").tag(AppTab.library)
                Label("Notebook", systemImage: "highlighter").tag(AppTab.notebook)
                Label("Search", systemImage: "magnifyingglass").tag(AppTab.search)
                Label("Your Reading", systemImage: "chart.bar").tag(AppTab.yourReading)
            }
            if !reading.isEmpty {
                Section("Reading") {
                    ForEach(reading) { book in
                        MacSidebarBookRow(book: book)
                            .tag(AppTab.book(book.id))
                            .bookContextMenu(book)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        // The theme's own paper rather than the system's cool grey.
        .scrollContentBackground(.hidden)
        .background(palette.surfaceAlt.opacity(0.55))
        .safeAreaInset(edge: .top, spacing: 0) {
            BrandLockup(size: 18)
                .padding(.horizontal, 18)
                .padding(.top, 2)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarTodayMeter { selection = .yourReading }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
        }
    }
}

/// A book in progress: a small cover with its ribbon, the title, and a
/// ribbon meter.
private struct MacSidebarBookRow: View {
    @Environment(\.palette) private var palette
    let book: Book

    var body: some View {
        HStack(spacing: 11) {
            BookCover(book: book, style: .mini)
                .frame(width: 24, height: 36)
                .shadow(color: palette.shadow, radius: 1.5, x: 0.5, y: 1)
            VStack(alignment: .leading, spacing: 5) {
                Text(book.displayTitle)
                    .font(.chickenSerif(13, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    ProgressLine(progress: book.progress, height: 2)
                    Text("\(Int((book.progress * 100).rounded()))%")
                        .font(.chickenMono(10, weight: .medium))
                        .foregroundStyle(palette.muted)
                        .fixedSize()
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(book.displayTitle)
        .accessibilityValue("\(Int((book.progress * 100).rounded())) percent read")
    }
}
#endif
