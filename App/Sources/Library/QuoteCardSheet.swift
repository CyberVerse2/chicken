import ChickenKit
import SwiftUI
import UniformTypeIdentifiers

struct QuoteCardRequest: Identifiable, Equatable {
    let id = UUID()
    let quote: String
    let note: String
    let bookTitle: String
    let author: String
    let highlightColor: HighlightColor
    let coverTintIndex: Int
}

struct QuoteCardSheet: View {
    enum CardStyle: String, CaseIterable, Identifiable {
        case paper = "Paper"
        case sepia = "Sepia"
        case ink = "Ink"
        case cloth = "Cloth"

        var id: String { rawValue }
    }

    enum Aspect: String, CaseIterable, Identifiable {
        case square = "Square"
        case portrait = "Portrait"

        var id: String { rawValue }

        var size: CGSize {
            switch self {
            case .square: CGSize(width: 340, height: 340)
            case .portrait: CGSize(width: 320, height: 400)
            }
        }
    }

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let request: QuoteCardRequest

    @State private var style: CardStyle = .paper
    @State private var aspect: Aspect = .square
    @State private var showNote = true
    @State private var copiedImage = false
    @State private var renderedImage: RenderedQuoteImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    cardSurface
                        .shadow(color: palette.shadow, radius: 22, x: 0, y: 12)
                        .animation(reduceMotion ? nil : ChickenMotion.standard, value: style)
                        .animation(reduceMotion ? nil : ChickenMotion.standard, value: aspect)
                        .padding(.top, 8)

                    VStack(spacing: 16) {
                        HStack(spacing: 8) {
                            ForEach(CardStyle.allCases) { option in
                                styleChip(option)
                            }
                        }

                        Picker("Ratio", selection: $aspect) {
                            ForEach(Aspect.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 260)

                        if !request.note.isEmpty {
                            Toggle("Include margin note", isOn: $showNote)
                                .font(.chickenUI(14, weight: .medium))
                                .tint(palette.ribbon)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(palette.surface)
                                        .stroke(palette.border, lineWidth: 0.5)
                                )
                                .frame(maxWidth: 360)
                        }

                        GlassEffectContainer(spacing: 10) {
                            HStack(spacing: 10) {
                                if let renderedImage {
                                    ShareLink(
                                        item: renderedImage,
                                        preview: SharePreview(request.bookTitle, image: renderedImage.previewImage)
                                    ) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "square.and.arrow.up")
                                                .font(.system(size: 13.5, weight: .semibold))
                                            Text("Share Card")
                                        }
                                        .font(.chickenUI(14, weight: .semibold))
                                        .padding(.horizontal, 12)
                                        .frame(height: 24)
                                    }
                                    .inkProminentButton()
                                    .controlSize(.large)
                                }

                                Button {
                                    copyRenderedCard()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: copiedImage ? "checkmark" : "doc.on.doc")
                                            .font(.system(size: 13, weight: .medium))
                                            .contentTransition(.symbolEffect(.replace))
                                        Text(copiedImage ? "Copied" : "Copy Image")
                                    }
                                    .font(.chickenUI(14, weight: .medium))
                                    .foregroundStyle(palette.text)
                                    .padding(.horizontal, 10)
                                    .frame(height: 24)
                                }
                                .buttonStyle(.glass)
                                .controlSize(.large)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
            .background(palette.background.ignoresSafeArea())
            .navigationTitle("Quote Card")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { SheetDoneButton { dismiss() } }
            .task(id: renderKey) {
                renderSnapshot()
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 500, minHeight: 620, idealHeight: 680)
        #endif
    }

    private var renderKey: String {
        "\(style.rawValue)-\(aspect.rawValue)-\(showNote)"
    }

    private var cardSurface: some View {
        QuoteCardCanvas(
            request: request,
            style: style,
            aspect: aspect,
            showNote: showNote
        )
    }

    private func styleChip(_ option: CardStyle) -> some View {
        let selected = style == option
        return Button {
            Haptics.selection()
            withAnimation(reduceMotion ? nil : ChickenMotion.snappy) { style = option }
        } label: {
            Text(option.rawValue)
                .font(.chickenUI(13, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? palette.text : palette.muted)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(selected ? palette.surface : palette.surfaceAlt.opacity(0.6))
                        .stroke(selected ? palette.ribbon : palette.border, lineWidth: selected ? 1.5 : 0.5)
                )
        }
        .buttonStyle(TactilePressStyle())
    }

    private func renderSnapshot() {
        let renderer = ImageRenderer(content: cardSurface)
        renderer.scale = 3
        #if os(macOS)
        if let nsImage = renderer.nsImage, let tiff = nsImage.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
            renderedImage = RenderedQuoteImage(pngData: png, previewImage: Image(nsImage: nsImage))
        }
        #else
        if let uiImage = renderer.uiImage, let png = uiImage.pngData() {
            renderedImage = RenderedQuoteImage(pngData: png, previewImage: Image(uiImage: uiImage))
        }
        #endif
    }

    private func copyRenderedCard() {
        guard let renderedImage else { return }
        #if os(macOS)
        if let image = NSImage(data: renderedImage.pngData) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
        }
        #else
        if let image = UIImage(data: renderedImage.pngData) {
            UIPasteboard.general.image = image
        }
        #endif
        Haptics.success()
        copiedImage = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copiedImage = false
        }
    }
}

