import ChickenKit
import SwiftUI

struct BookFinishedSheet: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette
    @Environment(\.readingTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let book: Book
    let onShareQuote: (Highlight) -> Void
    let onCloseReader: () -> Void
    let onKeepReading: () -> Void
    var onOpenNext: ((Book) -> Void)?

    @State private var coverHue: CoverHue?
    @State private var revealed = false
    @State private var detailsRevealed = false

    private var finishedThisYearCount: Int {
        library.booksFinished().count
    }

    private var annualGoal: Int {
        library.preferences.annualBookGoal
    }

    private var favoriteHighlight: Highlight? {
        book.sortedHighlights.first
    }

    private var nextBookInSeries: Book? {
        library.nextInSeries(after: book)
    }

    private var syncedToHardcover: Bool {
        library.preferences.syncHardcoverStatus && CatalogTokenStore.hasHardcoverToken && book.hardcoverBookID != nil
    }

    private var currentYear: String {
        String(Calendar.current.component(.year, from: Date()))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    ZStack {
                        let resolvedHue = coverHue ?? book.persistedCoverHue
                        RadialGradient(
                            colors: [
                                resolvedHue.wash(for: theme).opacity(palette.isDark ? 0.36 : 0.44),
                                resolvedHue.wash(for: theme).opacity(0.08),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 16,
                            endRadius: 145
                        )
                        .frame(width: 290, height: 290)
                        let coverHeight: CGFloat = 204
                        let coverWidth = (coverHeight * book.resolvedAspectRatio).rounded()
                        BookCover(book: book, style: .hero)
                            .frame(width: coverWidth, height: coverHeight)
                            .shadow(color: palette.shadow, radius: 22, x: 0, y: 14)
                            .scaleEffect(revealed ? 1 : 0.94)
                            .opacity(revealed ? 1 : 0)
                    }
                    .padding(.top, 16)

                    VStack(spacing: 6) {
                        Text("Finished")
                            .chickenEyebrow(palette, color: palette.ribbon)
                        Text(book.displayTitle)
                            .font(.chickenDisplay(26))
                            .tracking(-0.5)
                            .foregroundStyle(palette.text)
                            .multilineTextAlignment(.center)
                        if let author = book.author, !author.isEmpty {
                            Text(author)
                                .font(.chickenUI(15))
                                .foregroundStyle(palette.muted)
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(currentYear) reading goal")
                                .chickenEyebrow(palette)
                            Spacer()
                            Text("\(finishedThisYearCount) of \(annualGoal)")
                                .font(.chickenMono(13, weight: .semibold))
                                .foregroundStyle(palette.ribbon)
                        }

                        if annualGoal <= 24 {
                            EggCarton(laid: revealed ? finishedThisYearCount : max(0, finishedThisYearCount - 1), total: annualGoal)
                                .animation(reduceMotion ? nil : ChickenMotion.ribbonDrop, value: revealed)
                        } else {
                            ProgressLine(
                                progress: annualGoal > 0 ? min(1, Double(finishedThisYearCount) / Double(annualGoal)) : 0,
                                height: 3.5
                            )
                        }

                        HStack(spacing: 20) {
                            if let pages = book.pageCount, pages > 0 {
                                stat(value: "\(pages)", label: "pages")
                            }
                            stat(value: "\(book.highlightCount)", label: book.highlightCount == 1 ? "highlight" : "highlights")
                            stat(value: "\(library.readingSecondsToday / 60)", label: "min today")
                        }
                        .padding(.top, 4)

                        if syncedToHardcover {
                            Label("Synced to Hardcover", systemImage: "checkmark.icloud")
                                .font(.chickenUI(11.5, weight: .medium))
                                .foregroundStyle(palette.ribbon)
                                .padding(.top, 2)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(palette.surface)
                            .stroke(palette.border, lineWidth: 0.5)
                    )

                    if let next = nextBookInSeries {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Next in \(book.seriesName ?? "Series")")
                                .chickenEyebrow(palette, color: palette.ribbon)
                            HStack(spacing: 14) {
                                BookCover(book: next, style: .mini)
                                    .frame(width: 44, height: 66)
                                    .shadow(color: palette.shadow, radius: 4, y: 2)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(next.displayTitle)
                                        .font(.chickenUI(15, weight: .semibold))
                                        .foregroundStyle(palette.text)
                                        .lineLimit(2)
                                    if let badge = next.seriesBadgeText {
                                        Text(badge)
                                            .font(.chickenUI(12))
                                            .foregroundStyle(palette.muted)
                                            .lineLimit(1)
                                    }
                                    if let pages = next.pageCount, pages > 0 {
                                        Text("\(pages) pp. · \(ReadingEstimate.duration(forPages: pages, minutesPerPage: library.preferences.minutesPerPage))")
                                            .font(.chickenMono(11))
                                            .foregroundStyle(palette.faint)
                                    }
                                }
                                Spacer(minLength: 4)
                            }
                            if let onOpenNext {
                                Button {
                                    onOpenNext(next)
                                } label: {
                                    Label("Start Reading", systemImage: "arrow.right")
                                        .font(.chickenUI(13, weight: .semibold))
                                        .foregroundStyle(palette.ribbon)
                                }
                                .buttonStyle(TactilePressStyle(scale: 0.96))
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(palette.surface)
                                .stroke(palette.border, lineWidth: 0.5)
                        )
                        .opacity(detailsRevealed ? 1 : 0)
                        .offset(y: detailsRevealed || reduceMotion ? 0 : 8)
                    }

                    if let highlight = favoriteHighlight {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("A passage you kept")
                                .chickenEyebrow(palette)
                            Text("\u{201C}\(highlight.text)\u{201D}")
                                .font(.chickenSerif(16.5))
                                .foregroundStyle(palette.text)
                                .lineSpacing(5.5)
                                .lineLimit(5)
                            Button {
                                onShareQuote(highlight)
                            } label: {
                                Label("Create Quote Card", systemImage: "square.and.arrow.up")
                                    .font(.chickenUI(13, weight: .semibold))
                                    .foregroundStyle(palette.ribbon)
                            }
                            .buttonStyle(TactilePressStyle(scale: 0.96))
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(palette.surface)
                                .stroke(palette.border, lineWidth: 0.5)
                        )
                        .opacity(detailsRevealed ? 1 : 0)
                        .offset(y: detailsRevealed || reduceMotion ? 0 : 8)
                    }

                    VStack(spacing: 10) {
                        Button(action: onCloseReader) {
                            Text("Back to Library")
                                .font(.chickenUI(15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 28)
                        }
                        .inkProminentButton()
                        .controlSize(.large)

                        Button("Keep Reading", action: onKeepReading)
                            .font(.chickenUI(14, weight: .medium))
                            .foregroundStyle(palette.muted)
                            .buttonStyle(TactilePressStyle(scale: 0.96))
                            .padding(.vertical, 6)
                    }
                    .padding(.top, 4)
                    .opacity(detailsRevealed ? 1 : 0)
                    .offset(y: detailsRevealed || reduceMotion ? 0 : 10)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
            .background(palette.background.ignoresSafeArea())
            .task {
                coverHue = await CoverTintModifier.hue(for: book, library: library)
                withAnimation(reduceMotion ? nil : ChickenMotion.standard) {
                    revealed = true
                }
                if reduceMotion {
                    detailsRevealed = true
                } else {
                    try? await Task.sleep(for: .milliseconds(60))
                    withAnimation(ChickenMotion.standard) {
                        detailsRevealed = true
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 480, minHeight: 580, idealHeight: 640)
        #endif
    }

    private func stat(value: String, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.chickenDisplay(19))
                .foregroundStyle(palette.text)
                .monospacedDigit()
            Text(label)
                .font(.chickenUI(12.5))
                .foregroundStyle(palette.muted)
        }
    }
}
