import AppKit
import Combine

/// Manages the menu-bar status item and stealth mode.
///
/// Stealth mode hides the main window so the app is only accessible via the
/// status-bar icon — useful when others can see your screen. The icon shows
/// a filled circle while recording and an empty circle otherwise, which reads
/// as a generic system utility rather than an active recorder.
@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private var cancellables: Set<AnyCancellable> = []

    init(library: LibraryViewModel) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon(isRecording: false)

        statusItem.button?.action = #selector(handleClick)
        statusItem.button?.target = self
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        library.$activeRecordingId
            .receive(on: RunLoop.main)
            .map { $0 != nil }
            .sink { [weak self] isRecording in
                self?.updateIcon(isRecording: isRecording)
            }
            .store(in: &cancellables)
    }

    private func updateIcon(isRecording: Bool) {
        let name = isRecording ? "circle.fill" : "circle"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    @objc private func handleClick() {
        guard let window = NSApplication.shared.windows.first(where: { $0.title == "diarize" || $0.identifier?.rawValue == "diarize" }) ?? NSApplication.shared.windows.first else { return }
        if window.isVisible {
            window.orderOut(nil)
            NSApplication.shared.setActivationPolicy(.accessory)
        } else {
            NSApplication.shared.setActivationPolicy(.regular)
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
