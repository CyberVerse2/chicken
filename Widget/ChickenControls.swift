import AppIntents
import ChickenKit
import SwiftUI
import WidgetKit

/// "Continue Reading" for Control Center, the Lock Screen, and the Action
/// button: one press back to the page you were on.
struct ContinueReadingControl: ControlWidget {
    static let kind = "ChickenContinueReadingControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenURLIntent(ChickenLink.continueReading)) {
                Label("Continue Reading", systemImage: "book.pages")
            }
        }
        .displayName("Continue Reading")
        .description("Open the book you're reading at your place.")
    }
}

/// Chicken's egg, for small places in the extension.
struct WidgetEgg: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 48
        for index in 0...steps {
            let t = Double(index) / Double(steps) * 2 * .pi
            let y = -cos(t)
            let x = sin(t) * (1 + 0.16 * y) / 1.16
            let point = CGPoint(x: rect.midX + x * rect.width / 2, y: rect.midY + y * rect.height / 2)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}
