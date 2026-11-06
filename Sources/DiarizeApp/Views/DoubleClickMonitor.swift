import AppKit
import SwiftUI

/// Detects a double-click inside the view it is attached to (as a `.background`) without
/// installing a SwiftUI tap gesture. A tap gesture on a `List` row swallows or delays the
/// row's own single-click selection; this observes the click and lets it pass through.
struct DoubleClickMonitor: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.action = action
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.action = action
    }

    static func dismantleNSView(_ view: MonitorView, coordinator: ()) {
        view.stopMonitoring()
    }

    final class MonitorView: NSView {
        var action: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, event.clickCount == 2, event.window === self.window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                if self.bounds.contains(point) {
                    DispatchQueue.main.async { self.action?() }
                }
                return event
            }
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        /// Never take part in hit testing: clicks must reach the row.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
