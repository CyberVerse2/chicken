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
                            .font(.system(size: 15.5, weight: .semibold))
                            .tracking(-0.25)
                            .foregroundStyle(LiveColors.text)
                            .lineLimit(1)
                        Text(context.state.chapter ?? context.attributes.author)
                            .font(.system(size: 12.5))
                            .foregroundStyle(LiveColors.text.opacity(0.7))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        ProgressBar(progress: context.state.progress)
                        HStack {
                            if context.state.isReadingAloud {
                                Label("Reading aloud", systemImage: "waveform")
                                    .symbolEffect(.variableColor.iterative)
                                Spacer()
                                Text("\(Int((context.state.progress * 100).rounded()))%")
                            } else {
                                Text("\(Int((context.state.progress * 100).rounded()))% read")
                                Spacer()
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

private struct LockScreenBanner: View {
    let context: ActivityViewContext<ReadingActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            LiveCover(attributes: context.attributes)
                .frame(width: 48, height: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.title)
                    .font(.system(size: 16.5, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(LiveColors.text)
                    .lineLimit(1)
                Group {
                    if context.state.isReadingAloud {
                        Label("Reading aloud", systemImage: "waveform")
                    } else {
                        Text(context.state.chapter ?? context.attributes.author)
                    }
                }
                .font(.system(size: 12.5))
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

private struct GoalRing: View {
    let state: ReadingActivityAttributes.ContentState
    let size: CGFloat
    let lineWidth: CGFloat
    let showsMinutes: Bool

    var body: some View {
        ZStack {
            Circle().stroke(LiveColors.text.opacity(0.2), lineWidth: lineWidth)
            if state.minutesToday > 0 {
                Circle()
                    .trim(from: 0, to: max(0.03, state.goalFraction))
                    .stroke(LiveColors.ribbon, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            if showsMinutes {
                VStack(spacing: -1) {
                    Text("\(state.minutesToday)")
                        .font(.system(size: size * 0.32, weight: .bold))
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
                if progress > 0 {
                    Capsule().fill(LiveColors.ribbon)
                        .frame(width: max(3, geometry.size.width * min(max(progress, 0), 1)))
                }
            }
        }
        .frame(height: 3)
    }
}

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
    static let text = WidgetColors(theme: "ink").text
    static let ribbon = WidgetColors(theme: "ink").ribbon

    static func banner(_ attributes: ReadingActivityAttributes) -> Color {
        WidgetColors.coverTint(attributes.coverTintIndex).cloth.mix(with: .black, by: 0.45)
    }
}
#endif
