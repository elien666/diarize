import AppKit
import SwiftUI
import DiarizeCore

/// Keeps the app alive (menu-bar icon, recording) when the last window closes.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Dock-icon click with no visible window brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainWindow.open() }
        return true
    }
}

@main
struct DiarizeAppMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var library = LibraryViewModel()
    @StateObject private var permissions = PermissionsManager()
    @StateObject private var autoMode = AutoModeController()
    @StateObject private var cleanup = AudioCleanupController()
    // Stored as a property so ARC keeps it alive for the lifetime of the app.
    @State private var statusBar: StatusBarController?

    init() {
        // SwiftPM executables default to background-tool (no Dock icon, no window focus).
        // Promote to a foreground app so the window appears and gets focus.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        Window("diarize", id: MainWindow.id) {
            RootView()
                .environmentObject(library)
                .environmentObject(permissions)
                .environmentObject(autoMode)
                .environmentObject(cleanup)
                .frame(minWidth: 1100, minHeight: 640)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    // Re-check after the user returns from System Settings.
                    permissions.refresh()
                    // Immediately pick up any changes a `diarize mcp` process made
                    // while we were in the background, and resume change polling.
                    library.appDidBecomeActive()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                    library.appDidResignActive()
                }
                .modifier(MainWindowOpenerBridge())
                .withHostingWindow { window in
                    guard let window else { return }
                    if let statusBar {
                        statusBar.setWindow(window)
                    } else {
                        statusBar = StatusBarController(library: library, window: window)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Recording …") { library.openImportDialog() }
                    .keyboardShortcut("o")
                Button("Reload Library") { library.reload() }
                    .keyboardShortcut("r")
            }
            CommandGroup(after: .toolbar) {
                Button(autoMode.isActive ? "Exit Auto Recording Mode" : "Auto Recording Mode") {
                    autoMode.isActive ? autoMode.exit() : autoMode.enter()
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(!autoMode.isActive && !permissions.allGranted)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(library)
        }
    }
}
