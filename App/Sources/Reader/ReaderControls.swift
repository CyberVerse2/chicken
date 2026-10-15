import ChickenKit
import SwiftUI

// MARK: - Progress

/// Floating glass bar at the bottom of the reader: progress, a scrubber,
/// and where you are in the book.
struct ReaderProgressBar: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: ReaderModel
    let compact: Bool
    @State private var dragProgress: Double?

    private var shown: Double { min(1, max(0, dragProgress ?? model.overallProgress)) }

    var body: some View {
        HStack(spacing: 14) {
            Text("\(Int((shown * 100).rounded()))%")
                .font(.chickenMono(11, weight: .medium))
                .foregroundStyle(palette.muted)
                .frame(minWidth: 34, alignment: .leading)
                .contentTransition(.numericText())

            scrubber

            VStack(alignment: .trailing, spacing: 2) {
                // At the end the readout turns to serif italic: a quiet
                // marker that the book is finished.
                Text(model.pageReadout)
                    .font(model.isOnLastPage ? .chickenSerif(12, italic: true) : .chickenMono(11))
                    .foregroundStyle(palette.muted)
                if !compact {
                    let detail = [model.chapterReadout, model.timeReadout].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.chickenMono(10))
                            .foregroundStyle(palette.faint)
                            .lineLimit(1)
                    }
                }
            }
            .monospacedDigit()
            .fixedSize()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, compact ? 10 : 12)
        .frame(maxWidth: 820)
        .glassEffect(.regular, in: .capsule)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: shown)
    }

    private var scrubber: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(palette.text.opacity(0.12)).frame(height: 3)
                Capsule().fill(palette.ribbon).frame(width: width * shown, height: 3)
                Circle()
                    .fill(palette.ribbon)
                    .overlay(Circle().stroke(palette.background.opacity(0.8), lineWidth: 1.5))
                    .frame(width: dragProgress == nil ? 9 : 13, height: dragProgress == nil ? 9 : 13)
                    .offset(x: min(width - 9, max(0, width * shown - 4.5)))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let progress = min(1, max(0, value.location.x / width))
                        dragProgress = progress
                        model.seek(to: progress)
                    }
                    .onEnded { value in
                        model.seek(to: min(1, max(0, value.location.x / width)))
                        dragProgress = nil
                    }
            )
        }
        .frame(height: 24)
        .accessibilityElement()
        .accessibilityLabel("Reading position")
        .accessibilityValue("\(Int((shown * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            let step = 0.02
            model.seek(to: shown + (direction == .increment ? step : -step))
        }
    }
}

// MARK: - Highlighting

/// Appears while text is selected: pick a color to highlight it.
struct HighlightPicker: View {
    @Environment(\.palette) private var palette
    let model: ReaderModel

