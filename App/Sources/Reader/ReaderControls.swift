import ChickenKit
import SwiftUI

struct ReaderProgressBar: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: ReaderModel
    let compact: Bool
    @State private var dragProgress: Double?
    @State private var lastSeekTime: Date = .distantPast

    private var shown: Double { min(1, max(0, dragProgress ?? model.overallProgress)) }

    var body: some View {
        HStack(spacing: 14) {
            Text("\(Int((shown * 100).rounded()))%")
                .font(.chickenMono(11, weight: .medium))
                .foregroundStyle(palette.muted)
                .frame(width: 38, alignment: .leading)
                .contentTransition(.numericText())

            scrubber

            VStack(alignment: .trailing, spacing: 2) {
                Text(model.pageReadout)
                    .font(model.isOnLastPage ? .chickenSerif(12, italic: true) : .chickenMono(11))
                    .foregroundStyle(palette.muted)
                if !compact, !model.timeReadout.isEmpty {
                    Text(model.timeReadout)
                        .font(.chickenMono(10))
                        .foregroundStyle(palette.faint)
                        .lineLimit(1)
                }
            }
            .monospacedDigit()
            .fixedSize()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, compact ? 8 : 10)
        .frame(maxWidth: 820)
        .glassEffect(.regular, in: .capsule)
        .animation(reduceMotion || dragProgress != nil ? nil : ChickenMotion.micro, value: shown)
    }

    private var scrubber: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let isDragging = dragProgress != nil
            let thumbSize: CGFloat = isDragging ? 14 : 10
            let trackOffset = (width - thumbSize) * shown
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(0..<18, id: \.self) { index in
                        let fraction = Double(index) / 17.0
                        Rectangle()
                            .fill(fraction <= shown ? palette.ribbon.opacity(0.45) : palette.text.opacity(0.12))
                            .frame(width: 1, height: index % 3 == 0 ? 7 : 4)
                        if index < 17 { Spacer(minLength: 0) }
                    }
                }
                .offset(y: 7)
                .allowsHitTesting(false)

                Capsule().fill(palette.text.opacity(0.14)).frame(height: 3)
                Capsule().fill(palette.ribbon).frame(width: max(thumbSize / 2, width * shown), height: 3)
                Circle()
                    .fill(palette.ribbon)
                    .overlay(Circle().stroke(palette.background.opacity(0.85), lineWidth: 1.5))
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: trackOffset)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragProgress == nil { Haptics.selection() }
                        let progress = min(1, max(0, value.location.x / width))
                        dragProgress = progress
                        let now = Date()
                        if now.timeIntervalSince(lastSeekTime) >= 0.08 {
                            lastSeekTime = now
                            model.seek(to: progress)
                        }
                    }
                    .onEnded { value in
                        let finalProgress = min(1, max(0, value.location.x / width))
                        model.seek(to: finalProgress)
                        dragProgress = nil
                        Haptics.impact(.light)
                    }
            )
        }
        .frame(height: 36)
        .accessibilityElement()
        .accessibilityLabel("Reading position")
        .accessibilityValue("\(Int((shown * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            let step = 0.02
            model.seek(to: shown + (direction == .increment ? step : -step))
        }
    }
}

struct HighlightPicker: View {
    @Environment(\.palette) private var palette
    let model: ReaderModel
    var onShareSelection: ((String) -> Void)?
    @State private var copied = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(HighlightColor.allCases) { color in
                Button {
                    model.addHighlight(color: color)
                } label: {
                    Circle()
                        .fill(color.bar)
                        .frame(width: 24, height: 24)
                        .overlay(Circle().stroke(palette.text.opacity(0.15), lineWidth: 0.5))
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .buttonStyle(TactilePressStyle())
                .accessibilityLabel("Highlight \(color.label)")
            }
            Divider().frame(height: 18).padding(.horizontal, 2)
            Button {
                if let text = model.selection?.text {
                    Clipboard.copy(text)
                    Haptics.impact(.light)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        copied = false
                    }
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(copied ? palette.ribbon : palette.muted)
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
            }
            .buttonStyle(TactilePressStyle())
            .accessibilityLabel(copied ? "Copied" : "Copy")

            if let onShareSelection, let text = model.selection?.text {
                Button {
                    onShareSelection(text)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(palette.muted)
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .buttonStyle(TactilePressStyle())
                .accessibilityLabel("Share Quote Card")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
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

struct ReaderSearchBar: View {
    @Environment(\.palette) private var palette
    @Binding var text: String
    let matchSummary: String?
    let onSearch: (_ backwards: Bool) -> Void
    let onClose: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.faint)
                .padding(.leading, 6)
            TextField("Search in book", text: $text)
                .textFieldStyle(.plain)
                .font(.chickenUI(14))
                .focused($focused)
                .onSubmit { onSearch(false) }
                .frame(minWidth: 140)
            if let matchSummary {
                Text(matchSummary)
                    .font(.chickenMono(11))
                    .foregroundStyle(palette.faint)
                    .fixedSize()
            }
            searchButton("Previous match", systemImage: "chevron.up") { onSearch(true) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            searchButton("Next match", systemImage: "chevron.down") { onSearch(false) }
                .keyboardShortcut("g")
            searchButton("Close search", systemImage: "xmark") { onClose() }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(maxWidth: 460)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 16)
        .onAppear { focused = true }
    }

    private func searchButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.muted)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(TactilePressStyle(scale: 0.92))
        .accessibilityLabel(title)
    }
}

