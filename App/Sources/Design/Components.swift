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
                    .fill(fill ?? palette.muted)
                    .frame(width: max(0, geometry.size.width * min(max(progress, 0), 1)))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((progress * 100).rounded())) percent")
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
    }
}

extension Date {
    var relativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    var shortRelativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
