import SwiftUI

struct SectionLabel: View {
    @Environment(\.palette) private var palette
    let text: String
    var count: Int?

    var body: some View {
        HStack(spacing: 6) {
            Text(text).chickenEyebrow(palette)
            if let count {
                Text("\(count)")
                    .font(.chickenMono(11, weight: .semibold))
                    .foregroundStyle(palette.faint)
            }
        }
    }
}

/// Hairline progress meter used on tiles, cards, and the reader scrubber.
struct ProgressLine: View {
    @Environment(\.palette) private var palette
    let progress: Double
    var height: CGFloat = 3
    var fill: Color?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.surfaceAlt)
                if progress > 0 {
                    Capsule()
                        .fill(fill ?? palette.ribbon)
                        .frame(width: max(height, geometry.size.width * min(max(progress, 0), 1)))
                }
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((progress * 100).rounded())) percent")
    }
}

struct BrandLockup: View {
    @Environment(\.palette) private var palette
    var size: CGFloat = 21

    var body: some View {
        HStack(spacing: size * 0.4) {
            BrandBadge(size: size * 1.18)
            Text("Chicken")
                .font(.chickenDisplay(size, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.text)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chicken")
    }
}

struct BrandBadge: View {
    var size: CGFloat = 26

    var body: some View {
        Image("BrandBadge")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}

struct TactilePressStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.78 : 1)
            .animation(ChickenMotion.press, value: configuration.isPressed)
    }
}

extension View {
    func chickenGlass<S: InsettableShape>(
        in shape: S,
        isLit: Bool = false,
        interactive: Bool = false
    ) -> some View {
        modifier(ChickenGlassModifier(shape: shape, isLit: isLit, interactive: interactive))
    }

    func chickenGlassPill(isSelected: Bool, interactive: Bool = true) -> some View {
        modifier(ChickenGlassPillModifier(isSelected: isSelected, interactive: interactive))
    }

    @ViewBuilder
    func chickenSwipeActionsContainer() -> some View {
        if #available(iOS 27.0, macOS 27.0, *) {
            swipeActionsContainer()
        } else {
            self
        }
    }
}

private struct ChickenGlassModifier<S: InsettableShape>: ViewModifier {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: S
    var isLit = false
    var interactive = false

    private var showsGlass: Bool { !reduceTransparency && !isLit }

    func body(content: Content) -> some View {
        content
            .background {
                shape
                    .fill(isLit ? palette.text : palette.surfaceAlt)
                    .opacity(showsGlass ? 0 : 1)
            }
            .overlay {
                shape.strokeBorder(
                    palette.borderStrong.opacity(reduceTransparency && !isLit ? 1 : 0),
                    lineWidth: 0.5
                )
            }
            .glassEffect(
                showsGlass
                    ? .regular
                        .tint(palette.isDark ? .black.opacity(0.26) : .clear)
                        .interactive(interactive)
                    : .identity,
                in: shape
            )
    }
}

private struct ChickenGlassPillModifier: ViewModifier {
    @Environment(\.palette) private var palette
    let isSelected: Bool
    var interactive = true

    func body(content: Content) -> some View {
        content
            .foregroundStyle(isSelected ? palette.background : palette.text)
            .chickenGlass(in: Capsule(), isLit: isSelected, interactive: interactive)
            .contentShape(Capsule())
    }
}

struct ChickenStat: Identifiable, Hashable {
    let label: String
    let value: String
    var isNumeric = true
    var isAccent = false

    var id: String { label }
}

struct ChickenStatStrip: View {
    @Environment(\.palette) private var palette
    let stats: [ChickenStat]

