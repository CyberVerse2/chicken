import SwiftUI

#if os(macOS)
import AppKit
import ObjectiveC

typealias PlatformView = NSView
typealias PlatformColor = NSColor
typealias PlatformFont = NSFont
typealias PlatformImage = NSImage
typealias PlatformViewRepresentableBase = NSViewRepresentable
#else
import UIKit

typealias PlatformView = UIView
typealias PlatformColor = UIColor
typealias PlatformFont = UIFont
typealias PlatformImage = UIImage
typealias PlatformViewRepresentableBase = UIViewRepresentable
#endif

/// One representable definition for AppKit and UIKit. Conformers implement
/// `makeView` / `updateView` / `dismantleView`; the platform-specific
/// requirements forward to them.
protocol PlatformViewRepresentable: PlatformViewRepresentableBase {
    associatedtype ViewType: PlatformView

    func makeView(context: Context) -> ViewType
    func updateView(_ view: ViewType, context: Context)
    static func dismantleView(_ view: ViewType, coordinator: Coordinator)
}

extension PlatformViewRepresentable {
    static func dismantleView(_ view: ViewType, coordinator: Coordinator) {}

    #if os(macOS)
    func makeNSView(context: Context) -> ViewType { makeView(context: context) }
    func updateNSView(_ nsView: ViewType, context: Context) { updateView(nsView, context: context) }
    static func dismantleNSView(_ nsView: ViewType, coordinator: Coordinator) { dismantleView(nsView, coordinator: coordinator) }
    #else
    func makeUIView(context: Context) -> ViewType { makeView(context: context) }
    func updateUIView(_ uiView: ViewType, context: Context) { updateView(uiView, context: context) }
    static func dismantleUIView(_ uiView: ViewType, coordinator: Coordinator) { dismantleView(uiView, coordinator: coordinator) }
    #endif
}

extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}

extension PlatformColor {
    /// Builds a platform color from the same hex values the SwiftUI palette uses.
    nonisolated static func hex(_ value: UInt32, alpha: CGFloat = 1) -> PlatformColor {
        PlatformColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha
        )
    }
}

enum Platform {
    static var isMac: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    static var deviceName: String {
        #if os(macOS)
        "Mac"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }
}

enum Haptics {
    enum Weight {
        case light
        case medium
        case rigid
    }

    static func selection() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #else
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
        #endif
    }

    static func impact(_ weight: Weight = .light) {
        #if os(macOS)
        let pattern: NSHapticFeedbackManager.FeedbackPattern = weight == .light ? .alignment : .levelChange
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
        #else
        let style: UIImpactFeedbackGenerator.FeedbackStyle = switch weight {
        case .light: .light
        case .medium: .medium
        case .rigid: .rigid
        }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
        #endif
    }

    static func success() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        #else
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }
}

#if os(macOS)
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