    var body: some View {
        HStack(spacing: 10) {
            Text("Highlight")
                .font(.chickenUI(12, weight: .medium))
                .foregroundStyle(palette.muted)
            ForEach(HighlightColor.allCases) { color in
                Button {
                    model.addHighlight(color: color)
                } label: {
                    Circle()
                        .fill(color.bar)
                        .frame(width: 24, height: 24)
                        .overlay(Circle().stroke(palette.text.opacity(0.15), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Highlight \(color.label)")
            }
            Divider().frame(height: 18)
            Button("Copy", systemImage: "doc.on.doc") {
                if let text = model.selection?.text { Clipboard.copy(text) }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(palette.muted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

// MARK: - Search

struct ReaderSearchBar: View {
    @Environment(\.palette) private var palette
    @Binding var text: String
    let onSearch: (_ backwards: Bool) -> Void
    let onClose: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(palette.faint)
            TextField("Search in book", text: $text)
                .textFieldStyle(.plain)
                .font(.chickenUI(14))
                .focused($focused)
                .onSubmit { onSearch(false) }
                .frame(minWidth: 180)
            Button("Previous match", systemImage: "chevron.up") { onSearch(true) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Button("Next match", systemImage: "chevron.down") { onSearch(false) }
                .keyboardShortcut("g")
            Button("Close search", systemImage: "xmark") { onClose() }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .foregroundStyle(palette.muted)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 420)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 16)
        .onAppear { focused = true }
    }
}

// MARK: - Typography

struct TypographyPanel: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette
    @Bindable var model: ReaderModel
    let isCompact: Bool

    private var modes: [ReadingMode] { isCompact ? [.scroll, .paged] : ReadingMode.allCases }
    private var hasTypography: Bool { model.book.format != .pdf }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if hasTypography {
                    sample
                    typefacePicker
                    VStack(spacing: 0) {
                        row(
                            "Size", value: "\(Int(model.fontSize)) pt",
                            canDecrease: model.fontSize > ReaderPreferences.fontSizeRange.lowerBound,
                            canIncrease: model.fontSize < ReaderPreferences.fontSizeRange.upperBound,
                            decrease: { model.fontSize -= 1 }, increase: { model.fontSize += 1 }
                        )
                        divider
                        row(
                            "Line spacing", value: model.lineHeight.formatted(.number.precision(.fractionLength(1))),
                            canDecrease: model.lineHeight > ReaderPreferences.lineHeightRange.lowerBound + 0.001,
                            canIncrease: model.lineHeight < ReaderPreferences.lineHeightRange.upperBound - 0.001,
                            decrease: { model.lineHeight = ((model.lineHeight - 0.1) * 100).rounded() / 100 },
                            increase: { model.lineHeight = ((model.lineHeight + 0.1) * 100).rounded() / 100 }
                        )
                        if !isCompact {
                            divider
                            row(
                                "Column width", value: "\(Int(model.columnWidth)) pt",
                                canDecrease: model.columnWidth > ReaderPreferences.columnWidthRange.lowerBound,
                                canIncrease: model.columnWidth < ReaderPreferences.columnWidthRange.upperBound,
                                decrease: { model.columnWidth -= 40 }, increase: { model.columnWidth += 40 }
                            )
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.surface))
                }

                if model.book.format.supportsFlowModes {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Layout").chickenEyebrow(palette)
                        HStack(spacing: 8) {
                            ForEach(modes) { mode in
                                modeButton(mode)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Theme").chickenEyebrow(palette)
                    ThemeSwatchPicker(compact: true)
                }

                if hasTypography {
                    Button("Reset to Defaults", systemImage: "arrow.counterclockwise") {
                        withAnimation(.snappy) { model.resetTypography() }
                    }
                    .font(.chickenUI(13, weight: .medium))
                    .foregroundStyle(palette.muted)
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: isCompact ? nil : 340)
        .frame(maxWidth: isCompact ? .infinity : nil, minHeight: isCompact ? nil : 440)
        .background(palette.background.opacity(isCompact ? 1 : 0))
    }

    /// Each face set in itself, in a horizontally scrolling row.
    private var typefacePicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(ReaderTypeface.allCases) { face in
                    let selected = model.typeface == face
                    Button {
                        withAnimation(.snappy) { model.typeface = face }
                    } label: {
                        VStack(spacing: 4) {
                            Text("Ag").font(face.font(22))
                            Text(face.label)
                                .font(.chickenUI(11, weight: selected ? .semibold : .regular))
                                .lineLimit(1)
                        }
                        .foregroundStyle(selected ? palette.text : palette.muted)
                        .frame(minWidth: 64)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(selected ? palette.surface : palette.surfaceAlt.opacity(0.5))
                                .stroke(selected ? palette.ribbon : .clear, lineWidth: 1.5)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(face.label)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    /// A live preview of the current face, size, and spacing.
    private var sample: some View {
        Text("Rain on the window, tea gone cold, and one more chapter before bed.")
            .font(model.typeface.font(min(model.fontSize, 22)))
            .lineSpacing(CGFloat(model.lineHeight - 1) * CGFloat(min(model.fontSize, 22)) * 0.6)
            .foregroundStyle(palette.text)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.surfaceAlt.opacity(0.6)))
            .animation(.snappy, value: model.fontSize)
            .animation(.snappy, value: model.lineHeight)
            .animation(.snappy, value: model.typeface)
            .accessibilityHidden(true)
    }

    private var divider: some View {
        Rectangle().fill(palette.border).frame(height: 0.5).padding(.leading, 16)
    }

    private func row(
        _ label: String, value: String,
        canDecrease: Bool, canIncrease: Bool,
        decrease: @escaping () -> Void, increase: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.chickenUI(14)).foregroundStyle(palette.text)
                Text(value).font(.chickenSerif(13, italic: true)).foregroundStyle(palette.muted).monospacedDigit()
            }
            Spacer()
            GlassStepper(label: label, canDecrease: canDecrease, canIncrease: canIncrease, decrease: decrease, increase: increase)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func modeButton(_ mode: ReadingMode) -> some View {
        let selected = model.readingMode == mode
        Button {
            withAnimation(.snappy) { model.readingMode = mode }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 18, weight: .light))
                Text(mode.label)
                    .font(.chickenUI(12, weight: selected ? .semibold : .regular))
            }
            .foregroundStyle(selected ? palette.text : palette.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? palette.surface : palette.surfaceAlt.opacity(0.5))
                    .stroke(selected ? palette.ribbon : .clear, lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
