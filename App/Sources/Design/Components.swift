import SwiftUI

struct SectionLabel: View {
    @Environment(\.palette) private var palette
    let text: String
    var count: Int?

    var body: some View {
        HStack(spacing: 8) {
            Text(text).chickenEyebrow(palette)
            if let count {
                Text("· \(count)").chickenEyebrow(palette, color: palette.faint)
            }
        }
    }
}

/// Hairline progress meter used on tiles, cards, and the reader scrubber.
struct ProgressLine: View {
    @Environment(\.palette) private var palette
    let progress: Double
    var height: CGFloat = 2
    var fill: Color?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.surfaceAlt)
                Capsule()
                    .fill(fill ?? palette.ribbon)
                    .frame(width: max(0, geometry.size.width * min(max(progress, 0), 1)))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((progress * 100).rounded())) percent")
    }
}

/// The house lockup: the icon's hen-and-book on its soot tile, then the
/// name set in Superclarendon.
struct BrandLockup: View {
    @Environment(\.palette) private var palette
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: size * 0.38) {
            BrandBadge(size: size * 1.18)
            Text("Chicken")
                .font(.chickenDisplay(size, weight: .bold))
                .tracking(-0.2)
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
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}

/// A floating Liquid Glass capsule for controls that sit over reading content.
struct GlassCapsule<Content: View>: View {
    var padding: EdgeInsets = EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .glassEffect(.regular, in: .capsule)
    }
}

/// Primary call to action: tinted, prominent glass in the theme's ink color.
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
            .font(.chickenUI(14, weight: .medium))
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
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(palette.background)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(palette.text.opacity(hovering ? 0.88 : 1)))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .contentShape(Capsule())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
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
            .font(.chickenUI(13, weight: .medium))
            .foregroundStyle(palette.text)
        }
        #if os(macOS)
        // Glass buttons pick up the accent fill in active Mac windows, which
        // hides ink-colored labels; a hairline capsule reads in any state.
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
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(palette.text.opacity(hovering ? 0.06 : 0)))
            .overlay(Capsule().strokeBorder(palette.borderStrong, lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
            .contentShape(Capsule())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
    }
}
#endif

extension Date {
    var shortRelativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
