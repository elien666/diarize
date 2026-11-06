import SwiftUI

/// Lets AppKit code (status item) reopen the single main SwiftUI window
/// after it was closed.
@MainActor
enum MainWindow {
    static let id = "main"
    fileprivate static var openAction: OpenWindowAction?

    static func open() {
        openAction?(id: id)
    }
}

struct MainWindowOpenerBridge: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear { MainWindow.openAction = openWindow }
    }
}
