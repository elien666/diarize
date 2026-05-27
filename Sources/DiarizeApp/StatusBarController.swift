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
    // Shim that bridges NSStatusBarButton target/action to a Swift closure,
    // avoiding @MainActor isolation issues with #selector.
    private let actionShim = ActionShim()

    private weak var mainWindow: NSWindow?

    init(library: LibraryViewModel, window: NSWindow) {
        self.mainWindow = window

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon(isRecording: false)

        actionShim.handler = { [weak self] in self?.handleClick() }
        statusItem.button?.action = #selector(ActionShim.fire)
        statusItem.button?.target = actionShim
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

    private func handleClick() {
        guard let window = mainWindow else { return }
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

// NSObject subclass so #selector works without @objc on a @MainActor type.
private final class ActionShim: NSObject {
    var handler: (() -> Void)?
    @objc func fire() { handler?() }
}
