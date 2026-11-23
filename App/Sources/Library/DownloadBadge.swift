import SwiftUI

struct DownloadBadge: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let book: Book
    var size: CGFloat = 22

    var body: some View {
        if let download = library.download(for: book) {
            Group {
                switch download.status {
                case .downloading(let progress):
                    ZStack {
                        Circle().stroke(palette.border, lineWidth: 2)
                        Circle()
                            .trim(from: 0, to: max(0.04, progress))
                            .stroke(palette.ribbon, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .padding(5)
                    .animation(reduceMotion ? nil : ChickenMotion.standard, value: progress)
                    .accessibilityLabel("Downloading, \(Int((progress * 100).rounded())) percent")
                case .cloudOnly:
                    Image(systemName: "icloud")
                        .font(.system(size: size * 0.46, weight: .medium))
                        .foregroundStyle(palette.muted)
                        .accessibilityLabel("In iCloud")
                case .failed:
                    Image(systemName: "exclamationmark.icloud")
                        .font(.system(size: size * 0.46, weight: .medium))
                        .foregroundStyle(palette.ribbon)
                        .accessibilityLabel("Download failed")
                case .downloaded:
                    EmptyView()
                }
            }
            .frame(width: size, height: size)
            .background(palette.surface.opacity(0.94), in: .circle)
            .shadow(color: palette.shadow, radius: 2, y: 1)
            .opacity(download.isOnDevice ? 0 : 1)
            .transition(.opacity)
        }
    }
}

extension View {
    func downloadBadge(_ book: Book, size: CGFloat = 22, alignment: Alignment = .bottomTrailing) -> some View {
        overlay(alignment: alignment) {
            DownloadBadge(book: book, size: size)
                .padding(size * 0.3)
                .allowsHitTesting(false)
        }
    }
}

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
                    Button(
                        download.status == .failed ? "Retry Download" : "Download",
                        systemImage: "arrow.down.circle"
                    ) {
                        library.startDownload([book])
                    }
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
