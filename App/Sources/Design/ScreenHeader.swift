import SwiftUI

struct ChickenScreenHeader<Trailing: View>: View {
    var eyebrow: String? = nil
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    init(
        eyebrow: String? = nil,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            PageHeader(eyebrow: eyebrow, title: title, subtitle: subtitle)
            Spacer(minLength: 8)
            trailing()
        }
    }
}

struct ShelfSectionHeader: View {
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass
    let title: String
    var count: Int? = nil
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.chickenDisplay(sizeClass == .compact ? 20 : 22))
                .tracking(-0.3)
                .foregroundStyle(palette.text)
            if let count {
                Text("\(count)")
                    .font(.chickenMono(11.5, weight: .medium))
                    .foregroundStyle(palette.faint)
            }
            Spacer(minLength: 8)
            if let actionLabel, let action {
                Button(action: action) {
                    HStack(spacing: 3) {
                        Text(actionLabel)
                            .font(.chickenUI(12.5, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(palette.muted)
                    .contentShape(Rectangle())
                }
                .buttonStyle(TactilePressStyle(scale: 0.96))
            }
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