struct TypographyPanel: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: ReaderModel
    let isCompact: Bool

    private var modes: [ReadingMode] { isCompact ? [.scroll, .paged] : ReadingMode.allCases }
    private var hasTypography: Bool { model.book.format != .pdf }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if hasTypography {
                    sample
                        .padding(.horizontal, 20)
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
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(palette.surface)
                            .stroke(palette.border, lineWidth: 0.5)
                    )
                    .padding(.horizontal, 20)
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
                    .padding(.horizontal, 20)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Theme").chickenEyebrow(palette)
                    ThemeSwatchPicker(compact: true)
                }
                .padding(.horizontal, 20)

                if model.book.format == .pdf && palette.isDark {
                    Toggle(isOn: $model.darkModePDF) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dark pages")
                                .font(.chickenUI(14, weight: .medium))
                                .foregroundStyle(palette.text)
                            Text("Invert bright PDF pages in Ink mode")
                                .font(.chickenUI(12))
                                .foregroundStyle(palette.muted)
                        }
                    }
                    .tint(palette.ribbon)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(palette.surface)
                            .stroke(palette.border, lineWidth: 0.5)
                    )
                    .padding(.horizontal, 20)
                }

                if hasTypography {
                    Button("Reset to Defaults", systemImage: "arrow.counterclockwise") {
                        Haptics.selection()
                        withAnimation(reduceMotion ? nil : ChickenMotion.snappy) { model.resetTypography() }
                    }
                    .font(.chickenUI(13, weight: .medium))
                    .foregroundStyle(palette.muted)
                    .buttonStyle(TactilePressStyle(scale: 0.96))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 36)
                    .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: isCompact ? nil : 340)
        .frame(maxWidth: isCompact ? .infinity : nil, minHeight: isCompact ? nil : 440)
        .background(palette.background.opacity(isCompact ? 1 : 0))
    }

    private var typefacePicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(ReaderTypeface.allCases) { face in
                    let selected = model.typeface == face
                    Button {
                        Haptics.selection()
                        withAnimation(reduceMotion ? nil : ChickenMotion.snappy) { model.typeface = face }
                    } label: {
                        VStack(spacing: 4) {
                            Text("Ag").font(face.font(22))
                            Text(face.label)
                                .font(.chickenUI(11, weight: selected ? .semibold : .regular))
                                .lineLimit(1)
                        }
                        .foregroundStyle(selected ? palette.text : palette.muted)
                        .frame(minWidth: 68)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(selected ? palette.surface : palette.surfaceAlt.opacity(0.6))
                                .stroke(selected ? palette.ribbon : palette.border, lineWidth: selected ? 1.5 : 0.5)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(TactilePressStyle())
                    .accessibilityLabel(face.label)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.03),
                    .init(color: .black, location: 0.93),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private var sample: some View {
        Text("Rain on the window, tea gone cold, and one more chapter before bed.")
            .font(model.typeface.font(min(model.fontSize, 22)))
            .lineSpacing(CGFloat(model.lineHeight - 1) * CGFloat(min(model.fontSize, 22)) * 0.6)
            .foregroundStyle(palette.text)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(palette.surfaceAlt.opacity(0.75))
            )
            .animation(reduceMotion ? nil : ChickenMotion.micro, value: model.fontSize)
            .animation(reduceMotion ? nil : ChickenMotion.micro, value: model.lineHeight)
            .animation(reduceMotion ? nil : ChickenMotion.micro, value: model.typeface)
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
                Text(value)
                    .font(.chickenMono(12))
                    .foregroundStyle(palette.muted)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : ChickenMotion.micro, value: value)
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
            Haptics.selection()
            withAnimation(reduceMotion ? nil : ChickenMotion.snappy) { model.readingMode = mode }
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
                    .fill(selected ? palette.surface : palette.surfaceAlt.opacity(0.6))
                    .stroke(selected ? palette.ribbon : palette.border, lineWidth: selected ? 1.5 : 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(TactilePressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