struct RenderedQuoteImage: Transferable {
    let pngData: Data
    let previewImage: Image

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.pngData }
    }
}

private struct QuoteCardCanvas: View {
    let request: QuoteCardRequest
    let style: QuoteCardSheet.CardStyle
    let aspect: QuoteCardSheet.Aspect
    let showNote: Bool

    private var colors: (bg: Color, text: Color, muted: Color, ribbon: Color, border: Color) {
        switch style {
        case .paper:
            let p = ReadingTheme.paper.palette
            return (p.surface, p.text, p.muted, p.ribbon, p.border)
        case .sepia:
            let p = ReadingTheme.sepia.palette
            return (p.background, p.text, p.muted, p.ribbon, p.border)
        case .ink:
            let p = ReadingTheme.ink.palette
            return (p.background, p.text, p.muted, p.ribbon, p.border)
        case .cloth:
            let preset = CoverPreset.preset(for: request.coverTintIndex)
            return (preset.cloth, preset.ink, preset.ink.opacity(0.72), preset.accent, preset.ink.opacity(0.18))
        }
    }

    private var quoteFontSize: CGFloat {
        switch request.quote.count {
        case ..<110: 21
        case ..<220: 18
        default: 15.5
        }
    }

    var body: some View {
        let c = colors
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Capsule()
                    .fill(c.ribbon)
                    .frame(width: 26, height: 3)
                Spacer()
                EggShape()
                    .stroke(c.muted.opacity(0.45), lineWidth: 1)
                    .frame(width: 10, height: 13)
            }
            .padding(.bottom, 22)

            Text("\u{201C}\(request.quote)\u{201D}")
                .font(.chickenSerif(quoteFontSize))
                .foregroundStyle(c.text)
                .lineSpacing(6)
                .minimumScaleFactor(0.72)
                .fixedSize(horizontal: false, vertical: true)

            if showNote && !request.note.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Rectangle()
                        .fill(request.highlightColor.bar)
                        .frame(width: 12, height: 1.5)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
                    Text(request.note)
                        .font(.chickenSerif(13.5, italic: true))
                        .foregroundStyle(c.muted)
                        .lineLimit(3)
                }
                .padding(.top, 16)
            }

            Spacer(minLength: 20)

            Rectangle()
                .fill(c.border)
                .frame(height: 0.5)
                .padding(.bottom, 14)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.bookTitle)
                        .font(.chickenDisplay(14))
                        .foregroundStyle(c.text)
                        .lineLimit(2)
                    if !request.author.isEmpty && request.author != "Unknown author" {
                        Text(request.author)
                            .font(.chickenUI(12))
                            .foregroundStyle(c.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 10)
                Text("CHICKEN")
                    .font(.chickenUI(9.5, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(c.muted.opacity(0.75))
            }
        }
        .padding(28)
        .frame(width: aspect.size.width, height: aspect.size.height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(c.bg)
                .stroke(c.border, lineWidth: 0.75)
        )
    }
}
