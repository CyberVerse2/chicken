import SwiftUI

/// Scaffold for Chicken's secondary screens (Settings, Find Books, panels):
/// a serif title, an optional line of explanation, and themed sections.
/// Keeps them in the same visual language as the library instead of stock
/// grouped lists.
struct ChickenPage<Content: View>: View {
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.chickenDisplay(sizeClass == .compact ? 32 : 38))
                        .tracking(-0.6)
                        .foregroundStyle(palette.text)
                    if let subtitle {
                        Text(subtitle)
                            .font(.chickenSerif(16, italic: true))
                            .foregroundStyle(palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                content
            }
            .padding(.horizontal, sizeClass == .compact ? 20 : 32)
            .padding(.top, 8)
            .padding(.bottom, 48)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .background(palette.background.ignoresSafeArea())
    }
}

/// Top of a main page: a small-caps eyebrow, the title in the display
/// face, and an optional italic line.
struct PageHeader: View {
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass
    var eyebrow: String?
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let eyebrow {
                Text(eyebrow).chickenEyebrow(palette)
            }
            Text(title)
                .font(.chickenDisplay(sizeClass == .compact ? 38 : 52))
                .tracking(sizeClass == .compact ? -0.8 : -1.2)
                .foregroundStyle(palette.text)
            if let subtitle {
                Text(subtitle)
                    .font(.chickenSerif(sizeClass == .compact ? 16 : 18, italic: true))
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A labelled group: small-caps eyebrow, a solid surface card, and an
/// optional italic footnote.
struct ChickenSection<Content: View, Accessory: View>: View {
    @Environment(\.palette) private var palette
    let title: String
    var footer: String?
    var count: Int?
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    init(
        _ title: String,
        count: Int? = nil,
        footer: String? = nil,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.count = count
        self.footer = footer
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: title, count: count)
                Spacer(minLength: 8)
                accessory
            }
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(palette.surface)
                    .stroke(palette.border, lineWidth: 0.5)
            )
            if let footer {
                Text(footer)
                    .font(.chickenSerif(12, italic: true))
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// One row inside a `ChickenSection`, with a hairline between rows.
struct ChickenRow<Content: View>: View {
    @Environment(\.palette) private var palette
    var isLast = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !isLast {
                Rectangle().fill(palette.border).frame(height: 0.5).padding(.leading, 18)
            }
        }
    }
}

/// A pair of glass +/− buttons.
struct GlassStepper: View {
    let label: String
    let canDecrease: Bool
    let canIncrease: Bool
    let decrease: () -> Void
    let increase: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                Button("Decrease \(label)", systemImage: "minus", action: decrease)
                    .disabled(!canDecrease)
                Button("Increase \(label)", systemImage: "plus", action: increase)
                    .disabled(!canIncrease)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonRepeatBehavior(.enabled)
        }
    }
}

/// Large tappable previews of the three reading themes.
struct ThemeSwatchPicker: View {
    @Environment(LibraryStore.self) private var library
    var compact = false

    var body: some View {
        HStack(spacing: 10) {
            ForEach(ReadingTheme.allCases) { theme in
                let swatch = theme.palette
                let selected = library.preferences.theme == theme
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { library.preferences.theme = theme }
                } label: {
                    VStack(alignment: .leading, spacing: compact ? 4 : 8) {
                        Text("Aa")
                            .font(.chickenDisplay(compact ? 20 : 26))
                        HStack(spacing: 5) {
                            Capsule().fill(swatch.ribbon).frame(width: 3, height: 10)
                            Text(theme.label)
                                .font(.chickenSerif(12.5, italic: true))
                                .foregroundStyle(swatch.muted)
                        }
                    }
                    .foregroundStyle(swatch.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(compact ? 12 : 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(swatch.background)
                            .stroke(selected ? swatch.ribbon : swatch.border, lineWidth: selected ? 2 : 0.5)
                    )
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(swatch.ribbon)
                                .padding(10)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(theme.label) theme")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// Glass "Done" used by sheets on iPhone and iPad.
struct SheetDoneButton: ToolbarContent {
    let action: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done", systemImage: "checkmark", action: action)
        }
    }
}

extension View {
    /// Pages draw their own serif heading, so the system title is only used
    /// for the window title on the Mac and never shown as a large title.
    func pageTitle(_ title: String) -> some View {
        navigationTitle(title)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar(removing: .title)
    }
}
