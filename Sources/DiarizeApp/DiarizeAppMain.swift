import AppKit
import SwiftUI
import DiarizeCore

@main
struct DiarizeAppMain: App {
    @StateObject private var library = LibraryViewModel()
    @StateObject private var permissions = PermissionsManager()
    @StateObject private var autoMode = AutoModeController()
    // Stored as a property so ARC keeps it alive for the lifetime of the app.
    @State private var statusBar: StatusBarController?

    init() {
        // SwiftPM executables default to background-tool (no Dock icon, no window focus).
        // Promote to a foreground app so the window appears and gets focus.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("diarize") {
            RootView()
                .environmentObject(library)
                .environmentObject(permissions)
                .environmentObject(autoMode)
                .frame(minWidth: 1000, minHeight: 600)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    // Re-check after the user returns from System Settings.
                    permissions.refresh()
                }
                .withHostingWindow { window in
                    if statusBar == nil, let window {
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
