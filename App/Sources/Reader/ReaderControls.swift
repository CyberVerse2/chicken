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
                Capsule().fill(palette.text.opacity(0.75)).frame(width: width * shown, height: 3)
                Circle()
                    .fill(palette.text)
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

    private var modes: [ReadingMode] {
        isCompact ? [.scroll, .paged] : ReadingMode.allCases
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Text & Layout").chickenEyebrow(palette)

            if model.book.format != .pdf {
                StepperRow(
                    label: "Size",
                    value: "\(Int(model.fontSize)) pt",
                    canDecrease: model.fontSize > ReaderPreferences.fontSizeRange.lowerBound,
                    canIncrease: model.fontSize < ReaderPreferences.fontSizeRange.upperBound,
                    decrease: { model.fontSize -= 1 },
                    increase: { model.fontSize += 1 }
                )
                StepperRow(
                    label: "Spacing",
                    value: model.lineHeight.formatted(.number.precision(.fractionLength(2))),
                    canDecrease: model.lineHeight > ReaderPreferences.lineHeightRange.lowerBound + 0.001,
                    canIncrease: model.lineHeight < ReaderPreferences.lineHeightRange.upperBound - 0.001,
                    decrease: { model.lineHeight = ((model.lineHeight - 0.1) * 100).rounded() / 100 },
                    increase: { model.lineHeight = ((model.lineHeight + 0.1) * 100).rounded() / 100 }
                )
                if !isCompact {
                    StepperRow(
                        label: "Width",
                        value: "\(Int(model.columnWidth)) pt",
                        canDecrease: model.columnWidth > ReaderPreferences.columnWidthRange.lowerBound,
                        canIncrease: model.columnWidth < ReaderPreferences.columnWidthRange.upperBound,
                        decrease: { model.columnWidth -= 40 },
                        increase: { model.columnWidth += 40 }
                    )
                }
            }

            if model.book.format.supportsFlowModes {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Flow").font(.chickenUI(12)).foregroundStyle(palette.muted)
                    Picker("Flow", selection: $model.readingMode) {
                        ForEach(modes) { Label($0.label, systemImage: $0.systemImage).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Theme").font(.chickenUI(12)).foregroundStyle(palette.muted)
                HStack(spacing: 8) {
                    ForEach(ReadingTheme.allCases) { theme in
                        let swatch = theme.palette
                        let selected = library.preferences.theme == theme
                        Button { library.preferences.theme = theme } label: {
                            Text(theme.label)
                                .font(.chickenSerif(13, italic: true))
                                .foregroundStyle(swatch.text)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(swatch.background)
                                        .stroke(selected ? swatch.text : swatch.border, lineWidth: selected ? 1.5 : 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }

            if model.book.format != .pdf {
                Button("Reset to Defaults") { model.resetTypography() }
                    .buttonStyle(.glass)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .frame(width: isCompact ? nil : 320)
        .frame(maxWidth: isCompact ? .infinity : nil)
    }
}

private struct StepperRow: View {
    @Environment(\.palette) private var palette
    let label: String
    let value: String
    let canDecrease: Bool
    let canIncrease: Bool
    let decrease: () -> Void
    let increase: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.chickenUI(13)).foregroundStyle(palette.text)
                Text(value).font(.chickenMono(11)).foregroundStyle(palette.faint)
            }
            Spacer()
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    Button("Decrease \(label)", systemImage: "minus", action: decrease)
                        .disabled(!canDecrease)
                    Button("Increase \(label)", systemImage: "plus", action: increase)
                        .disabled(!canIncrease)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