    var body: some View {
        if !stats.isEmpty {
            HStack(spacing: 0) {
                ForEach(Array(stats.enumerated()), id: \.element.id) { index, stat in
                    if index > 0 {
                        Rectangle()
                            .fill(palette.borderStrong)
                            .frame(width: 0.5, height: 26)
                    }
                    VStack(spacing: 3) {
                        Text(stat.value)
                            .font(stat.isNumeric ? .chickenMono(15, weight: .semibold) : .chickenUI(14, weight: .semibold))
                            .foregroundStyle(stat.isAccent ? palette.ribbon : palette.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text(stat.label)
                            .font(.chickenUI(11))
                            .foregroundStyle(palette.muted)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(stat.label)
                    .accessibilityValue(stat.value)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(palette.surface.opacity(palette.isDark ? 0.65 : 0.72))
            )
        }
    }
}

struct CircularGlassButton: View {
    @Environment(\.palette) private var palette
    let title: String
    let systemImage: String
    var diameter: CGFloat = 44
    var iconSize: CGFloat?
    var foreground: Color?
    let action: () -> Void

    private var resolvedIconSize: CGFloat {
        iconSize ?? (diameter * 0.40).rounded()
    }

    var body: some View {
        #if os(macOS)
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: resolvedIconSize, weight: .semibold))
                .foregroundStyle(foreground ?? palette.text)
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
        }
        .buttonStyle(TactilePressStyle(scale: 0.94))
        .chickenGlass(in: Circle(), interactive: true)
        .accessibilityLabel(title)
        #else
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: resolvedIconSize, weight: .semibold))
                .foregroundStyle(foreground ?? palette.text)
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .chickenGlass(in: Circle(), interactive: true)
        .accessibilityLabel(title)
        #endif
    }
}

struct PrimaryHeroButton: View {
    @Environment(\.palette) private var palette
    let title: String
    var systemImage: String?
    var height: CGFloat = 50
    let action: () -> Void

    var body: some View {
        #if os(macOS)
        Button(action: action) {
            label
                .frame(maxWidth: .infinity)
                .frame(height: height)
        }
        .buttonStyle(InkCapsuleButtonStyle(palette: palette, verticalPadding: 0))
        #else
        Button(action: action) {
            label
                .frame(maxWidth: .infinity)
                .frame(height: height - 14)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .tint(palette.text)
        .foregroundStyle(palette.background)
        #endif
    }

    private var label: some View {
        HStack(spacing: 8) {
            Text(title)
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
            }
        }
        .font(.chickenUI(16, weight: .semibold))
    }
}

struct PrimaryActionButton: View {
    @Environment(\.palette) private var palette
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 12, weight: .semibold))
                }
            }
            .font(.chickenUI(14, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
        }
        .inkProminentButton()
    }
}

extension View {
    /// The filled, theme-ink button used for primary actions. On the Mac a
    /// tinted glass button loses its tint when the window is inactive, which
    /// leaves background-colored text on a pale capsule, so the Mac draws
    /// its own solid capsule instead.
    func inkProminentButton() -> some View {
        modifier(InkProminentButton())
    }
}

private struct InkProminentButton: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        #if os(macOS)
        content.buttonStyle(InkCapsuleButtonStyle(palette: palette))
        #else
        content
            .buttonStyle(.glassProminent)
            .tint(palette.text)
            .foregroundStyle(palette.background)
        #endif
    }
}

#if os(macOS)
private struct InkCapsuleButtonStyle: ButtonStyle {
    let palette: ReaderPalette
    var verticalPadding: CGFloat = 8
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        let baseOpacity: Double = appearsActive ? (hovering ? 0.88 : 1) : 0.65
        configuration.label
            .foregroundStyle(palette.background)
            .padding(.horizontal, 16)
            .padding(.vertical, verticalPadding)
            .background(Capsule().fill(palette.text.opacity(baseOpacity)))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.4)
            .contentShape(Capsule())
            .onHover { hovering = $0 }
            .animation(ChickenMotion.press, value: hovering)
            .animation(ChickenMotion.press, value: configuration.isPressed)
    }
}
#endif

struct SecondaryActionButton: View {
    @Environment(\.palette) private var palette
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                if let systemImage { Image(systemName: systemImage) }
            }
            .labelStyle(.titleAndIcon)
            .font(.chickenUI(13.5, weight: .medium))
            .foregroundStyle(palette.text)
        }
        #if os(macOS)
        .buttonStyle(InkOutlineButtonStyle(palette: palette))
        #else
        .buttonStyle(.glass)
        #endif
    }
}

#if os(macOS)
private struct InkOutlineButtonStyle: ButtonStyle {
    let palette: ReaderPalette
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(palette.text.opacity(hovering ? 0.06 : 0)))
            .overlay(Capsule().strokeBorder(palette.borderStrong.opacity(appearsActive ? 1 : 0.6), lineWidth: 1))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : (appearsActive ? 1 : 0.75)) : 0.4)
            .contentShape(Capsule())
            .onHover { hovering = $0 }
            .animation(ChickenMotion.press, value: hovering)
            .animation(ChickenMotion.press, value: configuration.isPressed)
    }
}
#endif

extension Date {
    var shortRelativeDescription: String {
        formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
    }
}
