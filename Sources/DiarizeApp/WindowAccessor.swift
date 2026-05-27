import AppKit
import SwiftUI

extension View {
    /// Calls `handler` once with the `NSWindow` that hosts this view,
    /// as soon as the view appears on screen.
    func withHostingWindow(_ handler: @escaping (NSWindow?) -> Void) -> some View {
        background(HostingWindowFinder(handler: handler))
    }
}

private struct HostingWindowFinder: NSViewRepresentable {
    let handler: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Defer to next runloop tick so the window is fully set up.
        DispatchQueue.main.async { [weak view] in
            self.handler(view?.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
