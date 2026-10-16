import SwiftUI

/// A small cloud on a cover whose book isn't on this device, so you know
/// before you tap; a ribbon-coloured ring while it downloads. Nothing once
/// it's here, or when the library doesn't sync.
struct DownloadBadge: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette
    let book: Book
    var size: CGFloat = 22

    var body: some View {
        if let download = library.download(for: book) {
            Group {
                if let progress = download.progress {
                    ZStack {
                        Circle().stroke(palette.border, lineWidth: 2)
                        Circle()
                            .trim(from: 0, to: max(0.04, progress))
                            .stroke(palette.ribbon, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .padding(5)
                    .animation(.smooth(duration: 0.4), value: progress)
                    .accessibilityLabel("Downloading, \(Int((progress * 100).rounded())) percent")
                } else if !download.isOnDevice {
                    Image(systemName: "icloud")
                        .font(.system(size: size * 0.46, weight: .medium))
                        .foregroundStyle(palette.muted)
                        .accessibilityLabel("In iCloud")
                }
            }
            .frame(width: size, height: size)
            .background(palette.surface.opacity(0.92), in: .circle)
            .shadow(color: palette.shadow, radius: 2, y: 1)
            .opacity(download.isOnDevice && download.progress == nil ? 0 : 1)
            .transition(.opacity)
        }
    }
}

extension View {
    /// Marks a cover whose book is only in iCloud, or downloading.
    func downloadBadge(_ book: Book, size: CGFloat = 22) -> some View {
        overlay(alignment: .bottomTrailing) {
            DownloadBadge(book: book, size: size)
                .padding(size * 0.3)
                .allowsHitTesting(false)
        }
    }
}

/// Download, Keep on This Device, and Remove Download, wherever a book's
/// actions are listed. Nothing when the library doesn't sync, and only
/// Remove (when it applies) while "Download all" is on.
struct DownloadMenuItems: View {
    @Environment(LibraryStore.self) private var library
    let book: Book

    var body: some View {
        if let download = library.download(for: book) {
            let downloadsAll = library.preferences.downloadsAllBooks
            if !downloadsAll || library.canRemoveDownload(book) {
                Divider()
            }
            if !downloadsAll {
                if !download.isOnDevice && download.progress == nil {
                    Button("Download", systemImage: "arrow.down.circle") { library.startDownload([book]) }
                }
                Toggle(isOn: Binding(get: { library.isKept(book) }, set: { library.setKept($0, for: [book]) })) {
                    Label("Keep on This Device", systemImage: "pin")
                }
            }
            if library.canRemoveDownload(book) {
                Button("Remove Download", systemImage: "minus.circle") { library.removeDownload([book]) }
            }
        }
    }
}
