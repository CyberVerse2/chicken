import Observation
import SwiftUI

nonisolated struct ScrollHeaderSpot: Equatable {
    let raw: CGFloat
    let fromTop: CGFloat
}

enum ScrollHeaderPhase {
    case atTop
    case expanded
    case collapsed
}

@Observable
final class ScrollHeaderState {
    private(set) var phase: ScrollHeaderPhase = .atTop
    @ObservationIgnored private var turn: CGFloat = 0

    var isCollapsed: Bool { phase == .collapsed }

    func track(_ spot: ScrollHeaderSpot) {
        if spot.fromTop < 48 {
            phase = .atTop
            turn = spot.raw
            return
        }
        switch phase {
        case .collapsed:
            if spot.raw > turn {
                turn = spot.raw
            } else if turn - spot.raw > 12 {
                phase = .expanded
                turn = spot.raw
            }
        case .atTop, .expanded:
            if spot.raw - turn > 18 {
                phase = .collapsed
                turn = spot.raw
            } else if spot.raw < turn {
                turn = spot.raw
            }
        }
    }
}

extension View {
    func trackScrollHeader(_ state: ScrollHeaderState) -> some View {
        onScrollGeometryChange(for: ScrollHeaderSpot.self) { geometry in
            ScrollHeaderSpot(
                raw: geometry.contentOffset.y,
                fromTop: geometry.contentOffset.y + geometry.contentInsets.top
            )
        } action: { _, spot in
            state.track(spot)
        }
    }
}

struct AddBooksMenuItems: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        Button("Import Files…", systemImage: "doc.badge.plus") {
            router.showingImporter = true
        }
        Button("Add Physical Book…", systemImage: "book.closed") {
            router.presentSheet(.addPhysicalBook(scanImmediately: false))
        }
        #if os(iOS)
        Button("Scan Book Barcode…", systemImage: "barcode.viewfinder") {
            router.presentSheet(.addPhysicalBook(scanImmediately: true))
        }
        #endif
        Divider()
        Button("Find Books in Folders…", systemImage: "folder.badge.gearshape") {
            router.presentSheet(.discovery)
        }
    }
}

struct CircularGlassMenu<Content: View>: View {
    @Environment(\.palette) private var palette
    let title: String
    let systemImage: String
    var diameter: CGFloat = 38
    var iconSize: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(palette.text)
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .chickenGlass(in: Circle(), interactive: true)
        .accessibilityLabel(title)
    }
}
