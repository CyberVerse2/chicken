#if os(macOS)
import AppKit
import ObjectiveC
import SwiftUI

/// The Mac's book card, as in Books on the Mac: a large card over the
/// blurred window, with the books before and after it standing smaller at
/// either side. Click one and it slides into the middle; ← and → do the
/// same, Return reads, Escape closes.
struct MacBookCard: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.openBook) private var openBook
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool

    /// Neighbours stand this much smaller than the card in the middle.
    private static let neighbourScale: CGFloat = 0.86
    /// Space between a neighbour and the card in the middle.
    private static let gap: CGFloat = 26
    /// How much of each neighbour shows at the window's edge.
    private static let peek: CGFloat = 120

    private var sequence: [UUID] {
        guard let id = router.detailBookID else { return [] }
        return router.detailSequence.contains(id) ? router.detailSequence : [id]
    }

    private var index: Int? {
        router.detailBookID.flatMap { sequence.firstIndex(of: $0) }
    }

    var body: some View {
        if let index {
            GeometryReader { geometry in
                let cardWidth = min(geometry.size.width - 2 * (Self.gap + Self.peek), 900)
                ZStack {
                    // The window blurs away behind the cards, as in Books.
                    Rectangle()
                        .fill(.regularMaterial)
                        .overlay(Color.black.opacity(0.25))
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture(perform: close)

                    // The card in the middle and up to two books either side,
                    // each keyed by its book so a step slides them all along.
                    ForEach(visibleRange(around: index), id: \.self) { position in
                        let id = sequence[position]
                        let offset = position - index
                        card(id, offset: offset, width: cardWidth)
                            .frame(width: cardWidth)
                            .frame(maxHeight: .infinity)
                            .padding(.vertical, 28)
                            .scaleEffect(offset == 0 ? 1 : Self.neighbourScale)
                            .rotation3DEffect(
                                .degrees(reduceMotion ? 0 : Double(-offset.signum()) * 7),
                                axis: (x: 0, y: 1, z: 0),
                                perspective: 0.5
                            )
                            .offset(x: xOffset(for: offset, cardWidth: cardWidth))
                            .zIndex(offset == 0 ? 2 : (abs(offset) == 1 ? 1 : 0))
                            .opacity(abs(offset) > 1 ? 0 : 1)
                            .transition(.opacity)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onAppear { focused = true }
            .onMoveCommand { move in
                switch move {
                case .left: step(-1)
                case .right: step(1)
                default: break
                }
            }
            .onKeyPress(.return) {
                if let id = router.detailBookID { openBook(id) }
                return .handled
            }
            .onExitCommand(perform: close)
            .transition(.opacity)
        }
    }

    /// The card at `offset` from the middle. Only the middle one is live;
    /// a neighbour is a picture of its book that brings it to the middle.
    @ViewBuilder
    private func card(_ id: UUID, offset: Int, width: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        BookDetailView(bookID: id, wide: true)
            .overlay(alignment: .topLeading) {
                if offset == 0 {
                    Button("Close", systemImage: "xmark", action: close)
                        .labelStyle(.iconOnly)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.hex(0xF7F1E6))
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .controlSize(.extraLarge)
                        .padding(18)
                        .transition(.opacity)
                }
            }
            .allowsHitTesting(offset == 0)
            .overlay {
                if offset != 0 {
                    NeighbourCover(label: offset < 0 ? "Previous book" : "Next book") { step(offset) }
                }
            }
            .clipShape(shape)
            .shadow(color: .black.opacity(offset == 0 ? 0.35 : 0.25), radius: offset == 0 ? 30 : 18, y: 12)
    }

    /// Empty when the sequence has shrunk under the card (a book removed
    /// here or on another device), rather than an invalid range.
    private func visibleRange(around index: Int) -> [Int] {
        let lower = max(0, index - 2)
        let upper = min(sequence.count - 1, index + 2)
        return lower <= upper ? Array(lower...upper) : []
    }

    /// Where a card sits: neighbours just clear the middle card by `gap`.
    private func xOffset(for offset: Int, cardWidth: CGFloat) -> CGFloat {
        guard offset != 0 else { return 0 }
        let step = cardWidth / 2 + Self.gap + cardWidth * Self.neighbourScale / 2
        let further = CGFloat(abs(offset) - 1) * (cardWidth * Self.neighbourScale + Self.gap)
        return CGFloat(offset.signum()) * (step + further)
    }

    private func step(_ offset: Int) {
        guard let index, sequence.indices.contains(index + offset) else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.45)) {
            router.detailBookID = sequence[index + offset]
        }
    }

    private func close() {
        withAnimation(.smooth(duration: 0.22)) { router.detailBookID = nil }
    }
}

/// Over a neighbouring card: dims it a little, brightens on hover, and
/// brings its book to the middle when clicked.
private struct NeighbourCover: View {
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Color.black.opacity(hovering ? 0.08 : 0.28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .accessibilityLabel(label)
    }
}

// MARK: - Scrollbars

/// Chicken's scrollbars are the thin overlay kind that appear only while
/// scrolling, whatever mouse is attached. With a mouse, macOS otherwise draws
/// full-width bars on every page and panel, which look heavy here. SwiftUI's
/// scroll views take their style from `NSScroller`, so the class's preferred
/// style is answered once, app-wide.
enum OverlayScrollbars {
    static func install() {
        guard
            let original = class_getClassMethod(NSScroller.self, #selector(getter: NSScroller.preferredScrollerStyle)),
            let replacement = class_getClassMethod(NSScroller.self, #selector(NSScroller.chicken_preferredScrollerStyle))
        else { return }
        method_exchangeImplementations(original, replacement)
    }
}

extension NSScroller {
    @objc dynamic class func chicken_preferredScrollerStyle() -> NSScroller.Style { .overlay }
}
#endif
