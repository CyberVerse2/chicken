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
        .buttonStyle(.glassProminent)
        .tint(palette.text)
        .foregroundStyle(palette.background)
        #if os(macOS)
        .controlSize(.large)
        #endif
    }
}

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
        .buttonStyle(.glass)
        #if os(macOS)
        .controlSize(.large)
        #endif
    }
}

extension Date {
    var shortRelativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
