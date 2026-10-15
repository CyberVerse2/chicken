#if os(iOS)
import ActivityKit
import ChickenKit
import SwiftUI
import UIKit
import WidgetKit

/// The reading session in the Dynamic Island and on the Lock Screen: the
/// book you're in, where you are in it, and today's minutes against your
/// goal. Tapping anywhere goes straight back to the page.
struct ReadingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReadingActivityAttributes.self) { context in
            LockScreenBanner(context: context)
                .activityBackgroundTint(LiveColors.banner(context.attributes))
                .activitySystemActionForegroundColor(LiveColors.text)
                .widgetURL(ChickenLink.book(context.attributes.bookID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LiveCover(attributes: context.attributes)
                        .frame(width: 42, height: 63)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    GoalRing(state: context.state, size: 44, lineWidth: 4, showsMinutes: true)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.attributes.title)
                            .font(.custom("Superclarendon-Regular", size: 16))
                            .foregroundStyle(LiveColors.text)
                            .lineLimit(1)
                        Text(context.state.chapter ?? context.attributes.author)
                            .font(.custom("IowanOldStyle-Italic", size: 13))
                            .foregroundStyle(LiveColors.text.opacity(0.7))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        ProgressBar(progress: context.state.progress)
                        HStack {
                            if context.state.isReadingAloud {
                                Label("Reading aloud", systemImage: "waveform")
                                    .symbolEffect(.variableColor.iterative)
                            } else {
                                Text("\(Int((context.state.progress * 100).rounded()))% read")
                            }
                            Spacer()
                            Link(destination: ChickenLink.book(context.attributes.bookID)) {
                                Label("Continue", systemImage: "arrow.right")
                                    .labelStyle(.titleAndIcon)
                                    .font(.system(size: 13, weight: .semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(LiveColors.text))
                                    .foregroundStyle(Color.black.opacity(0.85))
                            }
                        }
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(LiveColors.text.opacity(0.75))
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                }
            } compactLeading: {
                LiveCover(attributes: context.attributes)
                    .frame(width: 17, height: 25)
            } compactTrailing: {
                if context.state.isReadingAloud {
                    Image(systemName: "waveform")
                        .foregroundStyle(LiveColors.ribbon)
                        .symbolEffect(.variableColor.iterative)
                } else {
                    GoalRing(state: context.state, size: 20, lineWidth: 2.5, showsMinutes: false)
                }
            } minimal: {
                GoalRing(state: context.state, size: 20, lineWidth: 2.5, showsMinutes: false)
            }
            .keylineTint(LiveColors.ribbon)
            .widgetURL(ChickenLink.book(context.attributes.bookID))
        }
    }
}

/// The Lock Screen banner, in the book's own colour.
private struct LockScreenBanner: View {
    let context: ActivityViewContext<ReadingActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            LiveCover(attributes: context.attributes)
                .frame(width: 48, height: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.title)
                    .font(.custom("Superclarendon-Regular", size: 17))
                    .foregroundStyle(LiveColors.text)
                    .lineLimit(1)
                Group {
                    if context.state.isReadingAloud {
                        Label("Reading aloud", systemImage: "waveform")
                    } else {
                        Text(context.state.chapter ?? context.attributes.author)
                    }
                }
                .font(.custom("IowanOldStyle-Italic", size: 13))
                .foregroundStyle(LiveColors.text.opacity(0.75))
                .lineLimit(1)
                Spacer(minLength: 4)
                HStack(spacing: 8) {
                    ProgressBar(progress: context.state.progress)
                    Text("\(Int((context.state.progress * 100).rounded()))%")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(LiveColors.text.opacity(0.8))
                }
            }
            Spacer(minLength: 0)
            GoalRing(state: context.state, size: 52, lineWidth: 4.5, showsMinutes: true)
        }
        .padding(16)
    }
}

/// Today's minutes against the daily goal, as a ribbon-coloured ring.
private struct GoalRing: View {
    let state: ReadingActivityAttributes.ContentState
    let size: CGFloat
    let lineWidth: CGFloat
    let showsMinutes: Bool

    var body: some View {
        ZStack {
            Circle().stroke(LiveColors.text.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.02, state.goalFraction))
                .stroke(LiveColors.ribbon, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if showsMinutes {
                VStack(spacing: -1) {
                    Text("\(state.minutesToday)")
                        .font(.custom("Superclarendon-Regular", size: size * 0.32))
                        .foregroundStyle(LiveColors.text)
                    Text("min")
                        .font(.system(size: size * 0.16, weight: .medium))
                        .foregroundStyle(LiveColors.text.opacity(0.6))
                }
                .monospacedDigit()
            } else if state.goalFraction >= 1 {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(LiveColors.ribbon)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(state.minutesToday) of \(state.goalMinutes) minutes read today")
    }
}

private struct ProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(LiveColors.text.opacity(0.2))
                Capsule().fill(LiveColors.ribbon)
                    .frame(width: max(3, geometry.size.width * min(max(progress, 0), 1)))
            }
        }
        .frame(height: 3)
    }
}

/// The book's cover from the shared container, or its cloth colour.
private struct LiveCover: View {
    let attributes: ReadingActivityAttributes

    var body: some View {
        let tint = WidgetColors.coverTint(attributes.coverTintIndex)
        Group {
            if let url = ReadingActivityAttributes.coverURL(for: attributes.bookID),
               let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    tint.cloth
                    WidgetEgg()
                        .stroke(tint.ink.opacity(0.7), lineWidth: 1)
                        .frame(width: 8, height: 10)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .accessibilityHidden(true)
    }
}

private enum LiveColors {
    static let text = Color(red: 0.97, green: 0.945, blue: 0.9)
    static let ribbon = Color(red: 0.8, green: 0.553, blue: 0.27)

    /// The Lock Screen banner: the book's cloth colour, deepened so light
    /// text reads on it in any wallpaper.
    static func banner(_ attributes: ReadingActivityAttributes) -> Color {
        WidgetColors.coverTint(attributes.coverTintIndex).cloth.mix(with: .black, by: 0.45)
    }
}
#endif
