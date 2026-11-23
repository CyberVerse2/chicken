import ChickenKit
import SwiftUI

struct PullRibbonOverlay: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isBookmarked: Bool
    let isCompact: Bool
    let onToggle: () -> Void

    @State private var dragTranslation: CGFloat = 0
    @State private var isDragging = false
    @State private var crossedThreshold = false

    private let threshold: CGFloat = 46
    private var restingHeight: CGFloat { isCompact ? 82 : 64 }
    private var ribbonWidth: CGFloat { isCompact ? 15 : 18 }

    private var displayedHeight: CGFloat {
        if isBookmarked {
            if isDragging {
                let delta = dragTranslation
                if delta < 0 {
                    return max(14, restingHeight + delta)
                }
                return restingHeight + rubberBand(delta, limit: 36)
            }
            return restingHeight
        } else {
            if isDragging && dragTranslation > 0 {
                return min(restingHeight + 24, 16 + rubberBand(dragTranslation, limit: restingHeight + 8))
            }
            return 0
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            if displayedHeight > 1 {
                Ribbon()
                    .frame(width: ribbonWidth, height: displayedHeight)
                    .shadow(color: .black.opacity(0.22), radius: 2, x: 0, y: 1.5)
                    .opacity(isBookmarked ? 1 : min(1, Double(displayedHeight / 34)))
                    .animation(isDragging || reduceMotion ? nil : ChickenMotion.ribbonDrop, value: isBookmarked)
                    .animation(isDragging || reduceMotion ? nil : ChickenMotion.snappy, value: displayedHeight)
            }

            if isDragging && !isBookmarked && dragTranslation > 14 {
                Text(crossedThreshold ? "Release to bookmark" : "Pull to bookmark")
                    .font(.chickenUI(10.5, weight: .semibold))
                    .foregroundStyle(crossedThreshold ? palette.ribbon : palette.muted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassEffect(.regular, in: .capsule)
                    .fixedSize()
                    .offset(x: -54, y: max(28, displayedHeight - 10))
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    .allowsHitTesting(false)
            }
        }
        .frame(width: 58, height: 108, alignment: .top)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    isDragging = true
                    dragTranslation = value.translation.height
                    let passed = isBookmarked
                        ? (value.translation.height < -threshold || value.translation.height > threshold + 16)
                        : (value.translation.height > threshold)
                    if passed && !crossedThreshold {
                        crossedThreshold = true
                        Haptics.impact(.medium)
                    } else if !passed && crossedThreshold {
                        crossedThreshold = false
                    }
                }
                .onEnded { value in
                    let velocity = value.predictedEndTranslation.height - value.translation.height
                    let shouldToggle: Bool
                    if isBookmarked {
                        shouldToggle = value.translation.height < -threshold
                            || value.translation.height > threshold + 16
                            || velocity < -260
                    } else {
                        shouldToggle = value.translation.height > threshold || velocity > 260
                    }
                    isDragging = false
                    dragTranslation = 0
                    crossedThreshold = false
                    if shouldToggle {
                        onToggle()
                    }
                }
        )
        .padding(.trailing, isCompact ? 10 : 28)
        .ignoresSafeArea(edges: .top)
        .accessibilityElement()
        .accessibilityLabel(isBookmarked ? "Bookmarked" : "Pull to bookmark")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onToggle() }
    }

    private func rubberBand(_ offset: CGFloat, limit: CGFloat) -> CGFloat {
        let clamped = max(0, offset)
        if clamped <= limit { return clamped }
        return limit + (clamped - limit) * 0.24
    }
}

struct FootnotePopoverCard: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let footnote: ReaderFootnote
    let onJump: () -> Void
    let onDismiss: () -> Void
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Text("Note \(footnote.label)")
                    .chickenEyebrow(palette, color: palette.ribbon)
                Spacer()
                if footnote.chapterIndex != nil {
                    Button("Jump", action: onJump)
                        .font(.chickenUI(12.5, weight: .semibold))
                        .foregroundStyle(palette.muted)
                        .buttonStyle(TactilePressStyle(scale: 0.94))
                }
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.muted)
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                }
                .buttonStyle(TactilePressStyle(scale: 0.92))
                .accessibilityLabel("Dismiss footnote")
            }

            ScrollView {
                Text(footnote.text)
                    .font(.chickenSerif(15.5))
                    .foregroundStyle(palette.text)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(18)
        .frame(maxWidth: 460)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: palette.shadow, radius: 18, x: 0, y: 8)
        .offset(y: max(0, dragOffset))
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    dragOffset = max(0, value.translation.height)
                }
                .onEnded { value in
                    let velocity = value.predictedEndTranslation.height - value.translation.height
                    if value.translation.height > 48 || velocity > 220 {
                        Haptics.selection()
                        onDismiss()
                    } else {
                        withAnimation(reduceMotion ? nil : ChickenMotion.snappy) {
                            dragOffset = 0
                        }
                    }
                }
        )
    }
}

struct PreviouslyCatchUpCard: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let book: Book
    let lastOpened: Date
    let recentHighlight: Highlight?
    let onJumpToHighlight: (Highlight) -> Void
    let onDismiss: () -> Void
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text("Previously · \(lastOpened.formatted(.relative(presentation: .named)))")
                    .chickenEyebrow(palette, color: palette.ribbon)
                Spacer(minLength: 8)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(palette.muted)
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .buttonStyle(TactilePressStyle(scale: 0.92))
                .accessibilityLabel("Dismiss recap")
            }

            HStack(spacing: 6) {
                Text("\(Int((book.progress * 100).rounded()))%")
                    .font(.chickenMono(12, weight: .semibold))
                    .foregroundStyle(palette.text)
                if let chapter = book.lastChapterTitle, !chapter.isEmpty {
                    Text("·")
                        .foregroundStyle(palette.faint)
                    Text(chapter)
                        .font(.chickenUI(13, weight: .medium))
                        .foregroundStyle(palette.muted)
                        .lineLimit(1)
                }
            }

            if let highlight = recentHighlight {
                Button {
                    onJumpToHighlight(highlight)
                    onDismiss()
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Capsule()
                            .fill(highlight.color.bar)
                            .frame(width: 3)
                        Text("\u{201C}\(highlight.text)\u{201D}")
                            .font(.chickenSerif(14))
                            .foregroundStyle(palette.text)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
                }
                .buttonStyle(TactilePressStyle(scale: 0.98))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: 460, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: palette.shadow, radius: 14, x: 0, y: 6)
        .offset(y: min(0, dragOffset))
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    dragOffset = min(0, value.translation.height)
                }
                .onEnded { value in
                    let velocity = value.predictedEndTranslation.height - value.translation.height
                    if value.translation.height < -32 || velocity < -180 {
                        Haptics.selection()
                        onDismiss()
                    } else {
                        withAnimation(reduceMotion ? nil : ChickenMotion.snappy) {
                            dragOffset = 0
                        }
                    }
                }
        )
    }
}

struct ImageLightboxOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let preview: ReaderImagePreview
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 1
    @State private var steadyScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var steadyOffset: CGSize = .zero
    @State private var loadedImage: PlatformImage?

    private var dismissBackdropOpacity: Double {
        guard scale <= 1.05 else { return 0.92 }
        let progress = min(1, abs(offset.height) / 260)
        return max(0.35, 0.92 * (1 - progress * 0.6))
    }

    var body: some View {
        ZStack {
            Color.black.opacity(dismissBackdropOpacity)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 16) {
                if let loadedImage {
                    Image(platformImage: loadedImage)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnifyGesture()
                                .onChanged { value in
                                    scale = min(4, max(1, steadyScale * value.magnification))
                                }
                                .onEnded { _ in
                                    steadyScale = scale
                                    if scale <= 1.02 {
                                        withAnimation(reduceMotion ? nil : ChickenMotion.snappy) {
                                            scale = 1
                                            steadyScale = 1
                                            offset = .zero
                                            steadyOffset = .zero
                                        }
                                    }
                                }
                        )
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 8)
                                .onChanged { value in
                                    if scale > 1.05 {
                                        offset = CGSize(
                                            width: steadyOffset.width + value.translation.width,
                                            height: steadyOffset.height + value.translation.height
                                        )
                                    } else {
                                        offset = CGSize(width: 0, height: value.translation.height)
                                    }
                                }
                                .onEnded { value in
                                    if scale > 1.05 {
                                        steadyOffset = offset
                                    } else {
                                        let velocity = abs(value.predictedEndTranslation.height - value.translation.height)
                                        if abs(value.translation.height) > 90 || velocity > 320 {
                                            onDismiss()
                                        } else {
                                            withAnimation(reduceMotion ? nil : ChickenMotion.snappy) {
                                                offset = .zero
                                            }
                                        }
                                    }
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(reduceMotion ? nil : ChickenMotion.standard) {
                                if scale > 1.1 {
                                    scale = 1
                                    steadyScale = 1
                                    offset = .zero
                                    steadyOffset = .zero
                                } else {
                                    scale = 2.2
                                    steadyScale = 2.2
                                }
                            }
                        }
                        .padding(20)
                } else {
                    ProgressView()
                        .tint(.white)
                }

                if !preview.alt.isEmpty {
                    Text(preview.alt)
                        .font(.chickenUI(13))
                        .foregroundStyle(.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 28)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            CircularGlassButton(
                title: "Close",
                systemImage: "xmark",
                diameter: 44,
                iconSize: 17,
                foreground: .white,
                action: onDismiss
            )
            .padding(20)
        }
        .task(id: preview.url) {
            loadedImage = await Self.loadImage(from: preview.url)
        }
    }

    @concurrent
    private static func loadImage(from url: URL) async -> PlatformImage? {
        if url.scheme == EPUBSchemeRegistry.scheme,
           let data = EPUBSchemeRegistry.shared.resourceData(for: url) {
            return PlatformImage(data: data)
        }
        guard url.isFileURL, let data = try? Data(contentsOf: url) else { return nil }
        return PlatformImage(data: data)
    }
}
